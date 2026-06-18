import Foundation

/// Resolves the concrete API/login endpoints for a GitHub host from its *web* base URL.
///
/// github.com and GitHub Enterprise Server (GHES) lay out their endpoints differently:
/// github.com splits its API onto the `api.github.com` subdomain, while GHES keeps GraphQL,
/// REST (`/api/v3`), and OAuth/device (`/login`) under the single appliance host. This is the
/// only place that knows that distinction — both `GitHubProvider` and `GitHubAuthService` route
/// through it.
///
/// `webBaseURL` is the host root the user signs in against (e.g. `https://github.com` or
/// `https://github.enterprise.acme.com`) — NOT the API subdomain.
struct GitHubEndpoints: Equatable {
    let webBaseURL: URL

    /// The default github.com web host root. Reused as the default `baseURL` for the provider
    /// and auth service so existing call sites preserve today's behavior.
    static let dotComWebBaseURL = URL(string: "https://github.com")!

    init(webBaseURL: URL = GitHubEndpoints.dotComWebBaseURL) {
        self.webBaseURL = webBaseURL
    }

    /// True when this resolver targets public github.com (which splits its API onto `api.github.com`).
    var isDotCom: Bool {
        webBaseURL.host == "github.com"
    }

    /// GraphQL endpoint. github.com → `https://api.github.com/graphql`; GHES → `https://<host>/api/graphql`.
    var graphQL: URL {
        if isDotCom {
            return URL(string: "https://api.github.com/graphql")!
        }
        return webBaseURL.appendingPathComponent("api/graphql")
    }

    /// REST API base. github.com → `https://api.github.com`; GHES → `https://<host>/api/v3`.
    var restBase: URL {
        if isDotCom {
            return URL(string: "https://api.github.com")!
        }
        return webBaseURL.appendingPathComponent("api/v3")
    }

    /// Authenticated-user REST endpoint (`<restBase>/user`).
    var authenticatedUser: URL {
        restBase.appendingPathComponent("user")
    }

    /// OAuth device-code request endpoint (`<webBaseURL>/login/device/code`).
    var deviceCode: URL {
        webBaseURL.appendingPathComponent("login/device/code")
    }

    /// OAuth access-token endpoint (`<webBaseURL>/login/oauth/access_token`).
    var accessToken: URL {
        webBaseURL.appendingPathComponent("login/oauth/access_token")
    }
}
