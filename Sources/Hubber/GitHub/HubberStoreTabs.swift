import Foundation

// MARK: - Per-tab independent refresh helpers

@MainActor
extension Connection {
    /// Fans out three concurrent tab fetches; commits successful data before any global error handling.
    /// Returns `(didStop, tabSuccesses)` where `tabSuccesses` indicates which tabs fetched successfully
    /// (used by the notification pipeline to avoid false "merged" events on partial failures).
    func fetchAllTabsIndependently(
        token: StoredToken,
        login: String
    ) async -> (didStop: Bool, tabSuccesses: TabSuccesses) {
        async let incoming = fetchIncoming(token: token, login: login)
        async let outgoing = fetchOutgoing(token: token, login: login)
        async let drafts = fetchDrafts(token: token)
        let incomingResult = await incoming
        let outgoingResult = await outgoing
        let draftsResult = await drafts
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
        replaceData(HubberData(incoming: newIncoming, outgoing: newOutgoing, drafts: newDrafts))
        if let globalError = incomingGlobal ?? outgoingGlobal ?? draftsGlobal {
            await handleRefreshError(globalError, settingGlobalError: false)
            return (true, tabSuccesses)
        }
        return (false, tabSuccesses)
    }

    private func fetchIncoming(
        token: StoredToken,
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
        token: StoredToken,
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

    private func fetchDrafts(token: StoredToken) async -> Result<[DraftReview], Error> {
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
            if isGlobalError(error) {
                return (existing, error)
            }
            setTabError(error.localizedDescription, for: tab)
            appendDeveloperLog("\(label) tab refresh failed: \(error.localizedDescription)")
            return (existing, nil)
        }
    }

    private func isGlobalError(_ error: Error) -> Bool {
        if case CodeHostAuthError.rateLimited = error {
            return true
        }
        return Self.authState(afterRefreshError: error, signedInLogin: signedInLogin) != nil
    }

    func setTabError(_ message: String?, for tab: WorkTab) {
        switch tab {
        case .incoming: incomingError = message
        case .outgoing: outgoingError = message
        case .drafts: draftsError = message
        }
    }

}
