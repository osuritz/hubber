import AppKit
import SwiftUI

// MARK: - Shared scaffold

/// Full-panel onboarding chrome: optional icon, title, body, content slot, and a step indicator.
/// Mirrors the SignInScreen layout so onboarding feels like the rest of the app.
struct OnboardingScaffold<Content: View>: View {
    let stepIndex: Int
    let stepCount: Int
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 40)
            Spacer()
            stepDots.padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<stepCount, id: \.self) { i in
                Capsule()
                    .fill(i == stepIndex ? HubberDesign.accent : HubberDesign.text3.opacity(0.35))
                    .frame(width: i == stepIndex ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(stepIndex + 1) of \(stepCount)")
    }
}

// MARK: - Welcome (#101)

struct OnboardingWelcomeStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var primaryFocused: Bool

    var body: some View {
        OnboardingScaffold(stepIndex: 0, stepCount: OnboardingCoordinator.Step.allCases.count) {
            VStack(spacing: 0) {
                appIcon
                Text("Welcome to Hubber")
                    .font(.system(size: 19, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(HubberDesign.text)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 8)
                Text("Keep an eye on your PR reviews, CI, and drafts — right from the menu bar. Let's get you set up.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(HubberDesign.text2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 264)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 24)
                Button { coordinator.advance() } label: {
                    Text("Get started")
                        .font(.system(size: 13.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                }
                .buttonStyle(SignInButtonStyle(colorScheme: colorScheme))
                .frame(maxWidth: 264)
                .focused($primaryFocused)
            }
        }
        .onAppear { primaryFocused = true }
    }

    /// The app's own icon — the canonical "Welcome to <App>" mark. Falls back to the brand
    /// menubar glyph on its tile when running outside a packaged `.app` (e.g. SwiftUI previews).
    private var appIcon: some View {
        Group {
            if isBundledApp {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.22), radius: 9, y: 5)
            } else {
                menubarGlyphTile
            }
        }
        .padding(.bottom, 20)
    }

    private var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Dark rounded tile carrying the bundled menubar "stamp" glyph (template, tinted white).
    private var menubarGlyphTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(light: "#1f2328", dark: "#0d1117"))
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.30), radius: 11, y: 8)
            if let glyph = Self.menubarGlyph {
                Image(nsImage: glyph)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }

    /// The bundled menubar glyph (vector PDF, template). Mirrors `AppDelegate.menubarGlyph()`.
    private static var menubarGlyph: NSImage? {
        guard
            let url = Bundle.module.url(forResource: "stamp-vector", withExtension: "pdf"),
            let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        return image
    }
}

// MARK: - Reusable secondary button

/// Secondary (non-primary) onboarding action button — equal size to the primary so the
/// choice is balanced (no dark pattern). Reused by the consent / notifications /
/// launch-at-login steps for their "Not now" action.
struct OnboardingSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .foregroundStyle(HubberDesign.text)
                .background(HubberDesign.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(HubberDesign.sep, lineWidth: 0.5)
                }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 264)
    }
}

// MARK: - Managed (MDM-locked) notice

/// Shown in place of a step's choice when an MDM profile forces the setting — the user can't
/// change it, only acknowledge and continue. Reused by the consent and launch-at-login steps.
struct OnboardingManagedNotice: View {
    let message: String
    let onContinue: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                Text(message)
                    .font(.system(size: 11))
            }
            .foregroundStyle(HubberDesign.text2)

            Button(action: onContinue) {
                Text("Continue")
                    .font(.system(size: 13.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(SignInButtonStyle(colorScheme: colorScheme))
            .frame(maxWidth: 264)
        }
    }
}

// MARK: - Analytics consent (#102)

