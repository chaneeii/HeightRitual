import CoreImage
import UIKit
import Vision

/// Cuts the child out of the photo and crops tightly from the top of the head to the feet.
///
/// Because the crop starts at the head and ends at the feet, the wall view can show the
/// photo life-size without any camera calibration: it scales the cut-out so its height
/// equals the height typed in for that record.
enum PersonCutout {
    enum CutoutError: LocalizedError {
        case noPerson, render

        var errorDescription: String? {
            switch self {
            case .noPerson:
                return "No person was found in the photo. Make sure the whole body, from head to feet, is in the frame."
            case .render:
                return "The photo could not be processed. Try again."
            }
        }
    }

    static func make(from photo: UIImage) async throws -> UIImage {
        try await Task.detached(priority: .userInitiated) {
            try PersonCutout.cut(photo)
        }.value
    }

    private static func cut(_ photo: UIImage) throws -> UIImage {
        guard let cgImage = normalized(photo).cgImage else { throw CutoutError.render }

        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        guard let mask = request.results?.first?.pixelBuffer,
              let box = boundingBox(of: mask) else { throw CutoutError.noPerson }

        let image = CIImage(cgImage: cgImage)
        let maskImage = CIImage(cvPixelBuffer: mask)
        let sx = image.extent.width / maskImage.extent.width
        let sy = image.extent.height / maskImage.extent.height
        let scaledMask = maskImage.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

        guard let blend = CIFilter(name: "CIBlendWithMask") else { throw CutoutError.render }
        blend.setValue(image, forKey: kCIInputImageKey)
        blend.setValue(CIImage(color: .clear).cropped(to: image.extent), forKey: kCIInputBackgroundImageKey)
        blend.setValue(scaledMask, forKey: kCIInputMaskImageKey)
        guard let output = blend.outputImage else { throw CutoutError.render }

        // The box is in mask pixels with the origin at the top left; Core Image uses bottom left.
        let crop = CGRect(x: box.minX * sx,
                          y: image.extent.height - box.maxY * sy,
                          width: box.width * sx,
                          height: box.height * sy).integral

        let context = CIContext()
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let result = context.createCGImage(output, from: crop, format: .RGBA8, colorSpace: colorSpace)
        else { throw CutoutError.render }
        return UIImage(cgImage: result)
    }

    /// Smallest rectangle around the person in the mask, ignoring stray pixels.
    private static func boundingBox(of mask: CVPixelBuffer) -> CGRect? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }

        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let rowBytes = CVPixelBufferGetBytesPerRow(mask)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let minPixelsPerRow = max(2, width / 200)

        var minX = width, maxX = -1, minY = height, maxY = -1
        for y in 0..<height {
            let row = pixels + y * rowBytes
            var count = 0, rowMin = width, rowMax = -1
            for x in 0..<width where row[x] > 128 {
                count += 1
                rowMin = min(rowMin, x)
                rowMax = max(rowMax, x)
            }
            guard count >= minPixelsPerRow else { continue }
            minY = min(minY, y)
            maxY = max(maxY, y)
            minX = min(minX, rowMin)
            maxX = max(maxX, rowMax)
        }
        guard maxX > minX, maxY > minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// Bakes the EXIF orientation into the pixels so Vision and Core Image see an upright picture.
    private static func normalized(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
