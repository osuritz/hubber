import SwiftUI

struct HubberPopoverView: View {
    @ObservedObject var store: HubberStore

    @State private var selectedTab: WorkTab = .incoming
    @State private var showSettings = false
    @State private var sloHours = 4.0
    @State private var sloDisplay: SLODisplay = .remaining
    @State private var rowDensity: RowDensity = .normal

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(spacing: 0) {
                        if showSettings {
                            SettingsView(
                                store: store,
                                sloHours: $sloHours,
                                sloDisplay: $sloDisplay,
                                rowDensity: $rowDensity
                            )
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
        .preferredColorScheme(.dark)
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
                    .drafts: store.data.drafts.count
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
            let sorted = store.data.incoming.sorted { $0.assignedAgoHours > $1.assignedAgoHours }
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, review in
                IncomingReviewRow(
                    review: review,
                    sloHours: sloHours,
                    sloDisplay: sloDisplay,
                    density: rowDensity,
                    isLast: index == sorted.count - 1
                )
            }
        case .outgoing:
            ForEach(Array(store.data.outgoing.enumerated()), id: \.element.id) { index, review in
                OutgoingReviewRow(
                    review: review,
                    density: rowDensity,
                    isLast: index == store.data.outgoing.count - 1
                )
            }
        case .drafts:
            ForEach(Array(store.data.drafts.enumerated()), id: \.element.id) { index, draft in
                DraftRow(
                    draft: draft,
                    density: rowDensity,
                    isLast: index == store.data.drafts.count - 1
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Updated 2 min ago")
            Spacer()
            Text("SLO \(Int(sloHours))h")
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
}

private struct HubberTabBar: View {
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
                        if selectedTab == tab && !showSettings {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.white.opacity(0.16))
                                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                        }
                    }
                )
            }
        }
        .padding(2)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CountBadge: View {
    let count: Int
    var isActive = false

    var body: some View {
        Text("\(count)")
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(isActive ? .primary : .secondary)
            .frame(minWidth: 15)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.white.opacity(isActive ? 0.16 : 0.10), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.10), lineWidth: 0.5)
            }
    }
}

private struct IncomingReviewRow: View {
    let review: IncomingReview
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

            Spacer(minLength: 8)

            SLOPill(status: sloStatus, text: sloText)
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
            return elapsedText(hours: review.assignedAgoHours)
        case .traffic:
            switch sloStatus {
            case .green:
                return "On track"
            case .amber:
                return "Due soon"
            case .red:
                return "Past SLO"
            }
        case .remaining:
            return remainingText(hours: sloHours - review.assignedAgoHours)
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
                    .frame(width: density == .spacious ? 22 : density == .compact ? 16 : 18, height: density == .spacious ? 22 : density == .compact ? 16 : 18)

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

private struct SettingsView: View {
    @ObservedObject var store: HubberStore
    @Binding var sloHours: Double
    @Binding var sloDisplay: SLODisplay
    @Binding var rowDensity: RowDensity

