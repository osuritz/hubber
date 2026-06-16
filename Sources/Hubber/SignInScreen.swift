import SwiftUI

// MARK: - SignInScreen

/// Full-panel signed-out view shown when authState == .signedOut or .error.
/// Design ref: docs/design/github-macos-menu-app/project/popover.jsx `SignInScreen` ~line 132.
struct SignInScreen: View {
    @ObservedObject var store: HubberStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                // 64×64 rounded-square tile with pull-request icon
                appIcon

                // Title
                Text("Welcome to Hubber")
                    .font(.system(size: 19, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(HubberDesign.text)
                    .padding(.bottom, 8)

                // Body copy
                Text(
                    "Keep an eye on your PR reviews, CI, and drafts" +
                        " — right from the menu bar. Sign in to get started."
                )
                .font(.system(size: 12.5))
                .foregroundStyle(HubberDesign.text2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 264)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 24)

                // "Sign in with GitHub" button
                Button {
                    store.startSignIn()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 17, weight: .regular))
                        Text("Sign in with GitHub")
                            .font(.system(size: 13.5, weight: .semibold))
                            .tracking(-0.1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(SignInButtonStyle(colorScheme: colorScheme))
                .frame(maxWidth: 264)
                .padding(.bottom, 16)

                // Footnote
                HStack(spacing: 6) {
                    Image(systemName: "lock")
                        .font(.system(size: 12, weight: .regular))
                    Text("Read-only access to your pull requests")
                        .font(.system(size: 11))
                }
                .foregroundStyle(HubberDesign.text3)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 36)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark
                    ? Color(light: "#1f2328", dark: "#0d1117")
                    : Color(light: "#1f2328", dark: "#0d1117"))
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.30), radius: 11, y: 8)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                }

            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.bottom, 20)
    }
}

// MARK: - SignInButtonStyle

private struct SignInButtonStyle: ButtonStyle {
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                colorScheme == .dark
                    ? Color(light: "#f6f6f8", dark: "#f6f6f8")
                    : Color(light: "#1f2328", dark: "#1f2328"),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .foregroundStyle(
                colorScheme == .dark
                    ? Color(light: "#1f2328", dark: "#1f2328")
                    : Color.white
            )
            .shadow(color: .black.opacity(0.20), radius: 1.5, y: 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - DeviceCodeScreen

/// Full-panel device-code prompt shown when authState == .waitingForUser.
/// Reuses the same handlers as GitHubAuthSettingsView (openDeviceVerificationPage,
/// copyDeviceCode, cancelSignIn) — does NOT reinvent the auth state machine.
struct DeviceCodeScreen: View {
    @ObservedObject var store: HubberStore
    @Environment(\.colorScheme) private var colorScheme
    let authorization: GitHubDeviceAuthorization

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                // Step indicator icon
                ZStack {
                    Circle()
                        .fill(HubberDesign.accent.opacity(0.14))
                        .frame(width: 54, height: 54)

                    Image(systemName: "iphone.and.arrow.forward")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(HubberDesign.accent)
                }
                .padding(.bottom, 20)

                Text("Authorize with GitHub")
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(HubberDesign.text)
                    .padding(.bottom, 8)

                Text("Enter this code at github.com/login/device.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(HubberDesign.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 264)
                    .padding(.bottom, 20)

                // User code display + copy
                HStack(spacing: 10) {
                    Text(authorization.userCode)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HubberDesign.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            HubberDesign.fill,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(HubberDesign.sep, lineWidth: 0.5)
                        }

                    Button {
                        store.copyDeviceCode()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(HubberDesign.text2)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy code")
                }
                .padding(.bottom, 24)

                // Action buttons
                VStack(spacing: 10) {
                    Button {
                        store.openDeviceVerificationPage()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "safari")
                                .font(.system(size: 14))
                            Text("Open GitHub")
                                .font(.system(size: 13.5, weight: .semibold))
                                .tracking(-0.1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                    }
                    .buttonStyle(SignInButtonStyle(colorScheme: colorScheme))
                    .frame(maxWidth: 264)

                    Button("Cancel") {
                        store.cancelSignIn()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(HubberDesign.text2)
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 36)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - RestoringScreen

/// Full-panel loading indicator shown during auth restore (app launch).
struct RestoringScreen: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Signing in…")
                .font(.system(size: 12))
                .foregroundStyle(HubberDesign.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
