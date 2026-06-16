import SwiftUI

struct ReauthPromptRow: View {
    @ObservedObject var store: HubberStore

    var body: some View {
        VStack(spacing: 12) {
            // Amber lock icon (non-color cue: lock shape + "expired" label)
            ZStack {
                Circle()
                    .fill(HubberDesign.sloAmber.bg)
                    .overlay {
                        Circle().stroke(HubberDesign.sloAmber.border, lineWidth: 0.5)
                    }
                    .frame(width: 48, height: 48)

                Image(systemName: "lock.fill")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(HubberDesign.sloAmber.fg)
            }

            Text("Session expired")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HubberDesign.text)

            Text("Your GitHub session has expired. Sign in again to refresh pull requests.")
                .font(HubberType.secondary)
                .foregroundStyle(HubberDesign.text2)
                .multilineTextAlignment(.center)

            Button {
                store.startSignIn()
            } label: {
                Label("Sign in again", systemImage: "person.crop.circle.badge.checkmark")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
    }
}
