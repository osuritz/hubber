import Foundation

// MARK: - ProviderAccessPolicy

//
// Pure, Sendable value type. Encapsulates the IT/MDM-controlled rules that determine
// whether a GitHub.com (personal) sign-in is permitted on this device.
//
// Rules (evaluated in order):
//   1. If `allowlist` is non-empty and does NOT contain "github.com"
//      AND `allowPersonalGitHub` is false → blocked.
//   2. If `allowlist` is non-empty and CONTAINS "github.com" → allowed.
//   3. If `allowlist` is empty and `allowPersonalGitHub` is false → blocked.
//   4. Otherwise (allowPersonalGitHub == true, or allowlist contains github.com) → allowed.
//
// Today only github.com (personal) exists as a provider. Enterprise GitHub hosts are not
// yet supported; the `allowlist` and `allowPersonalGitHub` flags anticipate multi-host
// support (M6/backlog) and are already lockable via MDM so IT can prepare profiles now.
//
// The policy is read-only and evaluated synchronously. It contains no async operations
// and no mutable state — safe to use from any context.

struct ProviderAccessPolicy {
    /// When true, github.com personal accounts are permitted (unless the allowlist is active
    /// and explicitly excludes github.com). Defaults to `true`.
    let allowPersonalGitHub: Bool

    /// An explicit list of allowed provider hosts. When empty, no host restriction is applied
    /// and only `allowPersonalGitHub` determines whether github.com is accessible.
    /// When non-empty, a host must appear in this list (or be individually permitted via
    /// `allowPersonalGitHub`) to be accessible.
    let allowlist: [String]

    // MARK: - Host-generic policy

    /// True when the current policy permits connecting to `host`.
    ///
    /// - Non-empty allowlist: `host` must appear in the allowlist, OR be github.com with
    ///   `allowPersonalGitHub == true` (the personal-github override never grants an enterprise host).
    /// - Empty allowlist (no restriction configured): github.com is gated by `allowPersonalGitHub`;
    ///   every other host is permitted.
    func canConnect(host: String) -> Bool {
        if !allowlist.isEmpty {
            if allowlist.contains(host) {
                return true
            }
            return host == "github.com" && allowPersonalGitHub
        }
        if host == "github.com" {
            return allowPersonalGitHub
        }
        return true
    }

    /// A user-facing explanation of why connecting to `host` is blocked, or `nil` when not blocked.
    func blockedReason(host: String) -> String? {
        guard !canConnect(host: host) else { return nil }
        return "Sign-in to \(host) is restricted by your organization."
    }

    // MARK: - github.com (personal) shims — preserved for existing call sites

    /// True when the current policy permits signing in to github.com with a personal account.
    var canConnectGitHubDotCom: Bool {
        canConnect(host: "github.com")
    }

    /// A user-facing explanation of why github.com sign-in is blocked, or `nil` when not blocked.
    var blockedReason: String? {
        blockedReason(host: "github.com")
    }
}
