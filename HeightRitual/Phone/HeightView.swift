import SwiftUI

/// M3: the clip on repeat, the height in a large field, steps to correct it, Save and Retake.
/// Every button sends the controller's event: - and + are knob steps, the outer ones Left / Right.
struct HeightView: View {
    let height: HeightState
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 16) {
            switch height {
            case .cuttingOut(let progress):
                Spacer()
                ProgressView(value: progress) {
                    Text("Preparing the clip")
                }
                .padding(.horizontal, 40)
                Spacer()
                BigButton(title: "Retake") { state.handle(.cancel) }

            case .noPerson:
                ContentUnavailableView {
                    Label("Nobody found in the video", systemImage: "person.fill.questionmark")
                } description: {
                    Text("Stand with your heels on the line and film again.")
                }
                BigButton(title: "Retake", prominent: true) { state.handle(.cancel) }
                if state.draft?.clip.rawVideoURL != nil {
                    // Testing without a person: the clip is kept as filmed, the height set by hand.
                    BigButton(title: "Use this clip anyway") { state.useClipWithoutPerson() }
                }

            case .editing:
                editing
            }
        }
        .padding()
        .readableColumn()
        .navigationTitle(state.currentMember?.name ?? L("Height"))
        .navigationBarTitleDisplayMode(.inline)
        .tabBarFromRoute()
        .screenChrome()
    }

    @ViewBuilder private var editing: some View {
        let unit = state.settings.unit
        let mm = state.draft?.heightMM

        if let poster = state.draft?.clip.posterURL, let image = UIImage(contentsOfFile: poster.path) {
            ReferencePhoto(image: image, clip: state.draft?.clip, heightMM: mm, camera: state.settings.camera)
                .frame(maxHeight: .infinity)
        } else if let url = state.draft?.clip.rawVideoURL ?? state.draft?.clip.videoURL {
            LoopingVideo(url: url)
                .aspectRatio(FootGuide.frameAspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxHeight: .infinity)
        } else {
            // No clip (simulator): the wall copy, where the dashed line follows the number.
            WallCopy()
                .frame(maxHeight: .infinity)
        }

        VStack(spacing: 4) {
            Text(verbatim: mm.map { HeightFormatter.text($0, unit: unit) } ?? "–")
                .font(.system(size: 56, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText())
                .animation(.snappy, value: mm)
            if state.showsEstimateNote {
                Text("Estimated from the video. It can be a few centimetres off. Check with a tape and correct it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if mm == nil {
                Text("Set the height with - and +")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        HStack(spacing: 8) {
            step(unit == .cm ? "-1" : "-1 in", .left)
            step(unit == .cm ? "-0.5" : "-1/4", .knob(-1))
            step(unit == .cm ? "+0.5" : "+1/4", .knob(1))
            step(unit == .cm ? "+1" : "+1 in", .right)
        }

        HStack(spacing: 12) {
            BigButton(title: "Retake") { state.handle(.cancel) }
            BigButton(title: "Save", prominent: true) { state.handle(.confirm) }
                .disabled(mm == nil)
        }
    }

    private func step(_ label: String, _ event: ControlEvent) -> some View {
        Button {
            state.handle(event)
        } label: {
            Text(verbatim: label)
                .font(.headline.monospacedDigit())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}

/// The still from the reference half second with two lines: where the head top was found
/// (dotted) and where the height in the field is (dashed, follows - and +; needs the camera position).
private struct ReferencePhoto: View {
    let image: UIImage
    let clip: ProcessedClip?
    let heightMM: Int?
    let camera: CameraPosition?

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    let h = geo.size.height
                    if let head = clip?.headY {
                        line(at: head * h, width: geo.size.width, color: .white, dash: [3, 4])
                    }
                    if let camera, let mm = heightMM, camera.floorY > camera.y100 {
                        let y = camera.floorY - Double(mm) / 1000 * (camera.floorY - camera.y100)
                        line(at: y * h, width: geo.size.width, color: Color(red: 0.96, green: 0.50, blue: 0.42), dash: [10, 6])
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel("Photo from the clip with the head top marked")
    }

    private func line(at y: CGFloat, width: CGFloat, color: Color, dash: [CGFloat]) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dash))
        .shadow(color: .black.opacity(0.6), radius: 1)
    }
}
