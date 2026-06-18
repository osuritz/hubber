import Foundation

/// Add-account store surface: materialize an externally-resolved account, and the popover-pinning
/// signal the add-account sheet drives. Extracted from `GitHubAuth.swift` to keep that file under
/// the file-length limit. (`isAddingAccount` is a stored `@Published` property, so it must remain
/// in the main `HubberStore` body — only the methods and computed predicate live here.)
extension HubberStore {
    enum AddAccountError: Error { case alreadyAdded }

    /// Materializes an account whose identity was already resolved by an external auth flow
    /// (`AddAccountController`): builds the factory-routed connection, adopts the validated token,
    /// and registers it. Rejects a duplicate `ConnectionID`.
    @discardableResult
    func addResolvedAccount(
        id: ConnectionID,
        token: GitHubStoredToken,
        user: GitHubAuthenticatedUser
    ) async throws -> Connection {
        guard !connections.contains(where: { $0.id == id }) else {
            throw AddAccountError.alreadyAdded
        }
        let conn = try addConnection(id: id)
        await conn.adopt(token: token, user: user)
        return conn
    }

    /// The popover stays pinned (doesn't close when another app activates) while the user is
    /// mid-auth — device-flow sign-in OR an open add-account sheet. (`setAddingAccount(_:)` lives
    /// in the class body because `isAddingAccount` has a `private(set)` setter.)
    var shouldPinPanel: Bool {
        isAuthenticating || isAddingAccount
    }
}
