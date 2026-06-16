import AppKit
import SwiftUI

struct HubberPopoverView: View {
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject var store: HubberStore

    @State private var selectedTab: WorkTab = .incoming
    @State private var showSettings = false

    var body: some View {
        ZStack {
            VisualEffectView(material: .popover)
                .ignoresSafeArea()

            HubberAppearance.panelFill(for: colorScheme)
                .ignoresSafeArea()

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
        .foregroundStyle(.primary)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("GitHub")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(store.usernameDisplay)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

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
                .foregroundStyle(store.canRefreshPullRequests ? .secondary : .tertiary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .disabled(!store.canRefreshPullRequests || store.isRefreshingPullRequests)
                .help("Refresh pull requests")

                Button {
                    showSettings.toggle()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(showSettings ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
            }

            HubberTabBar(
                selectedTab: $selectedTab,
                showSettings: $showSettings,
                counts: [
                    .incoming: store.data.incoming.count,
                    .outgoing: store.data.outgoing.count,
                    .drafts: store.data.drafts.count,
                ]
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.55)
        }
    }

    @ViewBuilder
    private var content: some View {
        if case .sessionExpired = store.authState {
            ReauthPromptRow(store: store)
        } else {
            switch selectedTab {
            case .incoming:
                if let error = store.pullRequestRefreshError, store.data.incoming.isEmpty {
                    EmptyStateRow(text: "Refresh failed: \(error)")
                } else if store.isRefreshingPullRequests, store.data.incoming.isEmpty {
                    EmptyStateRow(text: "Loading reviews…")
                } else if store.data.incoming.isEmpty, store.lastPullRequestRefresh != nil {
                    AllClearRow()
                } else if store.data.incoming.isEmpty, store.lastPullRequestRefresh == nil {
                    EmptyStateRow(text: "Loading reviews…")
                } else {
                    let sorted = store.data.incoming.sorted { $0.sloClockStart < $1.sloClockStart }
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, review in
                        ClickableRow(url: review.url) {
                            IncomingReviewRow(
                                review: review,
                                isSLOEnabled: store.settings.sloEnabled,
                                sloHours: store.settings.sloHours(for: review.repo),
                                sloDisplay: store.settings.sloDisplay,
                                density: store.settings.rowDensity,
                                isLast: index == sorted.count - 1
                            )
                        }
                    }
                }
            case .outgoing:
                if let error = store.pullRequestRefreshError, store.data.outgoing.isEmpty {
                    EmptyStateRow(text: "Refresh failed: \(error)")
                } else if store.isRefreshingPullRequests, store.data.outgoing.isEmpty {
                    EmptyStateRow(text: "Loading pull requests…")
                } else if store.data.outgoing.isEmpty, store.lastPullRequestRefresh != nil {
                    EmptyStateRow(text: "No open pull requests.")
                } else if store.data.outgoing.isEmpty, store.lastPullRequestRefresh == nil {
                    EmptyStateRow(text: "Loading pull requests…")
                } else {
                    ForEach(Array(store.data.outgoing.enumerated()), id: \.element.id) { index, review in
                        ClickableRow(url: review.url) {
                            OutgoingReviewRow(
                                review: review,
                                density: store.settings.rowDensity,
                                isLast: index == store.data.outgoing.count - 1
                            )
                        }
                    }
                }
            case .drafts:
                if store.data.drafts.isEmpty {
                    EmptyStateRow(text: draftEmptyText)
                } else {
                    ForEach(Array(store.data.drafts.enumerated()), id: \.element.id) { index, draft in
                        ClickableRow(url: draft.url) {
                            DraftRow(
                                draft: draft,
                                density: store.settings.rowDensity,
                                isLast: index == store.data.drafts.count - 1
                            )
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let rateLimitMessage = store.rateLimitMessage {
                Text(rateLimitMessage).lineLimit(1)
            } else {
                Text(refreshStatusText).lineLimit(1)
            }
            Spacer()
            Text(ReviewSLOPresentation.footerText(
                isEnabled: store.settings.sloEnabled,
                hours: store.settings.sloHours
            ))
            Text("⌘, Settings")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            Divider().opacity(0.55)
        }
        .background {
            // ⌘R keyboard shortcut for manual refresh
            Button("") {
                store.refreshPullRequests()
            }
            .keyboardShortcut("r", modifiers: .command)
            .hidden()
        }
    }

    private var refreshStatusText: String {
        if store.isRefreshingPullRequests {
            return "Refreshing PRs..."
        }
        if store.pullRequestRefreshError != nil {
            return "Refresh failed"
        }
        if let lastPullRequestRefresh = store.lastPullRequestRefresh {
            return "Updated \(elapsedText(hours: Date().timeIntervalSince(lastPullRequestRefresh) / 3600))"
        }
        return store.canRefreshPullRequests ? "Not refreshed yet" : "Mock data"
    }

    private var draftEmptyText: String {
        if let error = store.pullRequestRefreshError {
            return "Refresh failed: \(error)"
        }
        if store.isRefreshingPullRequests {
            return "Refreshing draft pull requests"
        }
        return store.canRefreshPullRequests ? "No accessible draft pull requests" : "No draft pull requests"
    }
}

private struct ClickableRow<Content: View>: View {
    let url: URL?
    @ViewBuilder let content: () -> Content

    var body: some View {
        if let url {
            Button {
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
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedTab: WorkTab
    @Binding var showSettings: Bool
    let counts: [WorkTab: Int]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(WorkTab.allCases) { tab in
                Button {
                    selectedTab = tab
                    showSettings = false
                } label: {
                    HStack(spacing: 5) {
                        Text(tab.title)
                        CountBadge(count: counts[tab, default: 0], isActive: selectedTab == tab && !showSettings)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selectedTab == tab && !showSettings ? .primary : .secondary)
                .background(
                    Group {
                        if selectedTab == tab, !showSettings {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(HubberAppearance.selectedControlFill(for: colorScheme))
                                .shadow(
                                    color: HubberAppearance.controlShadow(for: colorScheme),
                                    radius: 1,
                                    y: 1
                                )
                        }
                    }
                )
            }
        }
        .padding(2)
        .background(
            HubberAppearance.controlGroupFill(for: colorScheme),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

private struct CountBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let count: Int
    var isActive = false

    var body: some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(isActive ? .primary : .secondary)
            .frame(minWidth: 15)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                HubberAppearance.badgeFill(isActive: isActive, for: colorScheme),
                in: Capsule()
            )
            .overlay {
                Capsule().stroke(HubberAppearance.hairline(for: colorScheme), lineWidth: 0.5)
            }
    }
}

private struct IncomingReviewRow: View {
    let review: IncomingReview
    let isSLOEnabled: Bool
    let sloHours: Double
    let sloDisplay: SLODisplay
    let density: RowDensity
    let isLast: Bool

    var body: some View {
        RowShell(density: density, isLast: isLast) {
            AvatarView(user: review.author, size: density == .compact ? 18 : density == .spacious ? 26 : 22)

            VStack(alignment: .leading, spacing: density == .compact ? 0 : 3) {
                PRTitle(number: review.number, title: review.title, density: density)

                if density != .compact {
                    HStack(spacing: 6) {
                        Text(review.repo)
                        Text("·")
                        Text(review.author.login)

                        if density == .spacious {
                            Text("·")
                            Text("+\(review.additions)")
                                .foregroundStyle(Color.green)
                            Text("-\(review.deletions)")
                                .foregroundStyle(Color.red)
                            Text("·")
                            Text("\(review.files) files")
                        }
                    }
                    .lineLimit(1)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSLOEnabled {
                SLOPill(status: sloStatus, text: sloText, helpText: sloHelpText)
            }
        }
    }

    private var sloStatus: SLOStatus {
        let ratio = review.assignedAgoHours / sloHours
        if ratio < 0.5 { return .green }
        if ratio < 1 { return .amber }
        return .red
    }

    private var sloText: String {
        switch sloDisplay {
        case .elapsed:
            elapsedText(hours: review.assignedAgoHours)
        case .traffic:
            switch sloStatus {
            case .green:
                "On track"
            case .amber:
                "Due soon"
            case .red:
                "Past SLO"
            }
        case .remaining:
            remainingText(hours: sloHours - review.assignedAgoHours)
        }
    }

    private var sloHelpText: String? {
        switch sloDisplay {
        case .elapsed:
            elapsedText(hours: review.assignedAgoHours)
        case .traffic, .remaining:
            remainingDetailText(hours: sloHours - review.assignedAgoHours)
        }
    }
}

private struct OutgoingReviewRow: View {
    let review: OutgoingReview
    let density: RowDensity
    let isLast: Bool

    var body: some View {
        RowShell(density: density, isLast: isLast) {
            CIBadge(ci: review.ci, size: density == .compact ? 12 : density == .spacious ? 16 : 14)
                .padding(.top, density == .compact ? 0 : 2)

            VStack(alignment: .leading, spacing: density == .compact ? 0 : 3) {
                PRTitle(number: review.number, title: review.title, density: density)

                if density != .compact {
                    HStack(spacing: 6) {
                        Text(review.repo)
                        Text("·")
                        Text(review.ciDetail)
                            .foregroundStyle(HubberDesign.ciColor(for: review.ci))

                        if review.unresolved > 0 {
                            Text("·")
                            Label("\(review.unresolved) unresolved", systemImage: "text.bubble")
                                .labelStyle(.titleAndIcon)
                        }

                        if density == .spacious {
                            Text("·")
                            Text("\(review.approvals)/\(review.requiredApprovals) approved")
                        }
                    }
                    .lineLimit(1)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if density != .compact {
                ReviewerStack(reviewers: review.reviewers, size: density == .spacious ? 22 : 18)
            }
        }
    }
}

private struct DraftRow: View {
    let draft: DraftReview
    let density: RowDensity
    let isLast: Bool

    var body: some View {
        RowShell(density: density, isLast: isLast) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .frame(
                        width: density == .spacious ? 22 : density == .compact ? 16 : 18,
                        height: density == .spacious ? 22 : density == .compact ? 16 : 18
                    )

                Image(systemName: "doc")
                    .font(.system(size: density == .spacious ? 11 : 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, density == .compact ? 0 : 1)

            VStack(alignment: .leading, spacing: density == .compact ? 0 : 3) {
                PRTitle(number: draft.number, title: draft.title, density: density)

                if density != .compact {
                    HStack(spacing: 6) {
                        Text(draft.repo)
                        Text("·")
                        Text("\(draft.commits) commits")
                        Text("·")
                        Text(elapsedText(hours: draft.updatedAgoHours))
                    }
                    .lineLimit(1)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                CIBadge(ci: draft.ci, size: density == .spacious ? 14 : 12)

                if density != .compact {
                    Text(draftStatusText)
                        .font(HubberType.ciDetail)
                        .foregroundStyle(HubberDesign.ciColor(for: draft.ci))
                }
            }
        }
    }

    private var draftStatusText: String {
        switch draft.ci {
        case .passing: "✓"
        case .failing: draft.ciDetail.components(separatedBy: " ").first ?? "Fail"
        case .running: "…"
        case .pending: "Pending"
        }
    }
}

private struct EmptyStateRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, minHeight: 70)
    }
}

private struct AllClearRow: View {
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.hubberSuccess.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.hubberSuccess)
            }
            Text("All clear")
                .font(.system(size: 14, weight: .semibold))
            Text("No reviews waiting on you. Enjoy the deep work.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }
}

// SettingsView and SettingsSection are in HubberSettingsView.swift

private struct RowShell<Content: View>: View {
    let density: RowDensity
    let isLast: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: density == .compact ? .center : .top, spacing: 10) {
            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, verticalPadding)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().opacity(0.55)
            }
        }
    }

    private var verticalPadding: CGFloat {
        switch density {
        case .compact: 7
        case .normal: 10
        case .spacious: 12
        }
    }
}

private struct PRTitle: View {
    let number: Int
    let title: String
    let density: RowDensity

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("#\(number)")
                .font(.system(size: density == .compact ? 12.5 : 13).monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()

            Text(title)
                .font(.system(size: density == .compact ? 12.5 : 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

private struct SLOPill: View {
    let status: SLOStatus
    let text: String
    let helpText: String?

    var body: some View {
        let tokens = HubberDesign.sloTokens(for: status)
        HStack(spacing: 5) {
            // Non-color cue: colored dot (shape) + text (label)
            Circle()
                .fill(tokens.fg)
                .frame(width: 6, height: 6)

            Text(text)
                .font(HubberType.sloPill)
                .foregroundStyle(tokens.fg)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2.5)
        .background(tokens.bg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(tokens.border, lineWidth: 0.5)
        }
        .help(helpText ?? text)
    }
}

private struct CIBadge: View {
    let ci: PullRequestCI
    let size: CGFloat

    var body: some View {
        let color = HubberDesign.ciColor(for: ci)
        ZStack {
            switch ci {
            case .passing:
                // Filled circle + checkmark (non-color cue: shape + icon)
                Circle().fill(color)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.50, weight: .bold))
                    .foregroundStyle(.white)
            case .failing:
                // Filled circle + xmark (non-color cue: shape + icon)
                Circle().fill(color)
                Image(systemName: "xmark")
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(.white)
            case .running:
                // Neutral spinner (non-color cue: animation)
                ProgressView()
                    .controlSize(.small)
                    .tint(color)
                    .scaleEffect(size / 16)
            case .pending:
                // Clock outline (non-color cue: clock icon = "pending/waiting")
                Circle()
                    .stroke(color, lineWidth: 1.5)
                Image(systemName: "clock")
                    .font(.system(size: size * 0.44, weight: .regular))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct ReviewerStack: View {
    @Environment(\.colorScheme) private var colorScheme

    let reviewers: [Reviewer]
    let size: CGFloat

    var body: some View {
        HStack(spacing: -6) {
            ForEach(reviewers.prefix(3)) { reviewer in
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(user: reviewer.user, size: size)

                    if let color = reviewerStateColor(reviewer.state) {
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                            .overlay {
                                Circle().stroke(
                                    HubberAppearance.statusDotStroke(for: colorScheme),
                                    lineWidth: 1.5
                                )
                            }
                            .offset(x: 1, y: 1)
                    }
                }
            }
        }
    }
}

private func reviewerStateColor(_ state: ReviewerState) -> Color? {
    HubberDesign.reviewerColor(for: state)
}
