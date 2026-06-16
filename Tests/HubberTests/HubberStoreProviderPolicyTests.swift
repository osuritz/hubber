import Foundation
import XCTest
@testable import Hubber

// MARK: - Spy auth service
//
// Captures whether `startDeviceFlow()` was called, for use in policy-enforcement tests.
// Throws `GitHubAuthError.deviceFlowDisabled` if actually called (so the Task in
// startSignIn completes quickly rather than hanging). Thread-safe via NSLock.

final class SpyGitHubAuthService: GitHubAuthServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var _startDeviceFlowCallCount = 0

    var startDeviceFlowCallCount: Int {
        lock.withLock { _startDeviceFlowCallCount }
    }

    func startDeviceFlow() async throws -> GitHubDeviceAuthorization {
        lock.withLock { _startDeviceFlowCallCount += 1 }
        // Simulate an immediate failure so the Task inside startSignIn terminates
        // without blocking the test; the call-count check is what matters.
        throw GitHubAuthError.deviceFlowDisabled
    }

    func pollForToken(deviceAuthorization: GitHubDeviceAuthorization) async throws -> GitHubStoredToken {
        throw GitHubAuthError.authorizationExpired
    }

    func refresh(_ token: GitHubStoredToken) async throws -> GitHubStoredToken {
        throw GitHubAuthError.missingRefreshToken
    }

    func fetchAuthenticatedUser(accessToken: String) async throws -> GitHubAuthenticatedUser {
        throw GitHubAuthError.badCredentials
    }
}

// MARK: - Tests

@MainActor
final class HubberStoreProviderPolicyTests: XCTestCase {

    // MARK: - Blocking policy: startSignIn() must NOT call startDeviceFlow()

    func testStartSignIn_blockedPolicy_doesNotStartDeviceFlow() async throws {
        let spy = SpyGitHubAuthService()
        let suiteName = "HubberStoreProviderPolicyTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Force allowPersonalGitHub = false → policy blocks github.com
        let managed = InMemoryManagedPreferences([ManagedKey.allowPersonalGitHub: false])
        let settings = SettingsStore(defaults: defaults, managed: managed)
        let store = HubberStore(
            authService: spy,
            tokenStore: SpyTokenStore(token: nil),
            settings: settings
        )

        // Manually set to signedOut so startSignIn is eligible
        store.authState = .signedOut

        store.startSignIn()

        // Wait briefly; the policy check is synchronous so the state change is immediate
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(
            spy.startDeviceFlowCallCount,
            0,
            "startDeviceFlow() must NOT be called when policy blocks the provider"
        )
    }

    // MARK: - Blocking policy: startSignIn() must set an error / blocked auth state

    func testStartSignIn_blockedPolicy_setsErrorAuthState() async throws {
        let spy = SpyGitHubAuthService()
        let suiteName = "HubberStoreProviderPolicyTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let managed = InMemoryManagedPreferences([ManagedKey.allowPersonalGitHub: false])
        let settings = SettingsStore(defaults: defaults, managed: managed)
        let store = HubberStore(
            authService: spy,
            tokenStore: SpyTokenStore(token: nil),
            settings: settings
        )

        // Wait for restoreSession() (launched from init) to reach .signedOut before calling
        // startSignIn(), so that restoreSession's async Task doesn't race with our check.
        let setupDeadline = Date().addingTimeInterval(1)
        while Date() < setupDeadline {
            if case .restoring = store.authState {
                try await Task.sleep(for: .milliseconds(20))
            } else {
                break
            }
        }

        store.startSignIn()
        // Policy check is synchronous in startSignIn() (before any Task), so authState
        // is set immediately — a short yield suffices.
        try await Task.sleep(for: .milliseconds(10))

        // authState should be .error(...) with a blocked reason
        if case .error = store.authState {
            // Correct — policy blocked and set error state
        } else {
            XCTFail("Expected .error authState when policy blocks sign-in, got \(store.authState)")
        }
    }

    // MARK: - Allowing policy: startSignIn() proceeds and calls startDeviceFlow()

    func testStartSignIn_allowingPolicy_callsStartDeviceFlow() async throws {
        let spy = SpyGitHubAuthService()
        let suiteName = "HubberStoreProviderPolicyTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Default policy: allowPersonalGitHub = true (no MDM restriction)
        let store = HubberStore(
            authService: spy,
            tokenStore: SpyTokenStore(token: nil),
            settings: SettingsStore(defaults: defaults)
        )
        store.authState = .signedOut

        store.startSignIn()

        // Wait for the spy to be called (it throws immediately so it's fast)
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline, spy.startDeviceFlowCallCount == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(
            spy.startDeviceFlowCallCount,
            1,
            "startDeviceFlow() must be called when policy allows the provider"
        )
    }
}
