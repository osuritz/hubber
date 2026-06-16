import Foundation

// MARK: - Per-tab independent refresh helpers

@MainActor
extension HubberStore {
    /// Fans out three concurrent tab fetches; commits successful data before any global error handling.
    /// Returns `(didStop, tabSuccesses)` where `tabSuccesses` indicates which tabs fetched successfully
    /// (used by the notification pipeline to avoid false "merged" events on partial failures).
    func fetchAllTabsIndependently(
        token: GitHubStoredToken,
        login: String
    ) async -> (didStop: Bool, tabSuccesses: TabSuccesses) {
        let incomingResult = await fetchIncoming(token: token, login: login)
        let outgoingResult = await fetchOutgoing(token: token, login: login)
        let draftsResult = await fetchDrafts(token: token)
        let errs = [incomingResult.failureError, outgoingResult.failureError, draftsResult.failureError]
        if errs.compactMap(\.self).contains(where: { $0 is CancellationError }) {
            appendDeveloperLog("Pull request refresh cancelled")
            return (true, TabSuccesses(incoming: false, outgoing: false))
        }
        let (newIncoming, incomingGlobal) = resolveTab(
            incomingResult, existing: data.incoming, tab: .incoming, label: "Incoming"
        )
        let (newOutgoing, outgoingGlobal) = resolveTab(
            outgoingResult, existing: data.outgoing, tab: .outgoing, label: "Outgoing"
        )
        let (newDrafts, draftsGlobal) = resolveTab(
            draftsResult, existing: data.drafts, tab: .drafts, label: "Drafts"
        )
        let tabSuccesses = TabSuccesses(
            incoming: incomingResult.failureError == nil,
            outgoing: outgoingResult.failureError == nil
        )
        data = HubberData(incoming: newIncoming, outgoing: newOutgoing, drafts: newDrafts)
        if let globalError = incomingGlobal ?? outgoingGlobal ?? draftsGlobal {
            await handleRefreshError(globalError, settingGlobalError: false)
            return (true, tabSuccesses)
        }
        return (false, tabSuccesses)
    }

    private func fetchIncoming(
        token: GitHubStoredToken,
        login: String
    ) async -> Result<[IncomingReview], Error> {
        await catchingResult {
            try await self.provider.fetchIncomingReviews(
                accessToken: token.accessToken,
                viewerLogin: login,
                mode: self.settings.incomingMode
            )
        }
    }

    private func fetchOutgoing(
        token: GitHubStoredToken,
        login: String
    ) async -> Result<[OutgoingReview], Error> {
        await catchingResult {
            try await self.provider.fetchOutgoingPullRequests(
                accessToken: token.accessToken,
                viewerLogin: login,
                unresolvedMode: self.settings.unresolvedMode
            )
        }
    }

    private func fetchDrafts(token: GitHubStoredToken) async -> Result<[DraftReview], Error> {
        await catchingResult {
            try await self.provider.fetchDraftPullRequests(accessToken: token.accessToken, limit: 100)
        }
    }

    private func resolveTab<T>(
        _ result: Result<T, Error>,
        existing: T,
        tab: WorkTab,
        label: String
    ) -> (T, Error?) {
        switch result {
        case let .success(value):
            setTabError(nil, for: tab)
            return (value, nil)
        case let .failure(error):
            if isGlobalError(error) { return (existing, error) }
            setTabError(error.localizedDescription, for: tab)
            appendDeveloperLog("\(label) tab refresh failed: \(error.localizedDescription)")
            return (existing, nil)
        }
    }

    private func isGlobalError(_ error: Error) -> Bool {
        if case GitHubAuthError.rateLimited = error { return true }
        return Self.authState(afterRefreshError: error, signedInLogin: signedInLogin) != nil
    }

    func setTabError(_ message: String?, for tab: WorkTab) {
        switch tab {
        case .incoming: incomingError = message
        case .outgoing: outgoingError = message
        case .drafts: draftsError = message
        }
    }

    /// Handles rate-limit and credential errors; returns `true` for global errors.
    @discardableResult
    func handleRefreshError(_ error: Error, settingGlobalError: Bool = true) async -> Bool {
        if case let GitHubAuthError.rateLimited(retryAfter) = error {
            let delay = retryAfter ?? (15 * 60)
            rateLimitedUntil = Date().addingTimeInterval(delay)
            let minutes = Int((delay / 60).rounded(.up))
            appendDeveloperLog("GitHub rate limited, backing off for \(minutes)m")
            return true
        }
        guard let newState = Self.authState(afterRefreshError: error, signedInLogin: signedInLogin) else {
            if settingGlobalError {
                pullRequestRefreshError = error.localizedDescription
                appendDeveloperLog("Refresh failed: \(error.localizedDescription)")
            }
            return false
        }
        authState = newState
        if case .sessionExpired = newState {
            appendDeveloperLog("Refresh failed: session expired, showing re-auth prompt")
            stopPullRequestRefreshLoop()
        } else if case .signedOut = newState {
            try? await deleteStoredToken()
            appendDeveloperLog("Refresh failed: invalid credentials")
            stopPullRequestRefreshLoop()
        }
        return true
    }
}
