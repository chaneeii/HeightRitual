import AVFoundation
import SwiftUI

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
