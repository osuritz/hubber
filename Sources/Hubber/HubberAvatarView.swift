import AppKit
import SwiftUI

struct AvatarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage?

    let user: GitHubUser
    let size: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(user.initials)
                    .font(.system(size: round(size * 0.42), weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(user.color, in: Circle())
            }
        }
        .overlay {
            Circle().stroke(HubberAppearance.avatarStroke(for: colorScheme), lineWidth: 0.5)
        }
        .task(id: user.avatarURL) {
            guard let url = user.avatarURL else { return }
            image = await AvatarCache.shared.image(for: url)
        }
    }
}
