import Foundation
import XCTest
@testable import Hubber

final class TokenStoreIsolationTests: XCTestCase {
    func testKeychainAccountsAreDerivedFromConnectionSlugs() {
        let personal = ConnectionID.gitHubDotCom(login: "personal")
        let work = ConnectionID.gitHubDotCom(login: "work")

        let personalStore = GitHubKeychainTokenStore(account: personal.slug)
        let workStore = GitHubKeychainTokenStore(account: work.slug)

        XCTAssertEqual(keychainAccount(from: personalStore), personal.slug)
        XCTAssertEqual(keychainAccount(from: workStore), work.slug)
        XCTAssertNotEqual(keychainAccount(from: personalStore), keychainAccount(from: workStore))
    }

    func testFactoryBackedStoresKeepConnectionTokensIsolated() throws {
        let personal = ConnectionID.gitHubDotCom(login: "personal")
        let work = ConnectionID.gitHubDotCom(login: "work")
        let stores = SpyTokenStores()

        let makeStore: (ConnectionID) -> any GitHubTokenStoring = { connectionID in
            stores.store(for: connectionID.slug)
        }

        let personalStore = makeStore(personal)
        let workStore = makeStore(work)
        let personalToken = makeToken(login: "personal", accessToken: "personal-token")
        let workToken = makeToken(login: "work", accessToken: "work-token")

        try personalStore.save(personalToken)
        try workStore.save(workToken)

        XCTAssertEqual(try personalStore.load(), personalToken)
        XCTAssertEqual(try workStore.load(), workToken)
        XCTAssertNotEqual(stores.store(for: personal.slug).identity, stores.store(for: work.slug).identity)
    }

    func testDefaultFactoryBuildsDistinctStoresForDistinctConnectionIDs() {
        let personal = ConnectionID.gitHubDotCom(login: "personal")
        let work = ConnectionID.gitHubDotCom(login: "work")

        let personalStore = GitHubTokenStore.makeStore(for: personal)
        let workStore = GitHubTokenStore.makeStore(for: work)

        #if DEBUG
            let personalFileStore = personalStore as? GitHubDevelopmentFileTokenStore
            let workFileStore = workStore as? GitHubDevelopmentFileTokenStore

            XCTAssertEqual(
                personalFileStore.flatMap(devTokenURL),
                GitHubDevelopmentFileTokenStore.devTokenURL(for: personal)
            )
            XCTAssertEqual(workFileStore.flatMap(devTokenURL), GitHubDevelopmentFileTokenStore.devTokenURL(for: work))
            XCTAssertNotEqual(personalFileStore.flatMap(devTokenURL), workFileStore.flatMap(devTokenURL))
        #else
            let personalKeychainStore = personalStore as? GitHubKeychainTokenStore
            let workKeychainStore = workStore as? GitHubKeychainTokenStore

            XCTAssertEqual(personalKeychainStore.flatMap(keychainAccount), personal.slug)
            XCTAssertEqual(workKeychainStore.flatMap(keychainAccount), work.slug)
            XCTAssertNotEqual(
                personalKeychainStore.flatMap(keychainAccount),
                workKeychainStore.flatMap(keychainAccount)
            )
        #endif
    }

    func testDevelopmentFileTokenURLsAreUniqueAndDoNotUseLegacyPath() {
        let personalURL = GitHubDevelopmentFileTokenStore.devTokenURL(
            for: ConnectionID.gitHubDotCom(login: "personal")
        )
        let workURL = GitHubDevelopmentFileTokenStore.devTokenURL(for: ConnectionID.gitHubDotCom(login: "work"))

        XCTAssertNotEqual(personalURL, workURL)
        XCTAssertNotEqual(personalURL, GitHubDevelopmentFileTokenStore.legacyTokenURL)
        XCTAssertNotEqual(workURL, GitHubDevelopmentFileTokenStore.legacyTokenURL)
        XCTAssertEqual(personalURL.lastPathComponent, "github-auth-dev-github_github.com_personal.json")
    }

    func testDeletingOneConnectionStoreLeavesOtherStoreUntouched() throws {
        let personal = ConnectionID.gitHubDotCom(login: "personal")
        let work = ConnectionID.gitHubDotCom(login: "work")
        let stores = SpyTokenStores()

        try stores.store(for: personal.slug).delete()

        XCTAssertEqual(stores.store(for: personal.slug).deleteCallCount, 1)
        XCTAssertEqual(stores.store(for: work.slug).deleteCallCount, 0)
    }
}

private final class SpyTokenStores: @unchecked Sendable {
    private let lock = NSLock()
    private var stores: [String: IsolationSpyTokenStore] = [:]

    var allStores: [IsolationSpyTokenStore] {
        lock.withLock { Array(stores.values) }
    }

    func store(for identity: String) -> IsolationSpyTokenStore {
        lock.withLock {
            if let store = stores[identity] {
                return store
            }

            let store = IsolationSpyTokenStore(identity: identity, token: nil)
            stores[identity] = store
            return store
        }
    }
}

private final class IsolationSpyTokenStore: GitHubTokenStoring, @unchecked Sendable {
    let identity: String

    private let lock = NSLock()
    private var storedToken: GitHubStoredToken?
    private var _deleteCallCount = 0
    private var _loadCallCount = 0
    private var _saveCallCount = 0
    private var _savedTokens: [GitHubStoredToken] = []

    var deleteCallCount: Int {
        lock.withLock { _deleteCallCount }
    }

    var loadCallCount: Int {
        lock.withLock { _loadCallCount }
    }

    var saveCallCount: Int {
        lock.withLock { _saveCallCount }
    }

    var savedTokens: [GitHubStoredToken] {
        lock.withLock { _savedTokens }
    }

    init(identity: String, token: GitHubStoredToken?) {
        self.identity = identity
        storedToken = token
    }

    func load() throws -> GitHubStoredToken? {
        lock.withLock {
            _loadCallCount += 1
            return storedToken
        }
    }

    func save(_ token: GitHubStoredToken) throws {
        lock.withLock {
            _saveCallCount += 1
            _savedTokens.append(token)
            storedToken = token
        }
    }

    func delete() throws {
        lock.withLock {
            _deleteCallCount += 1
            storedToken = nil
        }
    }
}

private func makeToken(login: String?, accessToken: String = "access-token") -> GitHubStoredToken {
    GitHubStoredToken(
        accessToken: accessToken,
        accessTokenExpiresAt: nil,
        refreshToken: nil,
        refreshTokenExpiresAt: nil,
        tokenType: "bearer",
        login: login
    )
}

private func keychainAccount(from store: GitHubKeychainTokenStore) -> String? {
    Mirror(reflecting: store).descendant("account") as? String
}

private func devTokenURL(from store: GitHubDevelopmentFileTokenStore) -> URL? {
    Mirror(reflecting: store).descendant("tokenURL") as? URL
}
