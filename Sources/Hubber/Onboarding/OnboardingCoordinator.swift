import Foundation

/// Drives the first-run onboarding flow: tracks the current step, persists progress so a
/// dismissed-then-reopened panel resumes where it left off, and records completion so the
/// flow never re-shows. UserDefaults is injectable for testing. See #101.
@MainActor
final class OnboardingCoordinator: ObservableObject {
    enum Step: String, CaseIterable {
        case welcome, consent, connect, notifications, launchAtLogin
    }

    private let defaults: UserDefaults
    private static let completedKey = "onboardingCompleted"
    private static let stepKey = "onboardingStep"

    @Published private(set) var currentStep: Step
    @Published private(set) var isCompleted: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isCompleted = defaults.bool(forKey: Self.completedKey)
        let saved = defaults.string(forKey: Self.stepKey).flatMap(Step.init(rawValue:))
        currentStep = saved ?? .welcome
    }

    /// Advances to the next step, or completes the flow if already on the last step.
    func advance() {
        guard let idx = Step.allCases.firstIndex(of: currentStep) else { return }
        let next = idx + 1
        if next < Step.allCases.count {
            currentStep = Step.allCases[next]
            defaults.set(currentStep.rawValue, forKey: Self.stepKey)
        } else {
            complete()
        }
    }

    /// When resuming onto the connect step but an account is already connected
    /// (dev build / prior session), skip straight past it.
    func skipConnectIfAlreadyConnected(_ isConnected: Bool) {
        guard currentStep == .connect, isConnected else { return }
        advance()
    }

    /// Marks onboarding finished — the flow never shows again.
    func complete() {
        isCompleted = true
        defaults.set(true, forKey: Self.completedKey)
    }

    /// Clears persisted onboarding state so the full flow runs again on the next launch.
    /// Used by the Developer panel to re-trigger onboarding for testing; takes effect on
    /// the next start (a live coordinator instance keeps its current state until then).
    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: completedKey)
        defaults.removeObject(forKey: stepKey)
    }
}
