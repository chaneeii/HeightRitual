@preconcurrency import AVFoundation
import CoreImage
import UIKit
import VideoToolbox
import Vision

/// Milestone 6 (SPEC 9 steps 2 to 7): person segmentation for every frame, one crop for the
/// whole clip, HEVC with alpha about 1280 px tall, a poster, and the height from the head top.
/// The filmed clip is kept too, so Memory can show it with its background.
///
/// Not yet run on a device: segmentation time for 150 frames and the alpha video are unverified.
struct VideoCutout: ClipProcessing {
    /// The person stands still this long at the start; it is the reference for the height.
    static let referenceSeconds = 0.5
    static let maxClipHeight = 1280.0
    /// Fewer frames with a person than this, and the clip counts as "nobody found".
    static let minPersonShare = 0.3

    func process(movie: URL?, camera: CameraPosition?,
                 progress: @escaping @MainActor (Double) -> Void) async throws -> ProcessedClip? {
        // Simulator, or the camera gave nothing: a clip without video, so the flow can go on.
        guard let movie, FileManager.default.fileExists(atPath: movie.path) else {
            await progress(1)
            return ProcessedClip()
        }
        let temp = FileManager.default.temporaryDirectory
        let raw = temp.appendingPathComponent("raw-\(UUID().uuidString).mov")
        try FileManager.default.copyItem(at: movie, to: raw)

        let asset = AVURLAsset(url: raw)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
        let transform = try await track.load(.preferredTransform)
        let natural = try await track.load(.naturalSize)
        let duration = try await asset.load(.duration).seconds
        let fps = Double(try await track.load(.nominalFrameRate))
        let hasSound = !((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty
        let orientation = Self.orientation(of: transform)
        let turned = orientation == .right || orientation == .left
        let width = Double(turned ? natural.height : natural.width)     // upright frame
        let height = Double(turned ? natural.width : natural.height)
        let expectedFrames = max(1, duration * max(fps, 1))
        let context = CIContext()

        // Pass 1: a mask and a person box per frame; the poster from the reference time.
        var masks: [CVPixelBuffer?] = []
        var boxes: [CGRect?] = []
        var times: [CMTime] = []
        var posterURL: URL?
        try await Self.readFrames(asset: asset, track: track) { buffer, time in
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .balanced
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation).perform([request])
            let mask = request.results?.first.flatMap { Self.copy($0.pixelBuffer) }
            masks.append(mask)
            boxes.append(mask.flatMap(Self.personBox))
            times.append(time)
            if posterURL == nil, time.seconds >= Self.referenceSeconds {
                posterURL = Self.writePoster(CIImage(cvPixelBuffer: buffer).oriented(orientation), context: context)
            }
            let done = Double(times.count)
            Task { @MainActor in progress(min(0.5, 0.5 * done / expectedFrames)) }
        }

        let found = boxes.compactMap { $0 }
        let reference = zip(times, boxes).filter { $0.0.seconds <= Self.referenceSeconds }.compactMap { $0.1 }
        var clip = ProcessedClip(posterURL: posterURL, hasSound: hasSound, rawVideoURL: raw,
                                 rawAspect: width / height, duration: duration)
        guard Double(found.count) >= Double(max(1, boxes.count)) * Self.minPersonShare,
              !reference.isEmpty || !found.isEmpty else {
            clip.personFound = false
            await progress(1)
            return clip
        }

        // Reference: median head top and feet over the first half second (SPEC 9 step 2).
        let ref = reference.isEmpty ? Array(found.prefix(15)) : reference
        let headY = Self.median(ref.map { Double($0.minY) })
        let feetY = Self.median(ref.map { Double($0.maxY) })
        clip.headY = headY
        clip.feetY = feetY
        clip.estimatedMM = HeightEstimator.estimateMM(headY: headY, camera: camera)
        clip.rawBodyRatio = feetY - headY
        clip.rawFloorRatio = 1 - feetY

        // One crop for the whole clip: the union of the person boxes, a little padding (step 5).
        var union = found[0]
        for box in found { union = union.union(box) }
        let pad = 0.03
        let top = max(0, Double(union.minY) - pad), bottom = min(1, Double(union.maxY) + pad)
        let left = max(0, Double(union.minX) - pad * height / width)
        let right = min(1, Double(union.maxX) + pad * height / width)
        let cropPx = CGRect(x: left * width, y: (1 - bottom) * height,          // Core Image: origin bottom-left
                            width: (right - left) * width, height: (bottom - top) * height)
        let scale = min(1, Self.maxClipHeight / cropPx.height)
        let outWidth = Int(cropPx.width * scale / 2) * 2
        let outHeight = Int(cropPx.height * scale / 2) * 2
        clip.bodyRatio = (feetY - headY) / (bottom - top)
        clip.floorRatio = (bottom - feetY) / (bottom - top)
        clip.clipAspect = Double(outWidth) / Double(outHeight)

        // Pass 2: blend each frame with its mask, crop, write HEVC with alpha (step 4 and 6).
        let cut = FileManager.default.temporaryDirectory.appendingPathComponent("cut-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: cut, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
            AVVideoWidthKey: outWidth,
            AVVideoHeightKey: outHeight,
            AVVideoCompressionPropertiesKey: [kVTCompressionPropertyKey_TargetQualityForAlpha as String: 0.75],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outWidth,
            kCVPixelBufferHeightKey as String: outHeight,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: times.first ?? .zero)

        let bounds = CGRect(x: 0, y: 0, width: outWidth, height: outHeight)
        let clear = CIImage(color: .clear).cropped(to: bounds)
        var index = 0
        var lastMask: CVPixelBuffer?
        try await Self.readFrames(asset: asset, track: track) { buffer, time in
            defer { index += 1 }
            guard index < masks.count else { return }
            if let mask = masks[index] { lastMask = mask }
            guard let mask = lastMask, let pool = adaptor.pixelBufferPool else { return }
            let image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
            let maskImage = CIImage(cvPixelBuffer: mask)
            let scaledMask = maskImage.transformed(by: CGAffineTransform(
                scaleX: image.extent.width / maskImage.extent.width,
                y: image.extent.height / maskImage.extent.height))
            let person = image.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: image.extent),
                kCIInputMaskImageKey: scaledMask,
            ])
            let framed = person.cropped(to: cropPx)
                .transformed(by: CGAffineTransform(translationX: -cropPx.minX, y: -cropPx.minY))
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .composited(over: clear)
            var out: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out)
            guard let out else { return }
            context.render(framed, to: out, bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            adaptor.append(out, withPresentationTime: time)
            let done = Double(index + 1) / Double(max(1, masks.count))
            Task { @MainActor in progress(0.5 + 0.5 * done) }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        clip.videoURL = cut
        await progress(1)
        return clip
    }

    // MARK: Helpers

    /// Calls `body` for every decoded frame (BGRA) of the video track, in order.
    private static func readFrames(asset: AVAsset, track: AVAssetTrack,
                                   _ body: (CVPixelBuffer, CMTime) async throws -> Void) async throws {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            try await body(buffer, CMSampleBufferGetPresentationTimeStamp(sample))
        }
    }

    /// Upright orientation from the track's transform (the camera writes portrait as a rotation).
    static func orientation(of transform: CGAffineTransform) -> CGImagePropertyOrientation {
        let angle = atan2(transform.b, transform.a) * 180 / .pi
        switch angle {
        case 45..<135: return .right
        case -135 ..< -45: return .left
        case 135...180, -180 ..< -135: return .down
        default: return .up
        }
    }

    /// The person's box in a mask, as fractions with the origin top-left. Nil when empty.
    static func personBox(_ mask: CVPixelBuffer) -> CGRect? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let width = CVPixelBufferGetWidth(mask), height = CVPixelBufferGetHeight(mask)
        let stride = CVPixelBufferGetBytesPerRow(mask)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in Swift.stride(from: 0, to: height, by: 2) {
            let row = pixels + y * stride
            for x in Swift.stride(from: 0, to: width, by: 2) where row[x] > 127 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        let w = Double(width), h = Double(height)
        return CGRect(x: Double(minX) / w, y: Double(minY) / h,
                      width: Double(maxX - minX + 1) / w, height: Double(maxY - minY + 1) / h)
    }

    /// Vision may reuse its buffers, so each mask is copied.
    private static func copy(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        var copy: CVPixelBuffer?
        CVPixelBufferCreate(nil, CVPixelBufferGetWidth(source), CVPixelBufferGetHeight(source),
                            CVPixelBufferGetPixelFormatType(source), nil, &copy)
        guard let copy else { return nil }
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(copy, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        let rows = CVPixelBufferGetHeight(source)
        let from = CVPixelBufferGetBytesPerRow(source), to = CVPixelBufferGetBytesPerRow(copy)
        guard let src = CVPixelBufferGetBaseAddress(source), let dst = CVPixelBufferGetBaseAddress(copy) else { return nil }
        for row in 0..<rows {
            memcpy(dst + row * to, src + row * from, min(from, to))
        }
        return copy
    }

    private static func writePoster(_ image: CIImage, context: CIContext) -> URL? {
        guard let cg = context.createCGImage(image, from: image.extent),
              let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.8) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poster-\(UUID().uuidString).jpg")
        return (try? data.write(to: url)) != nil ? url : nil
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }
}