struct OnboardingConsentStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject var store: HubberStore
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var primaryFocused: Bool

    /// When MDM forces analyticsEnabled, the choice is not the user's to make — show the
    /// managed state and let them continue (the gate already reflects the forced value).
    private var isManaged: Bool {
        store.settings.isLocked(ManagedKey.analyticsEnabled)
    }

    var body: some View {
        OnboardingScaffold(stepIndex: 1, stepCount: OnboardingCoordinator.Step.allCases.count) {
            VStack(spacing: 0) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(HubberDesign.accent)
                    .padding(.bottom, 16)

                Text("Help improve Hubber?")
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(HubberDesign.text)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 8)

                Text(
                    "Share anonymous usage data — counts and basic interactions only. "
                        + "Never repo names, PR titles, logins, or any personal data. "
                        + "You can change this anytime in Settings."
                )
                .font(.system(size: 12.5))
                .foregroundStyle(HubberDesign.text2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 264)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

                if isManaged {
                    OnboardingManagedNotice(
                        message: store.settings.analyticsEnabled
                            ? "Analytics is enabled by your organization."
                            : "Analytics is disabled by your organization."
                    ) {
                        coordinator.advance()
                    }
                } else {
                    choiceButtons
                }

                Button("Read our Privacy Policy") {
                    NSWorkspace.shared.open(PrivacyLinks.privacyPolicy)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(HubberDesign.accent)
                .padding(.top, 14)
            }
        }
        .onAppear { if !isManaged { primaryFocused = true } }
    }

    private var choiceButtons: some View {
        VStack(spacing: 10) {
            Button {
                store.settings.analyticsEnabled = true
                coordinator.advance()
            } label: {
                Text("Enable analytics")
                    .font(.system(size: 13.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(SignInButtonStyle(colorScheme: colorScheme))
            .frame(maxWidth: 264)
            .focused($primaryFocused)

            OnboardingSecondaryButton(title: "Not now") {
                store.settings.analyticsEnabled = false
                coordinator.advance()
            }
        }
    }

}

// MARK: - Connect (#105)

struct OnboardingConnectStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject var store: HubberStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingAdd = false
    @FocusState private var primaryFocused: Bool

    private var isRestricted: Bool {
        !store.settings.providerAccessPolicy.canConnectGitHubDotCom
    }

    var body: some View {
        OnboardingScaffold(stepIndex: 2, stepCount: OnboardingCoordinator.Step.allCases.count) {
            content
        }
        .onAppear {
            // Skip the required connect step only when an account is actually signed in — NOT
            // merely when a Connection object exists. restoreAllConnections() builds a tokenless
            // legacy Connection on a fresh install, so checking `connections.isEmpty` would
            // wrongly skip connecting and finish onboarding signed out (Codex review).
            if case .signedIn = store.authState {
                coordinator.skipConnectIfAlreadyConnected(true)
            }
            // Only set default focus when showing the connect prompt, not the device-code screen.
            guard case .waitingForUser = store.authState else { primaryFocused = true; return }
        }
        .onChange(of: store.authState) { _, newState in
            guard coordinator.currentStep == .connect else { return }
            if case .signedIn = newState { coordinator.advance() }
        }
        .sheet(isPresented: $showingAdd) { addAccountSheet }
    }

    @ViewBuilder private var content: some View {
        switch store.authState {
        case let .waitingForUser(authorization):
            DeviceCodeScreen(store: store, authorization: authorization)
        case let .error(message):
            connectPrompt(errorMessage: message)
        default:
            connectPrompt(errorMessage: nil)
        }
    }

    private func connectPrompt(errorMessage: String?) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(HubberDesign.accent)
                .padding(.bottom, 16)
            Text("Connect your account")
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(HubberDesign.text)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 8)
            Text("Sign in with GitHub to start seeing the PRs waiting on you. Hubber only requests read-only access.")
                .font(.system(size: 12.5))
                .foregroundStyle(HubberDesign.text2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 264)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(HubberDesign.sloRed.fg)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 264)
                    .padding(.bottom, 12)
            }

            signInButton(errorMessage: errorMessage)

            Button("Add GitHub Enterprise or GitLab…") { showingAdd = true }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(HubberDesign.text2)
                .accessibilityHint("Opens the device-code flow")
                .padding(.top, 12)
        }
    }

    private func signInButton(errorMessage: String?) -> some View {
        VStack(spacing: 0) {
            Button { store.startSignIn() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 17))
                    Text(errorMessage == nil ? "Sign in with GitHub" : "Try again")
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
            }
            .buttonStyle(SignInButtonStyle(colorScheme: colorScheme))
            .frame(maxWidth: 264)
            .focused($primaryFocused)
            .disabled(isRestricted)
            .opacity(isRestricted ? 0.45 : 1)

            if isRestricted {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                    Text("Sign-in is restricted by your organization.")
                        .font(.system(size: 11))
                }
                .foregroundStyle(HubberDesign.text2)
                .padding(.top, 10)
            }
        }
    }

    private var addAccountSheet: some View {
        AddAccountView(
            policy: store.settings.providerAccessPolicy,
            isDuplicate: { [weak store] id in store?.connections.contains { $0.id == id } ?? false },
            addAccount: { [weak store] id, token, user in
                _ = try await store?.addResolvedAccount(id: id, token: token, user: user)
            },
            onActiveChange: { store.setAddingAccount($0) },
            onDone: { showingAdd = false }
        )
    }
}

