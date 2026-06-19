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
        .accessibilityLabel("Step \(stepIndex + 1) of \(stepCount)")
    }
}

// MARK: - Welcome (#101)

struct OnboardingWelcomeStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        OnboardingScaffold(stepIndex: 0, stepCount: OnboardingCoordinator.Step.allCases.count) {
            VStack(spacing: 0) {
                appIconTile
                Text("Welcome to Hubber")
                    .font(.system(size: 19, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(HubberDesign.text)
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
            }
        }
    }

    private var appIconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(light: "#1f2328", dark: "#0d1117"))
                .frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.30), radius: 11, y: 8)
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.bottom, 20)
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

// MARK: - Analytics consent (#102)

struct OnboardingConsentStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject var store: HubberStore
    @Environment(\.colorScheme) private var colorScheme

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
                    .padding(.bottom, 8)

                Text(
                    "Share anonymous usage data — counts and timings only. "
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
                    managedNotice
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

            OnboardingSecondaryButton(title: "Not now") {
                store.settings.analyticsEnabled = false
                coordinator.advance()
            }
        }
    }

    private var managedNotice: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                Text(store.settings.analyticsEnabled
                    ? "Analytics is enabled by your organization."
                    : "Analytics is disabled by your organization.")
                    .font(.system(size: 11))
            }
            .foregroundStyle(HubberDesign.text2)

            Button { coordinator.advance() } label: {
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

// MARK: - Step stubs (replaced by later tasks)

/// Minimal placeholder used until the real step lands. Title + Continue (advances the flow).
struct OnboardingStepStub: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let stepIndex: Int
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        OnboardingScaffold(stepIndex: stepIndex, stepCount: OnboardingCoordinator.Step.allCases.count) {
            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(HubberDesign.text)
                Button { coordinator.advance() } label: {
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
}
