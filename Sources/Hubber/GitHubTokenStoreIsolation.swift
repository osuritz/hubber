import Foundation

extension GitHubTokenStore {
    static func makeStore(for connectionID: ConnectionID) -> any GitHubTokenStoring {
        #if DEBUG
            return GitHubDevelopmentFileTokenStore(connectionID: connectionID)
        #else
            return GitHubKeychainTokenStore(account: connectionID.slug)
        #endif
    }
}

extension GitHubDevelopmentFileTokenStore {
    convenience init(connectionID: ConnectionID) {
        self.init(tokenURL: GitHubDevelopmentFileTokenStore.devTokenURL(for: connectionID))
    }

    static var defaultTokenURL: URL {
        legacyTokenURL
    }

    static var legacyTokenURL: URL {
        tokenDirectoryURL.appendingPathComponent("github-auth-dev.json")
    }

    static func devTokenURL(for connectionID: ConnectionID) -> URL {
        tokenDirectoryURL.appendingPathComponent("github-auth-dev-\(connectionID.slug).json")
    }

    private static var tokenDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let baseURL = appSupport
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return baseURL.appendingPathComponent("Hubber", isDirectory: true)
    }
}
