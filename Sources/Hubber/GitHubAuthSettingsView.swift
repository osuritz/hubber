import SwiftUI

struct GitHubAuthSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var store: HubberStore

    /// True when the provider access policy blocks github.com sign-in.
    private var isRestricted: Bool {
        !store.settings.providerAccessPolicy.canConnectGitHubDotCom
    }

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
        VStack(alignment: .leading, spacing: 6) {
            Button {
                store.startSignIn()
            } label: {
                Label("Sign in with GitHub", systemImage: "person.crop.circle.badge.checkmark")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
            .disabled(isRestricted)
            .opacity(isRestricted ? 0.45 : 1)

            if isRestricted {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .regular))
                    Text("Sign-in is restricted by your organization.")
                        .font(.system(size: 11))
                }
                .foregroundStyle(HubberDesign.text2)
            }
        }
    }

    private var sessionExpiredView: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Session expired — sign in again")
                .font(.system(size: 11.5))
                .foregroundStyle(Color.hubberWarning)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    store.startSignIn()
                } label: {
                    Label("Sign in with GitHub", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(isRestricted)
                .opacity(isRestricted ? 0.45 : 1)

                Button("Sign out") {
                    Task { await store.signOut() }
                }
            }
            .controlSize(.small)

            if isRestricted {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .regular))
                    Text("Sign-in is restricted by your organization.")
                        .font(.system(size: 11))
                }
                .foregroundStyle(HubberDesign.text2)
            }
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
        HStack(spacing: 10) {
            AvatarView(
                user: CodeHostUser(
                    login: login,
                    initials: initials(for: store.viewerName ?? login),
                    color: avatarColor(for: login),
                    avatarURL: store.viewerAvatarURL
                ),
                size: AvatarSize.row.rawValue
            )

            VStack(alignment: .leading, spacing: 1) {
                if let name = store.viewerName, !name.isEmpty {
                    Text(name)
                        .hubberFont(.title)
                        .foregroundStyle(HubberDesign.text)
                    Text("@\(login)")
                        .hubberFont(.secondary)
                        .foregroundStyle(HubberDesign.text2)
                } else {
                    Text("@\(login)")
                        .hubberFont(.title)
                        .foregroundStyle(HubberDesign.text)
                }
            }

            Spacer()

            Button("Sign out") {
                Task { await store.signOut() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Avatar helpers

    private func initials(for name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        if
            words.count >= 2,
            let first = words[0].first,
            let second = words[1].first {
            return "\(first)\(second)".uppercased()
        } else if let first = name.first {
            return String(first).uppercased()
        }
        return "?"
    }

    /// Deterministic hue from login — mirrors the GitHubProvider avatar color approach.
    private func avatarColor(for login: String) -> Color {
        let hue = Double(login.hashValue.magnitude % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.70)
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
                .disabled(isRestricted)
                .opacity(isRestricted ? 0.45 : 1)

                Button("Clear") {
                    Task { await store.signOut() }
                }
            }
            .controlSize(.small)

            if isRestricted {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .regular))
                    Text("Sign-in is restricted by your organization.")
                        .font(.system(size: 11))
                }
                .foregroundStyle(HubberDesign.text2)
            }
        }
    }
}
