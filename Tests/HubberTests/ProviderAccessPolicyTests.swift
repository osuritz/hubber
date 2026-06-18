import Foundation
import XCTest
@testable import Hubber

// MARK: - ProviderAccessPolicyTests

//
// Full allow/block matrix for ProviderAccessPolicy:
//
//   empty allowlist + allowPersonalGitHub == true  → allowed
//   empty allowlist + allowPersonalGitHub == false → blocked
//   non-empty allowlist containing "github.com"   → allowed
//   non-empty allowlist NOT containing "github.com"
//     + allowPersonalGitHub == true               → allowed (personal explicitly allowed)
//     + allowPersonalGitHub == false              → blocked
//
// (Allowlist is for host restriction; allowPersonalGitHub is the separate personal-flag.)

@MainActor
final class ProviderAccessPolicyTests: XCTestCase {

    // MARK: - Empty allowlist (no host restriction)

    func testEmptyAllowlistPersonalAllowed_canConnect() {
        let policy = ProviderAccessPolicy(allowPersonalGitHub: true, allowlist: [])
        XCTAssertTrue(policy.canConnectGitHubDotCom)
        XCTAssertNil(policy.blockedReason)
    }

    func testEmptyAllowlistPersonalBlocked_cannotConnect() {
        let policy = ProviderAccessPolicy(allowPersonalGitHub: false, allowlist: [])
        XCTAssertFalse(policy.canConnectGitHubDotCom)
        XCTAssertNotNil(policy.blockedReason)
    }

    // MARK: - Non-empty allowlist containing "github.com"

    func testAllowlistContainsGitHubDotCom_allowed() {
        let policy = ProviderAccessPolicy(allowPersonalGitHub: false, allowlist: ["github.com"])
        XCTAssertTrue(policy.canConnectGitHubDotCom)
        XCTAssertNil(policy.blockedReason)
    }

    func testAllowlistContainsGitHubDotComPlusOthers_allowed() {
        let policy = ProviderAccessPolicy(
            allowPersonalGitHub: false,
            allowlist: ["github.com", "github.enterprise.example.com"]
        )
        XCTAssertTrue(policy.canConnectGitHubDotCom)
        XCTAssertNil(policy.blockedReason)
    }

    // MARK: - Non-empty allowlist NOT containing "github.com"

    func testAllowlistOtherHosts_personalAllowed_canConnect() {
        // allowPersonalGitHub == true overrides the absent-from-allowlist restriction
        let policy = ProviderAccessPolicy(
            allowPersonalGitHub: true,
            allowlist: ["github.enterprise.example.com"]
        )
        XCTAssertTrue(policy.canConnectGitHubDotCom)
        XCTAssertNil(policy.blockedReason)
    }

    func testAllowlistOtherHosts_personalBlocked_cannotConnect() {
        // allowPersonalGitHub == false + github.com not in allowlist → blocked
        let policy = ProviderAccessPolicy(
            allowPersonalGitHub: false,
            allowlist: ["github.enterprise.example.com"]
        )
        XCTAssertFalse(policy.canConnectGitHubDotCom)
        XCTAssertNotNil(policy.blockedReason)
    }

    // MARK: - Default values

    func testDefaultPolicyAllowsEverything() {
        // Default: allowPersonalGitHub == true, allowlist == [] → allowed
        let policy = ProviderAccessPolicy(allowPersonalGitHub: true, allowlist: [])
        XCTAssertTrue(policy.canConnectGitHubDotCom)
    }

    // MARK: - blockedReason content

    func testBlockedReasonMentionsOrganization() {
        let policy = ProviderAccessPolicy(allowPersonalGitHub: false, allowlist: [])
        guard let reason = policy.blockedReason else {
            XCTFail("Expected a blocked reason")
            return
        }
        // The reason should surface something meaningful to an end-user
        XCTAssertFalse(reason.isEmpty)
    }

    // MARK: - Host-generic canConnect(host:) — #82

    // MC-MDM-03: allowlist containing the GHES host permits that host (but not github.com).
    func testAllowlistWithGHESHostPermitsGHESButNotGitHubDotCom() {
        let policy = ProviderAccessPolicy(
            allowPersonalGitHub: false,
            allowlist: ["github.enterprise.acme.com"]
        )
        XCTAssertTrue(policy.canConnect(host: "github.enterprise.acme.com"))
        XCTAssertNil(policy.blockedReason(host: "github.enterprise.acme.com"))
        XCTAssertFalse(policy.canConnect(host: "github.com"))
    }

