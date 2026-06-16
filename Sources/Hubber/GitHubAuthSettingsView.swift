import SwiftUI

struct GitHubAuthSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var store: HubberStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            switch store.authState {
            case .restoring:
                restoringView
            case .signedOut:
                signedOutView
            case let .waitingForUser(authorization):
                waitingForUserView(authorization: authorization)
            case let .signedIn(login):
                signedInView(login: login)
            case .sessionExpired:
                sessionExpiredView
            case let .error(message):
                errorView(message: message)
            }
        }
    }

    private var restoringView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Checking GitHub sign-in")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var signedOutView: some View {
        Button {
            store.startSignIn()
        } label: {
            Label("Sign in with GitHub", systemImage: "person.crop.circle.badge.checkmark")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.small)
    }

    private var sessionExpiredView: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Session expired — sign in again")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.hubberWarning)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                store.startSignIn()
            } label: {
                Label("Sign in with GitHub", systemImage: "person.crop.circle.badge.checkmark")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
        }
    }

    private func waitingForUserView(authorization: GitHubDeviceAuthorization) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(authorization.userCode)
                    .font(.system(size: 18, weight: .semibold).monospaced())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        HubberAppearance.chipFill(for: colorScheme),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )

                Button {
                    store.copyDeviceCode()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .help("Copy code")

                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    store.openDeviceVerificationPage()
                } label: {
                    Label("Open GitHub", systemImage: "safari")
                }

                Button("Cancel") {
                    store.cancelSignIn()
                }
            }
            .controlSize(.small)

            Text("Enter this code at github.com/login/device.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func signedInView(login: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.hubberSuccess)

            Text("@\(login)")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button("Sign out") {
                store.signOut()
            }
            .controlSize(.small)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.hubberError)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Try again") {
                    store.startSignIn()
                }

                Button("Clear") {
                    store.signOut()
                }
            }
            .controlSize(.small)
        }
    }
}
