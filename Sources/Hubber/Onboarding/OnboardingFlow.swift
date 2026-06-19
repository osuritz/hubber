import SwiftUI

/// Renders the current onboarding step. Shown by HubberPopoverView ahead of the normal
/// auth-branched body while onboarding is incomplete. See #101.
struct OnboardingFlow: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject var store: HubberStore

    var body: some View {
        Group {
            switch coordinator.currentStep {
            case .welcome:
                OnboardingWelcomeStep(coordinator: coordinator)
            case .consent:
                OnboardingConsentStep(coordinator: coordinator, store: store)
            case .connect:
                OnboardingConnectStep(coordinator: coordinator, store: store)
            case .notifications:
                OnboardingNotificationsStep(coordinator: coordinator, store: store)
            case .launchAtLogin:
                OnboardingStepStub(coordinator: coordinator, stepIndex: 4, title: "Launch at login")
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: coordinator.currentStep)
    }
}
