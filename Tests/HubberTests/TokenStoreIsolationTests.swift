import Foundation
import XCTest
@testable import Hubber

final class TokenStoreIsolationTests: XCTestCase {
    func testKeychainAccountsAreDerivedFromConnectionSlugs() {
        let personal = ConnectionID.gitHubDotCom(login: "personal")
        let work = ConnectionID.gitHubDotCom(login: "work")

        let personalStore = KeychainTokenStore(account: personal.slug)
        let workStore = KeychainTokenStore(account: work.slug)

        XCTAssertEqual(keychainAccount(from: personalStore), personal.slug)
        XCTAssertEqual(keychainAccount(from: workStore), work.slug)
        XCTAssertNotEqual(keychainAccount(from: personalStore), keychainAccount(from: workStore))
    }

    func testFactoryBackedStoresKeepConnectionTokensIsolated() throws {
        let personal = ConnectionID.gitHubDotCom(login: "personal")
        let work = ConnectionID.gitHubDotCom(login: "work")
        let stores = SpyTokenStores()

        let makeStore: (ConnectionID) -> any TokenStoring = { connectionID in
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

        let personalStore = TokenStore.makeStore(for: personal)
        let workStore = TokenStore.makeStore(for: work)

        #if DEBUG
            let personalFileStore = personalStore as? DevelopmentFileTokenStore
            let workFileStore = workStore as? DevelopmentFileTokenStore

            XCTAssertEqual(
                personalFileStore.flatMap(devTokenURL),
                DevelopmentFileTokenStore.devTokenURL(for: personal)
            )
            XCTAssertEqual(workFileStore.flatMap(devTokenURL), DevelopmentFileTokenStore.devTokenURL(for: work))
            XCTAssertNotEqual(personalFileStore.flatMap(devTokenURL), workFileStore.flatMap(devTokenURL))
        #else
            let personalKeychainStore = personalStore as? KeychainTokenStore
            let workKeychainStore = workStore as? KeychainTokenStore

            XCTAssertEqual(personalKeychainStore.flatMap(keychainAccount), personal.slug)
            XCTAssertEqual(workKeychainStore.flatMap(keychainAccount), work.slug)
            XCTAssertNotEqual(
                personalKeychainStore.flatMap(keychainAccount),
                workKeychainStore.flatMap(keychainAccount)
            )
        #endif
    }

    func testDevelopmentFileTokenURLsAreUniqueAndDoNotUseLegacyPath() {
        let personalURL = DevelopmentFileTokenStore.devTokenURL(
            for: ConnectionID.gitHubDotCom(login: "personal")
        )
        let workURL = DevelopmentFileTokenStore.devTokenURL(for: ConnectionID.gitHubDotCom(login: "work"))

        XCTAssertNotEqual(personalURL, workURL)
        XCTAssertNotEqual(personalURL, DevelopmentFileTokenStore.legacyTokenURL)
        XCTAssertNotEqual(workURL, DevelopmentFileTokenStore.legacyTokenURL)
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

private final class IsolationSpyTokenStore: TokenStoring, @unchecked Sendable {
    let identity: String

    private let lock = NSLock()
    private var storedToken: StoredToken?
    private var _deleteCallCount = 0
    private var _loadCallCount = 0
    private var _saveCallCount = 0
    private var _savedTokens: [StoredToken] = []

    var deleteCallCount: Int {
        lock.withLock { _deleteCallCount }
    }

    var loadCallCount: Int {
        lock.withLock { _loadCallCount }
    }

    var saveCallCount: Int {
        lock.withLock { _saveCallCount }
    }

    var savedTokens: [StoredToken] {
        lock.withLock { _savedTokens }
    }

    init(identity: String, token: StoredToken?) {
        self.identity = identity
        storedToken = token
    }

    func load() throws -> StoredToken? {
        lock.withLock {
            _loadCallCount += 1
            return storedToken
        }
    }

    func save(_ token: StoredToken) throws {
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

private func makeToken(login: String?, accessToken: String = "access-token") -> StoredToken {
    StoredToken(
        accessToken: accessToken,
        accessTokenExpiresAt: nil,
        refreshToken: nil,
        refreshTokenExpiresAt: nil,
        tokenType: "bearer",
        login: login
    )
}

private func keychainAccount(from store: KeychainTokenStore) -> String? {
    Mirror(reflecting: store).descendant("account") as? String
}

private func devTokenURL(from store: DevelopmentFileTokenStore) -> URL? {
    Mirror(reflecting: store).descendant("tokenURL") as? URL
}