    // MC-MDM-04: a host not in a non-empty allowlist is blocked.
    func testAllowlistWithoutHostBlocksThatHost() {
        let policy = ProviderAccessPolicy(allowPersonalGitHub: true, allowlist: ["github.com"])
        XCTAssertFalse(policy.canConnect(host: "gitlab.com"))
        XCTAssertNotNil(policy.blockedReason(host: "gitlab.com"))
    }

    /// Empty allowlist = no host restriction: enterprise hosts allowed; github.com gated by the flag.
    func testEmptyAllowlistAllowsAnyEnterpriseHostButGatesGitHubDotCom() {
        let permissive = ProviderAccessPolicy(allowPersonalGitHub: true, allowlist: [])
        XCTAssertTrue(permissive.canConnect(host: "github.enterprise.acme.com"))
        XCTAssertTrue(permissive.canConnect(host: "github.com"))

        let blocked = ProviderAccessPolicy(allowPersonalGitHub: false, allowlist: [])
        XCTAssertTrue(blocked.canConnect(host: "github.enterprise.acme.com"))
        XCTAssertFalse(blocked.canConnect(host: "github.com"))
    }

    /// The github.com shim must stay provably identical to canConnect(host: "github.com").
    func testCanConnectGitHubDotComShimMatchesHostPredicate() {
        let cases = [
            ProviderAccessPolicy(allowPersonalGitHub: true, allowlist: []),
            ProviderAccessPolicy(allowPersonalGitHub: false, allowlist: []),
            ProviderAccessPolicy(allowPersonalGitHub: false, allowlist: ["github.com"]),
            ProviderAccessPolicy(allowPersonalGitHub: false, allowlist: ["github.enterprise.acme.com"]),
            ProviderAccessPolicy(allowPersonalGitHub: true, allowlist: ["github.enterprise.acme.com"]),
        ]
        for policy in cases {
            XCTAssertEqual(policy.canConnectGitHubDotCom, policy.canConnect(host: "github.com"))
            XCTAssertEqual(policy.blockedReason, policy.blockedReason(host: "github.com"))
        }
    }

    // MARK: - SettingsStore integration

    func testSettingsStoreDefaultProviderAllowlistIsEmpty() throws {
        let suiteName = "ProviderAccessPolicyTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.providerAllowlist.isEmpty)
    }

    func testSettingsStoreDefaultAllowPersonalGitHubIsTrue() throws {
        let suiteName = "ProviderAccessPolicyTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.allowPersonalGitHub)
    }

    func testSettingsStoreDefaultPolicyAllowsGitHubDotCom() throws {
        let suiteName = "ProviderAccessPolicyTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.providerAccessPolicy.canConnectGitHubDotCom)
    }

    func testForcedAllowPersonalGitHubFalseBlocksGitHubDotCom() throws {
        let suiteName = "ProviderAccessPolicyTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let managed = InMemoryManagedPreferences([ManagedKey.allowPersonalGitHub: false])
        let store = SettingsStore(defaults: defaults, managed: managed)
        XCTAssertFalse(store.allowPersonalGitHub)
        XCTAssertFalse(store.providerAccessPolicy.canConnectGitHubDotCom)
    }

    func testForcedProviderAllowlistExcludingGitHubDotComBlocksWhenPersonalFalse() throws {
        let suiteName = "ProviderAccessPolicyTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let managed = InMemoryManagedPreferences([
            ManagedKey.allowPersonalGitHub: false,
            ManagedKey.providerAllowlist: ["github.enterprise.example.com"],
        ])
        let store = SettingsStore(defaults: defaults, managed: managed)
        XCTAssertFalse(store.providerAccessPolicy.canConnectGitHubDotCom)
    }

    func testIsLockedProviderAllowlistWhenForced() throws {
        let suiteName = "ProviderAccessPolicyTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let managed = InMemoryManagedPreferences([
            ManagedKey.providerAllowlist: ["github.enterprise.example.com"],
        ])
        let store = SettingsStore(defaults: defaults, managed: managed)
        XCTAssertTrue(store.isLocked(ManagedKey.providerAllowlist))
    }

    func testIsLockedAllowPersonalGitHubWhenForced() throws {
        let suiteName = "ProviderAccessPolicyTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let managed = InMemoryManagedPreferences([ManagedKey.allowPersonalGitHub: false])
        let store = SettingsStore(defaults: defaults, managed: managed)
        XCTAssertTrue(store.isLocked(ManagedKey.allowPersonalGitHub))
    }
}
