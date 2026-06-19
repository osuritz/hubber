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
                OnboardingStepStub(coordinator: coordinator, stepIndex: 1, title: "Analytics consent")
            case .connect:
                OnboardingStepStub(coordinator: coordinator, stepIndex: 2, title: "Connect account")
            case .notifications:
                OnboardingStepStub(coordinator: coordinator, stepIndex: 3, title: "Notifications")
            case .launchAtLogin:
                OnboardingStepStub(coordinator: coordinator, stepIndex: 4, title: "Launch at login")
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: coordinator.currentStep)
    }
}
