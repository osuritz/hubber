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

    private var footer: some View {
        HStack {
            Text(refreshStatusText).lineLimit(1)
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
                            .foregroundStyle(ciColor(review.ci))

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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ciColor(draft.ci))
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

private struct SettingsView: View {
    @ObservedObject var store: HubberStore
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            SettingsSection(title: "GitHub Account") {
                GitHubAuthSettingsView(store: store)
            }

            SettingsSection(title: "Developer") {
                DeveloperPanelView(store: store)
            }

            SettingsSection(title: ReviewSLOPresentation.settingsSectionTitle) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ReviewSLOPresentation.title)
                            .font(.system(size: 13, weight: .medium))
                        Text(ReviewSLOPresentation.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.sloEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(settings.isLocked("reviewSLOEnabled"))
                }

                HStack(spacing: 12) {
                    Text(ReviewSLOPresentation.windowLabel).font(.system(size: 13))
                    Spacer(minLength: 12)
                    Slider(value: $settings.sloHours, in: 1...24, step: 1)
                        .frame(width: 190)
                    Text("\(Int(settings.sloHours))h")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .frame(width: 36, alignment: .trailing)
                }
                .disabled(!settings.sloEnabled || settings.isLocked("sloWindowHours"))
                .opacity(settings.sloEnabled ? 1 : 0.45)

                Text(ReviewSLOPresentation.thresholdHelp)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(settings.sloEnabled ? 1 : 0.55)
            }

            SettingsSection(title: "Show SLO as") {
                Picker("", selection: $settings.sloDisplay) {
                    ForEach(SLODisplay.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!settings.sloEnabled)
                .opacity(settings.sloEnabled ? 1 : 0.45)
            }

            SettingsSection(title: "Incoming mode") {
                Picker("", selection: $settings.incomingMode) {
                    ForEach(IncomingReviewMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(settings.isLocked("incomingMode"))
            }

            SettingsSection(title: "Unresolved threads") {
                Picker("", selection: $settings.unresolvedMode) {
                    ForEach(UnresolvedThreadMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(settings.isLocked("unresolvedThreadMode"))
            }

            SettingsSection(title: "Row density", isLast: true) {
                Picker("", selection: $settings.rowDensity) {
                    ForEach(RowDensity.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(settings.isLocked("rowDensity"))
            }
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    var isLast = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(.secondary)

            content()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider().opacity(0.55)
            }
        }
    }
}

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
    @Environment(\.colorScheme) private var colorScheme

    let status: SLOStatus
    let text: String
    let helpText: String?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(HubberAppearance.sloDotShadowOpacity(for: colorScheme)), radius: 3)

            Text(text)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(color.opacity(HubberAppearance.sloFillOpacity(status, for: colorScheme)), in: Capsule())
        .overlay {
            Capsule().stroke(color.opacity(HubberAppearance.sloStrokeOpacity(status, for: colorScheme)), lineWidth: 0.5)
        }
        .help(helpText ?? text)
    }

    private var color: Color {
        HubberAppearance.sloColor(status, for: colorScheme)
    }
}

private struct CIBadge: View {
    let ci: PullRequestCI
    let size: CGFloat

    var body: some View {
        ZStack {
            switch ci {
            case .passing:
                Circle().fill(ciColor(ci))
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.55, weight: .bold))
                    .foregroundStyle(.white)
            case .failing:
                Circle().fill(ciColor(ci))
                Image(systemName: "xmark")
                    .font(.system(size: size * 0.52, weight: .bold))
                    .foregroundStyle(.white)
            case .running:
                ProgressView()
                    .controlSize(.small)
                    .tint(ciColor(ci))
                    .scaleEffect(size / 16)
            case .pending:
                Circle()
                    .stroke(.secondary, lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct AvatarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var image: NSImage?

    let user: GitHubUser
    let size: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(user.initials)
                    .font(.system(size: round(size * 0.42), weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: size, height: size)
                    .background(user.color, in: Circle())
            }
        }
        .overlay {
            Circle().stroke(HubberAppearance.avatarStroke(for: colorScheme), lineWidth: 0.5)
        }
        .task(id: user.avatarURL) {
            guard let url = user.avatarURL else { return }
            image = await AvatarCache.shared.image(for: url)
        }
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

private func ciColor(_ ci: PullRequestCI) -> Color {
    switch ci {
    case .passing: .hubberSuccess
    case .failing: .hubberError
    case .running: .hubberWarning
    case .pending: .secondary
    }
}

private func reviewerStateColor(_ state: ReviewerState) -> Color? {
    switch state {
    case .approved: Color(red: 0.20, green: 0.78, blue: 0.35)
    case .changesRequested: Color(red: 1.00, green: 0.27, blue: 0.23)
    case .commented: Color(red: 0.04, green: 0.52, blue: 1.00)
    case .pending: nil
    }
}
