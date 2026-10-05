import AVFoundation
import SwiftUI

/// M2: camera preview with the foot guide, one red button. Ready, countdown 3-2-1, filming.
struct FilmView: View {
    let film: FilmState
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 12) {
            SetupBanner()

            if CameraController.isRefused {
                ContentUnavailableView {
                    Label("The camera is not allowed", systemImage: "video.slash")
                } description: {
                    Text("Height Ritual needs the camera to film the clip.")
                } actions: {
                    Button("Open permissions") {
                        state.openSettings()
                        state.openSettingsPage(.permissions)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            } else {
                ZStack {
                    CameraPreview(session: state.cameraSession)
                    FootGuideOverlay(guide: state.footGuide, accent: Palette.color(state.currentMember?.colorIndex ?? 0))
                        .opacity(film == .ready ? 1 : 0)
                    statusOverlay
                }
                .aspectRatio(FootGuide.frameAspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(film == .ready ? LocalizedStringKey("Heels on the line, back against the wall") : " ")
                    .font(.headline)

                recordButton
            }
        }
        .padding()
        .readableColumn()
        .navigationTitle(state.currentMember.map { L("Film \($0.name)") } ?? L("Film"))
        .navigationBarTitleDisplayMode(.inline)
        // Countdown and filming end with Stop, not by leaving the screen.
        .navigationBarBackButtonHidden(film != .ready)
        .tabBarFromRoute()
        .screenChrome()
    }

    @ViewBuilder private var statusOverlay: some View {
        switch film {
        case .ready:
            EmptyView()
        case .countdown(let n):
            Text("\(n)")
                .font(.system(size: 120, weight: .light, design: .serif))
                .foregroundStyle(.white)
                .shadow(radius: 8)
        case .filming(let left):
            VStack {
                HStack(spacing: 8) {
                    Circle().fill(Color.red).frame(width: 14, height: 14)
                    Text("\(left) s left").font(.headline.monospacedDigit())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(.top, 12)
                Spacer()
            }
        }
    }

    /// One red button: Record when ready, Stop during the countdown and filming.
    private var recordButton: some View {
        BigButton(title: film == .ready ? "Record" : "Stop",
                  systemImage: film == .ready ? "record.circle" : "stop.fill",
                  prominent: true, tint: .red) {
            state.handle(.record)
        }
    }
}

/// Floor line with two foot marks and the standing outline, drawn in camera-frame fractions.
struct FootGuideOverlay: View {
    let guide: FootGuide
    let accent: Color

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let floor = guide.floorY * h
            let cx = guide.centerX * w
            let cmX = guide.cmX * w

            var line = Path()
            line.move(to: CGPoint(x: 0, y: floor))
            line.addLine(to: CGPoint(x: w, y: floor))
            ctx.stroke(line, with: .color(.white.opacity(0.9)), lineWidth: 3)

            // Two feet, about 25 cm long and 10 cm wide, heels on the line. Seen from the front,
            // a foot is a short bar on the floor.
            for side in [-1.0, 1.0] {
                let rect = CGRect(x: cx + (side < 0 ? -12 : 2) * cmX, y: floor - 3 * guide.cmY * h,
                                  width: 10 * cmX, height: 3 * guide.cmY * h)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.5 * cmX), with: .color(accent.opacity(0.8)))
            }

            let outline = PersonOutline.path(heightPt: (guide.floorY - guide.topY) * h, centerX: cx, floorY: floor)
            ctx.stroke(outline, with: .color(accent), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Foot guide: stand with your heels on the line")
    }
}