// MARK: - Notifications (#107)

struct OnboardingNotificationsStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject var store: HubberStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var requesting = false
    @FocusState private var primaryFocused: Bool

    var body: some View {
        OnboardingScaffold(stepIndex: 3, stepCount: OnboardingCoordinator.Step.allCases.count) {
            VStack(spacing: 0) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(HubberDesign.accent)
                    .padding(.bottom, 16)
                Text("Stay in the loop")
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(HubberDesign.text)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 8)
                Text(
                    "Get a heads-up the moment a review is requested from you. "
                        + "You control exactly which events notify you in Settings."
                )
                .font(.system(size: 12.5))
                .foregroundStyle(HubberDesign.text2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 264)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

                if store.notificationsDenied {
                    deniedGuidance
                } else {
                    choiceButtons
                }
            }
        }
        .onAppear { primaryFocused = true }
    }

    private var choiceButtons: some View {
        VStack(spacing: 10) {
            Button {
                requesting = true
                Task {
                    await store.requestNotificationAuthorization()
                    requesting = false
                    coordinator.advance()
                }
            } label: {
                Text(requesting ? "Requesting…" : "Enable notifications")
                    .font(.system(size: 13.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(SignInButtonStyle(colorScheme: colorScheme))
            .frame(maxWidth: 264)
            .focused($primaryFocused)
            .disabled(requesting)

            OnboardingSecondaryButton(title: "Not now") {
                coordinator.advance()
            }
        }
    }

    private var deniedGuidance: some View {
        VStack(spacing: 10) {
            Text(
                "Notifications are turned off for Hubber in macOS. "
                    + "You can enable them in System Settings → Notifications → Hubber."
            )
            .font(.system(size: 11))
            .foregroundStyle(HubberDesign.text2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 264)
            Button { coordinator.advance() } label: {
                Text("Continue")
                    .font(.system(size: 13.5, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(SignInButtonStyle(colorScheme: colorScheme))
            .frame(maxWidth: 264)
            .focused($primaryFocused)
        }
    }
}

// MARK: - Launch at login (#106)

struct OnboardingLaunchAtLoginStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject var store: HubberStore
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var primaryFocused: Bool

    /// When MDM forces launchAtLogin, the user can't change it — show the managed state and
    /// let them continue (reconcileLaunchAtLogin already applied the forced value at launch).
    private var isManaged: Bool {
        store.settings.isLocked(ManagedKey.launchAtLogin)
    }

    var body: some View {
        OnboardingScaffold(stepIndex: 4, stepCount: OnboardingCoordinator.Step.allCases.count) {
            VStack(spacing: 0) {
                Image(systemName: "power")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(HubberDesign.accent)
                    .padding(.bottom, 16)
                Text("Open at login")
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.3)
                    .foregroundStyle(HubberDesign.text)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 8)
                Text(
                    "Hubber works best running quietly in your menu bar. Open it automatically "
                        + "when you log in so you never miss a review."
                )
                .font(.system(size: 12.5))
                .foregroundStyle(HubberDesign.text2)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 264)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

                if isManaged {
                    OnboardingManagedNotice(
                        message: store.settings.launchAtLoginEnabled
                            ? "Opening at login is enabled by your organization."
                            : "Opening at login is set by your organization."
                    ) {
                        coordinator.advance()
                    }
                } else {
                    VStack(spacing: 10) {
                        Button {
                            store.setLaunchAtLogin(true)
                            coordinator.advance()
                        } label: {
                            Text("Open Hubber at login")
                                .font(.system(size: 13.5, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 16)
                        }
                        .buttonStyle(SignInButtonStyle(colorScheme: colorScheme))
                        .frame(maxWidth: 264)
                        .focused($primaryFocused)

                        OnboardingSecondaryButton(title: "Not now") {
                            coordinator.advance()
                        }
                    }
                }
            }
        }
        .onAppear { if !isManaged { primaryFocused = true } }
    }
}
