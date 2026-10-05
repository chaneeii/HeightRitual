import SwiftUI
import UIKit

/// A member's profile picture: their photo, or the first letter of their name in their colour.
struct AvatarView: View {
    let member: Member
    var size: CGFloat = 44
    /// A photo chosen in A1 but not saved yet; `showsPhoto` false previews "no photo".
    var pendingPhoto: UIImage?
    var showsPhoto = true
    @Environment(AppState.self) private var state

    var body: some View {
        Group {
            if showsPhoto, let image = pendingPhoto ?? storedPhoto {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Palette.color(member.colorIndex)
                    Text(verbatim: member.initial)
                        .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var storedPhoto: UIImage? {
        state.store.mediaURL(member.photoFile).flatMap { UIImage(contentsOfFile: $0.path) }
    }
}

extension UIImage {
    /// A JPEG no larger than `maxSide` on its long side, for profile photos.
    func profileJPEG(maxSide: CGFloat = 512) -> Data? {
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let resized = UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.85)
    }
}
