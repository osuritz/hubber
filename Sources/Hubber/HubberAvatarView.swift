import AppKit
import SwiftUI

// MARK: - Avatar sizes (per primitives.jsx)

enum AvatarSize: CGFloat {
    /// Row avatar — 36pt
    case row = 36
    /// Reviewer stack — 24pt
    case reviewer = 24
    /// Compact / inline — 20pt
    case compact = 20

    var dotSize: CGFloat {
        max(8, (rawValue * 0.30).rounded())
    }

    var fontRatio: CGFloat {
        0.40
    }
}

// MARK: - AvatarView

struct AvatarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage?

    let user: GitHubUser
    /// Point size for the avatar circle. Use AvatarSize.xxx.rawValue or pass any CGFloat.
    let size: CGFloat
    /// Optional reviewer state dot overlay (bottom-right).
    var reviewerState: ReviewerState?
    /// Optional role descriptor for accessibility (e.g. "author"). Nil = omitted from label.
    var accessibilityRole: String? = nil

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            circle
            if let reviewerState {
                stateDot(state: reviewerState)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [user.login, accessibilityRole, reviewerState.map(AccessibilityText.reviewerPhrase)]
                .compactMap { $0 }.joined(separator: ", ")
        )
        .task(id: user.avatarURL) {
            guard let url = user.avatarURL else { return }
            // withTaskCancellationHandler ensures that when the .task is cancelled
            // (row disappeared) we cancel the in-flight network request too.
            await withTaskCancellationHandler {
                image = await AvatarCache.shared.image(for: url)
            } onCancel: {
                if let url = user.avatarURL {
                    Task { @MainActor in
                        AvatarCache.shared.cancelFetch(for: url)
                    }
                }
            }
        }
    }

    // MARK: Private

    @ViewBuilder
    private var circle: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(
                        HubberAppearance.avatarStroke(for: colorScheme),
                        lineWidth: 0.5
                    )
                }
        } else {
            Text(user.initials)
                .font(.system(size: (size * 0.40).rounded(), weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(user.color, in: Circle())
                .overlay {
                    Circle().stroke(.black.opacity(0.18), lineWidth: 0.5)
                }
        }
    }

    @ViewBuilder
    private func stateDot(state: ReviewerState) -> some View {
        let dotSize = max(8, (size * 0.30).rounded())
        let isHollow = state == .pending

        if isHollow {
            // Pending: hollow ring (no fill)
            Circle()
                .stroke(HubberDesign.rvPending, lineWidth: 1.5)
                .frame(width: dotSize, height: dotSize)
                .background(HubberDesign.materialSolid, in: Circle())
                .overlay {
                    Circle().stroke(HubberDesign.materialSolid, lineWidth: 1.5)
                }
                .offset(x: 1, y: 1)
        } else if let fillColor = HubberDesign.reviewerColor(for: state) {
            Circle()
                .fill(fillColor)
                .frame(width: dotSize, height: dotSize)
                .overlay {
                    Circle().stroke(HubberDesign.materialSolid, lineWidth: 1.5)
                }
                .offset(x: 1, y: 1)
        }
    }
}