    var body: some View {
        VStack(spacing: 0) {
            settingsSection(title: "GitHub Account") {
                GitHubAuthSettingsView(store: store)
            }

            settingsSection(title: "Review SLO") {
                HStack(spacing: 10) {
                    Slider(value: $sloHours, in: 1...24, step: 1)
                    Text("\(Int(sloHours))h")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .frame(width: 56, alignment: .trailing)
                }

                Text("Reviews are flagged amber at 50% and red at 100% of this budget.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            settingsSection(title: "Show SLO as") {
                Picker("", selection: $sloDisplay) {
                    ForEach(SLODisplay.allCases) { display in
                        Text(display.title).tag(display)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            settingsSection(title: "Row density", isLast: true) {
                Picker("", selection: $rowDensity) {
                    ForEach(RowDensity.allCases) { density in
                        Text(density.title).tag(density)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private func settingsSection<Content: View>(title: String, isLast: Bool = false, @ViewBuilder content: () -> Content) -> some View {
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

private struct GitHubAuthSettingsView: View {
    @ObservedObject var store: HubberStore

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            switch store.authState {
            case .restoring:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking GitHub sign-in")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

            case .signedOut:
                Button {
                    store.startSignIn()
                } label: {
                    Label("Sign in with GitHub", systemImage: "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)

            case .waitingForUser(let authorization):
                HStack(spacing: 8) {
                    Text(authorization.userCode)
                        .font(.system(size: 18, weight: .semibold).monospaced())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Button {
                        store.copyDeviceCode()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .help("Copy code")

                    Spacer()
                }

                HStack(spacing: 8) {
                    Button {
                        store.openDeviceVerificationPage()
                    } label: {
                        Label("Open GitHub", systemImage: "safari")
                    }

                    Button("Cancel") {
                        store.cancelSignIn()
                    }
                }
                .controlSize(.small)

                Text("Enter this code at github.com/login/device.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

            case .signedIn(let login):
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(red: 0.25, green: 0.73, blue: 0.31))

                    Text("@\(login)")
                        .font(.system(size: 13, weight: .semibold))

                    Spacer()

                    Button("Sign out") {
                        store.signOut()
                    }
                    .controlSize(.small)
                }

            case .error(let message):
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(red: 1.00, green: 0.48, blue: 0.45))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Try again") {
                        store.startSignIn()
                    }

                    Button("Clear") {
                        store.signOut()
                    }
                }
                .controlSize(.small)
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
    let status: SLOStatus
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.65), radius: 3)

            Text(text)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(color.opacity(status == .red ? 0.18 : 0.16), in: Capsule())
        .overlay {
            Capsule().stroke(color.opacity(status == .red ? 0.45 : 0.40), lineWidth: 0.5)
        }
    }

    private var color: Color {
        switch status {
        case .green: Color(red: 0.25, green: 0.73, blue: 0.31)
        case .amber: Color(red: 0.89, green: 0.70, blue: 0.25)
        case .red: Color(red: 1.00, green: 0.48, blue: 0.45)
        }
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
    let user: GitHubUser
    let size: CGFloat

    var body: some View {
        Text(user.initials)
            .font(.system(size: round(size * 0.42), weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(user.color, in: Circle())
            .overlay {
                Circle().stroke(.black.opacity(0.15), lineWidth: 0.5)
            }
    }
}

private struct ReviewerStack: View {
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
                                Circle().stroke(Color(red: 0.15, green: 0.15, blue: 0.17), lineWidth: 1.5)
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
    case .passing: Color(red: 0.25, green: 0.73, blue: 0.31)
    case .failing: Color(red: 1.00, green: 0.48, blue: 0.45)
    case .running: Color(red: 0.89, green: 0.70, blue: 0.25)
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

private func elapsedText(hours: Double) -> String {
    let minutes = Int((hours * 60).rounded(.down))
    if minutes < 1 { return "just now" }
    if minutes < 60 { return "\(minutes)m ago" }
    if minutes < 24 * 60 {
        let h = minutes / 60
        let m = minutes % 60
        return m > 0 ? "\(h)h \(m)m ago" : "\(h)h ago"
    }
    return "\(minutes / (24 * 60))d ago"
}

private func remainingText(hours: Double) -> String {
    if hours <= 0 {
        let over = abs(hours)
        let minutes = Int((over * 60).rounded(.down))
        if minutes < 60 { return "\(minutes)m over" }
        let h = minutes / 60
        let m = minutes % 60
        return m > 0 ? "\(h)h \(m)m over" : "\(h)h over"
    }

    let minutes = Int((hours * 60).rounded(.down))
    if minutes < 60 { return "\(minutes)m left" }
    let h = minutes / 60
    let m = minutes % 60
    return m > 0 ? "\(h)h \(m)m left" : "\(h)h left"
}
