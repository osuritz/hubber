import AppKit
import SwiftUI

struct HubberPopoverView: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var store: HubberStore

    @State private var selectedTab: WorkTab = .incoming
    @State private var showSettings = false
    @State private var showSignInSuccess = false
    @State private var showingAdd = false

    var body: some View {
        ZStack {
            VisualEffectView(material: .popover)
                .ignoresSafeArea()

            HubberAppearance.panelFill(for: colorScheme)
                .ignoresSafeArea()

            authBranchedBody
        }
        .foregroundStyle(.primary)
        .onChange(of: selectedTab) { _, newTab in
            store.telemetry.tabSwitched(to: newTab)
        }
        .onChange(of: store.authState) { oldState, newState in
            // Only trigger on the in-panel device flow: waitingForUser → signedIn.
            // Do NOT trigger on cold-launch restore (restoring → signedIn).
            if case .waitingForUser = oldState, case .signedIn = newState {
                showSignInSuccess = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.3))
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showSignInSuccess = false
                    }
                }
            }
        }
    }

    // MARK: - Auth-state branching

    /// Top-level branch on auth state. Only `.signedIn` and `.sessionExpired`
    /// show the normal header + tabs + content + footer chrome.
    @ViewBuilder
    private var authBranchedBody: some View {
        switch store.authState {
        case .restoring:
            RestoringScreen()

        case .signedOut:
            SignInScreen(store: store)
                .overlay(alignment: .bottom) {
                    addDifferentAccountLink
                }
                .sheet(isPresented: $showingAdd) {
                    addAccountSheet
                }

        case let .error(message):
            SignInScreen(store: store)
                .overlay(alignment: .top) {
                    authErrorBanner(message: message)
                }
                .overlay(alignment: .bottom) {
                    addDifferentAccountLink
                }
                .sheet(isPresented: $showingAdd) {
                    addAccountSheet
                }

        case let .waitingForUser(authorization):
            DeviceCodeScreen(store: store, authorization: authorization)

        case let .signedIn(login):
            if showSignInSuccess {
                SignInSuccessScreen(login: login)
                    .transition(.opacity)
            } else {
                normalChrome
                    .transition(.opacity)
            }

        case .sessionExpired:
            normalChrome
        }
    }

    private func authErrorBanner(message: String) -> some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(HubberDesign.sloRed.fg)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(HubberDesign.sloRed.bg)
    }

    private var addDifferentAccountLink: some View {
        Button("Add GitHub Enterprise or GitLab…") {
            showingAdd = true
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(HubberDesign.text2)
        .padding(.bottom, 12)
    }

    private var addAccountSheet: some View {
        AddAccountView(
            policy: store.settings.providerAccessPolicy,
            addAccount: { [weak store] id, token, user in
                _ = try await store?.addResolvedAccount(
                    id: id,
                    token: token,
                    user: user
                )
            },
            onDone: { showingAdd = false }
        )
    }

    /// The normal popover chrome (header + tabs + scrollable content + footer).
    private var normalChrome: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(spacing: 0) {
                    if showSettings {
                        SettingsView(store: store, settings: store.settings)
                    } else {
                        content
                    }
                }
            }
            .scrollIndicators(.visible)
            .frame(maxHeight: .infinity)

            footer
        }
    }

    private var header: some View {
        VStack(spacing: 11) {
            HStack(spacing: 0) {
                AccountMenuView(store: store)

                Spacer()

                Button {
                    store.refreshPullRequests()
                } label: {
                    if store.isRefreshingPullRequests {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(store.canRefreshPullRequests ? HubberDesign.text2 : HubberDesign.text3)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .disabled(!store.canRefreshPullRequests || store.isRefreshingPullRequests)
                .help("Refresh pull requests (⌘R)")

                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(showSettings ? HubberDesign.accent : HubberDesign.text2)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .help("Settings (⌘,)")
                .keyboardShortcut(",", modifiers: .command)
            }

            HubberTabBar(
                selectedTab: $selectedTab,
                showSettings: $showSettings,
                counts: [
                    .incoming: store.data.incoming.count,
                    .outgoing: store.data.outgoing.count(where: { $0.ci == .failing || $0.unresolved > 0 }),
                    .drafts: store.data.drafts.count,
                ]
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            HubberDesign.sep.frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var content: some View {
        if case .sessionExpired = store.authState {
            ReauthPromptRow(store: store)
        } else {
            switch selectedTab {
            case .incoming:
                incomingContent
            case .outgoing:
                outgoingContent
            case .drafts:
                draftsContent
            }
        }
    }

    @ViewBuilder
    private var incomingContent: some View {
        if store.isRefreshingPullRequests, store.data.incoming.isEmpty {
            LoadingState()
        } else if store.incomingError != nil, store.data.incoming.isEmpty {
            ErrorState(
                message: "Couldn't load reviews",
                lastUpdated: lastUpdatedText,
                onRetry: { store.refreshPullRequests() }
            )
        } else if store.data.incoming.isEmpty {
            AllClearState()
        } else {
            if let error = store.incomingError {
                ErrorState(
                    message: "Couldn't load reviews",
                    lastUpdated: "Last refresh failed: \(error)",
                    onRetry: { store.refreshPullRequests() }
                )
            }
            let sorted = store.data.incoming.sorted { $0.sloClockStart < $1.sloClockStart }
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, review in
                ClickableRow(
                    url: review.url,
                    onOpen: { store.telemetry.itemOpened(in: .incoming) },
                    content: {
                        IncomingReviewRow(
                            review: review,
                            isSLOEnabled: store.settings.sloEnabled,
                            sloHours: store.settings.sloHours(for: review.repo),
                            sloDisplay: store.settings.sloDisplay,
                            density: store.settings.rowDensity,
                            isLast: index == sorted.count - 1
                        )
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var outgoingContent: some View {
        if store.isRefreshingPullRequests, store.data.outgoing.isEmpty {
            LoadingState()
        } else if store.outgoingError != nil, store.data.outgoing.isEmpty {
            ErrorState(
                message: "Couldn't load outgoing PRs",
                lastUpdated: lastUpdatedText,
                onRetry: { store.refreshPullRequests() }
            )
        } else if store.data.outgoing.isEmpty {
            EmptyOutgoingState()
        } else {
            if let error = store.outgoingError {
                ErrorState(
                    message: "Couldn't load outgoing PRs",
                    lastUpdated: "Last refresh failed: \(error)",
                    onRetry: { store.refreshPullRequests() }
                )
            }
            ForEach(Array(store.data.outgoing.enumerated()), id: \.element.id) { index, review in
                ClickableRow(
                    url: review.url,
                    onOpen: { store.telemetry.itemOpened(in: .outgoing) },
                    content: {
                        OutgoingReviewRow(
                            review: review,
                            density: store.settings.rowDensity,
                            isLast: index == store.data.outgoing.count - 1
                        )
                    }
                )
            }
        }
    }

    /// Drafts tab — #19: add error, loading, and empty states (matching Incoming/Outgoing).
    @ViewBuilder
    private var draftsContent: some View {
        if store.isRefreshingPullRequests, store.data.drafts.isEmpty {
            LoadingState()
        } else if store.draftsError != nil, store.data.drafts.isEmpty {
            ErrorState(
                message: "Couldn't load drafts",
                lastUpdated: lastUpdatedText,
                onRetry: { store.refreshPullRequests() }
            )
        } else if store.data.drafts.isEmpty {
            EmptyDraftsState()
        } else {
            if let error = store.draftsError {
                ErrorState(
                    message: "Couldn't load drafts",
                    lastUpdated: "Last refresh failed: \(error)",
                    onRetry: { store.refreshPullRequests() }
                )
            }
            ForEach(Array(store.data.drafts.enumerated()), id: \.element.id) { index, draft in
                ClickableRow(
                    url: draft.url,
                    onOpen: { store.telemetry.itemOpened(in: .drafts) },
                    content: {
                        DraftPRRow(
                            draft: draft,
                            density: store.settings.rowDensity,
                            isLast: index == store.data.drafts.count - 1
                        )
                    }
                )
            }
        }
    }

    private var lastUpdatedText: String? {
        guard let last = store.lastPullRequestRefresh else { return nil }
        return "Updated \(elapsedText(hours: Date().timeIntervalSince(last) / 3600))"
    }

    private var footer: some View {
        HStack(spacing: 6) {
            // Last-refresh status (per popover.jsx footer)
            if let rateLimitMessage = store.rateLimitMessage {
                Text(rateLimitMessage).lineLimit(1)
            } else {
                Text(refreshStatusText).lineLimit(1)
            }

            Spacer(minLength: 8)

            // ⌘R Refresh button (per popover.jsx "Refresh")
            Button {
                store.refreshPullRequests()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                    Text("⌘R")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(HubberDesign.text2)
            .disabled(store.isRefreshingPullRequests)
            .keyboardShortcut("r", modifiers: .command)
        }
        .font(HubberType.footer)
        .foregroundStyle(HubberDesign.text2)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            HubberDesign.sep.frame(height: 0.5)
        }
    }

    private var refreshStatusText: String {
        if store.isRefreshingPullRequests {
            return "Refreshing PRs..."
        }
        let hasAnyError = store.pullRequestRefreshError != nil
            || store.incomingError != nil
            || store.outgoingError != nil
            || store.draftsError != nil
        if hasAnyError {
            return "Refresh failed"
        }
        if let lastPullRequestRefresh = store.lastPullRequestRefresh {
            return "Updated \(elapsedText(hours: Date().timeIntervalSince(lastPullRequestRefresh) / 3600))"
        }
        return store.canRefreshPullRequests ? "Not refreshed yet" : "Mock data"
    }

}

private struct ClickableRow<Content: View>: View {
    let url: URL?
    var onOpen: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        if let url {
            Button {
                onOpen?()
                NSWorkspace.shared.open(url)
            } label: {
                content()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open pull request")
        } else {
            content()
        }
    }
}

private struct HubberTabBar: View {
    @Binding var selectedTab: WorkTab
    @Binding var showSettings: Bool
    let counts: [WorkTab: Int]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(WorkTab.allCases) { tab in
                let isActive = selectedTab == tab && !showSettings
                Button {
                    selectedTab = tab
                    showSettings = false
                } label: {
                    HStack(spacing: 5) {
                        Text(tab.title)
                        let badgeCount = counts[tab, default: 0]
                        if badgeCount > 0 {
                            CountBadge(count: badgeCount, isActive: isActive)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? HubberDesign.text : HubberDesign.text2)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                            .fill(HubberDesign.ctrlThumb)
                            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                    }
                }
            }
        }
        .padding(2)
        .background(
            HubberDesign.ctrlTrack,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }
}

private struct CountBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let count: Int
    var isActive = false

    var body: some View {
        Text("\(count)")
            .font(HubberType.badge)
            .foregroundStyle(isActive ? HubberDesign.text : HubberDesign.text2)
            .frame(minWidth: 16)
            .padding(.horizontal, 5)
            .lineLimit(1)
            .background(
                HubberAppearance.badgeFill(isActive: isActive, for: colorScheme),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
    }
}

// SettingsView and SettingsSection are in HubberSettingsView.swift
// Row components (IncomingReviewRow, OutgoingReviewRow, DraftPRRow, etc.) are in HubberRows.swift
// List states (AllClearState, ErrorState, LoadingState, etc.) are in HubberListStates.swift
