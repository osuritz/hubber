import SwiftUI

/// Add-account flow: provider picker -> github.com device flow or host + PAT form.
struct AddAccountView: View {
    @Environment(\.colorScheme) private var colorScheme

    // Owned (not observed): created once and survives parent re-renders. HubberStore re-broadcasts
    // every connection's objectWillChange, so an @ObservedObject built inline in the .sheet closure
    // would be rebuilt at .picker mid-flow (and the .added transition would be orphaned).
    @StateObject private var controller: AddAccountController
    var onDone: () -> Void
    /// Called with `true` while this sheet is on screen and `false` when it leaves, so the host can
    /// pin the popover open (browser hops during device-flow / "create a token" must not dismiss it).
    var onActiveChange: (Bool) -> Void

    init(
        policy: ProviderAccessPolicy,
        isDuplicate: @escaping (ConnectionID) -> Bool,
        addAccount: @escaping (ConnectionID, StoredToken, AuthenticatedUser) async throws -> Void,
        onActiveChange: @escaping (Bool) -> Void,
        onDone: @escaping () -> Void
    ) {
        _controller = StateObject(
            wrappedValue: AddAccountController(policy: policy, isDuplicate: isDuplicate, addAccount: addAccount)
        )
        self.onActiveChange = onActiveChange
        self.onDone = onDone
    }

    @State private var serverURL = ""
    @State private var token = ""
    @State private var usePATForGitHub = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            // Stable content height across stages so the spinner → success transition doesn't
            // resize the sheet mid-animation (which dropped the success animation on the fast
            // PAT path; the slow device-flow path didn't resize as much).
            Group {
                switch controller.stage {
                case .picker:
                    providerPicker
                case let .form(provider):
                    if provider == .gitHubDotCom, !usePATForGitHub {
                        gitHubDotComStart
                    } else {
                        patForm(provider: provider)
                    }
                case .authenticating:
                    ProgressView("Connecting...")
                        .frame(maxWidth: .infinity)
                case let .deviceCode(authorization):
                    deviceCode(authorization)
                case let .failed(message):
                    errorState(message)
                case let .added(id):
                    successState(login: id.login)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 188, alignment: .center)
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            serverURL = controller.selectedProvider.defaultServerURL
            onActiveChange(true)
        }
        .onDisappear {
            onActiveChange(false)
        }
    }

    private var header: some View {
        HStack {
            Text("Add account")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HubberDesign.text)

            Spacer()

            Button("Cancel") {
                controller.cancel()
                onDone()
            }
            .buttonStyle(.plain)
            .foregroundStyle(HubberDesign.text2)
        }
    }

    private var providerPicker: some View {
        VStack(spacing: 8) {
            ForEach(AddAccountProvider.allCases) { provider in
                Button {
                    usePATForGitHub = false
                    serverURL = provider.defaultServerURL
                    token = ""
                    controller.choose(provider)
                } label: {
                    HStack {
                        Text(provider.title)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundStyle(HubberDesign.text3)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(HubberDesign.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var gitHubDotComStart: some View {
        VStack(spacing: 12) {
            Button {
                Task { await controller.beginDeviceFlow() }
            } label: {
                Text("Sign in with GitHub")
                    .font(.system(size: 13.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(SignInButtonStyle(colorScheme: colorScheme))

            Button("Use a token instead") {
                usePATForGitHub = true
                serverURL = AddAccountProvider.gitHubDotCom.defaultServerURL
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(HubberDesign.text2)
        }
    }

    private func patForm(provider: AddAccountProvider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if provider != .gitHubDotCom {
                Text("Server URL")
                    .hubberFont(.settingsSub)
                    .foregroundStyle(HubberDesign.text2)
                TextField("https://...", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
            }

            Text("Personal access token")
                .hubberFont(.settingsSub)
                .foregroundStyle(HubberDesign.text2)
            SecureField("Paste your token", text: $token)
                .textFieldStyle(.roundedBorder)

            Link("Create a token", destination: tokenHelpURL(provider))
                .font(.system(size: 11))
                .foregroundStyle(HubberDesign.accent)

            Button {
                Task {
                    await controller.connectWithToken(
                        provider: provider,
                        serverURL: serverURL,
                        token: token
                    )
                }
            } label: {
                Text("Connect")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(SignInButtonStyle(colorScheme: colorScheme))
            .disabled(token.isEmpty || (provider != .gitHubDotCom && serverURL.isEmpty))
        }
    }

    private func deviceCode(_ authorization: GitHubDeviceAuthorization) -> some View {
        VStack(spacing: 12) {
            Text("Enter this code at \(authorization.verificationURI.host ?? "github.com").")
                .font(.system(size: 12.5))
                .foregroundStyle(HubberDesign.text2)

            Text(authorization.userCode)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(HubberDesign.text)

            HStack(spacing: 10) {
                Button("Copy code") {
                    controller.copyDeviceCode()
                }
                Button("Open GitHub") {
                    controller.openDeviceVerificationPage()
                }
            }

            Button("Cancel") {
                controller.cancel()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(HubberDesign.text2)
        }
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(HubberDesign.sloRed.fg)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Try again") {
                controller.reset()
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Plays the success animation in the dialog, then materializes the account (deferred via
    /// `controller.finalize()` so the new connection's sign-in/refresh churn happens as the dialog
    /// closes — never during the animation) and dismisses.
    private func successState(login: String) -> some View {
        SignInSuccessScreen(login: login)
            .frame(maxWidth: .infinity, minHeight: 150)
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.4))
                    await controller.finalize()
                    onDone()
                }
            }
    }

    private func tokenHelpURL(_: AddAccountProvider) -> URL {
        // Hubber's token-permission guide — covers all three providers, the minimal scopes to
        // grant (Hubber is read-only), and links to each provider's token-creation page. See #99.
        URL(string: "https://github.com/osuritz/hubber/blob/main/docs/token-permissions.md")!
    }
}
