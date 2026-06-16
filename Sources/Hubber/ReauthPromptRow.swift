import SwiftUI

struct ReauthPromptRow: View {
    @ObservedObject var store: HubberStore

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.hubberWarning)

            Text("Session expired")
                .font(.system(size: 13, weight: .semibold))

            Text("Your GitHub session has expired. Sign in again to refresh pull requests.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
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
