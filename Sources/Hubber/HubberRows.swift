import SwiftUI

// MARK: - Density Configuration (per rows.jsx densityCfg)

struct RowDensityCfg {
    let padV: CGFloat
    let padH: CGFloat
    let avatar: CGFloat
    let secondary: Bool
    let rv: CGFloat
    let ci: CGFloat
    let gap: CGFloat
}

extension RowDensity {
    var cfg: RowDensityCfg {
        switch self {
        case .compact:
            RowDensityCfg(
                padV: 6,
                padH: 14,
                avatar: 28,
                secondary: false,
                rv: 20,
                ci: 18,
                gap: 9
            )
        case .normal:
            RowDensityCfg(
                padV: 9.5,
                padH: 14,
                avatar: 36,
                secondary: true,
                rv: 24,
                ci: 22,
                gap: 11
            )
        case .spacious:
            RowDensityCfg(
                padV: 13,
                padH: 16,
                avatar: 40,
                secondary: true,
                rv: 26,
                ci: 24,
                gap: 13
            )
        }
    }
}

// MARK: - RowShell (shared frame with signal treatment)

struct RowShell<Content: View>: View {
    let density: RowDensity
    let isLast: Bool
    var isSignal = false
    /// Rail-indicator mode: a full-height colour rail drawn at the leading edge. Its colour
    /// already encodes CI state, so it subsumes the signal accent (we draw one or the other,
    /// never both); the `signalTint` background still flags attention rows in either mode.
    var railColor: Color?
    @ViewBuilder let content: () -> Content

    var body: some View {
        let cfg = density.cfg
        // Either edge treatment occupies the leading 3pt, so pull content in to match.
        let hasEdgeBar = railColor != nil || isSignal
        HStack(alignment: cfg.secondary ? .top : .center, spacing: cfg.gap) {
            content()
        }
        .padding(.leading, hasEdgeBar ? cfg.padH - 3 : cfg.padH)
        .padding(.trailing, cfg.padH)
        .padding(.vertical, cfg.padV)
        .background {
            if isSignal {
                HubberDesign.signalTint
                    .ignoresSafeArea()
            }
        }
        .overlay(alignment: .leading) {
            if let railColor {
                railColor
                    .frame(width: 3)
            } else if isSignal {
                HubberDesign.signalAccent
                    .frame(width: 3)
            }
        }
        .overlay(alignment: .bottom) {
            if !isLast {
                HubberDesign.sep
                    .frame(height: 0.5)
            }
        }
    }
}

// MARK: - PRTitleLine

struct PRTitleLine: View {
    let number: Int
    let title: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("#\(number)")
                .hubberFont(.prNumber)
                .foregroundStyle(HubberDesign.text3)
                .fixedSize()

            Text(title)
                .hubberFont(.title)
                .foregroundStyle(HubberDesign.text)
                .lineLimit(1)
                .truncationMode(.tail)
                // Full title on hover, since the line truncates.
                .help(title)
        }
    }
}

// MARK: - SecondaryLine

struct SecondaryLine<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 5) {
            content()
        }
        .hubberFont(.secondary)
        .foregroundStyle(HubberDesign.text2)
        .lineLimit(1)
    }
}

struct RowDot: View {
    var body: some View {
        Text("·").foregroundStyle(HubberDesign.text3)
            .accessibilityHidden(true)
    }
}

/// PR size indicator: "+<added>" in green, "-<removed>" in red, counts
/// abbreviated at ≥1000. The +/- signs carry the meaning so it reads without
/// relying on color. VoiceOver announces size via the row's composed label, so
/// this view is hidden from the accessibility tree.
struct PRSizeView: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        HStack(spacing: 4) {
            Text("+\(abbreviatedLineCount(additions))")
                .foregroundStyle(HubberDesign.diffAdded)
            Text("-\(abbreviatedLineCount(deletions))")
                .foregroundStyle(HubberDesign.diffRemoved)
        }
        .hubberFont(.prSize)
        .monospacedDigit()
        .accessibilityHidden(true)
    }
}

// MARK: - IncomingReviewRow

struct IncomingReviewRow: View {
    let review: IncomingReview
    let isSLOEnabled: Bool
    let sloHours: Double
    let sloDisplay: SLODisplay
    let density: RowDensity
    let isLast: Bool

    var body: some View {
        let cfg = density.cfg
        RowShell(density: density, isLast: isLast) {
            AvatarView(user: review.author, size: cfg.avatar, accessibilityRole: "author")
                .alignmentGuide(.top) { $0[.top] }

            VStack(alignment: .leading, spacing: cfg.secondary ? 3 : 0) {
                PRTitleLine(number: review.number, title: review.title)

                if cfg.secondary {
                    SecondaryLine {
                        Text(review.repo).lineLimit(1)
                        RowDot()
                        Text(review.author.login)
                        if review.additions > 0 || review.deletions > 0 {
                            RowDot()
                            PRSizeView(additions: review.additions, deletions: review.deletions)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSLOEnabled {
                SLOPillView(status: sloStatus, text: sloText, helpText: sloHelpText)
                    .alignmentGuide(.top) { $0[.top] + 1 }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessibilityText.incomingRow(
            number: review.number, title: review.title, repo: review.repo,
            authorLogin: review.author.login, sloEnabled: isSLOEnabled,
            sloStatus: isSLOEnabled ? sloStatus : nil,
            sloText: isSLOEnabled ? sloText : nil,
            additions: review.additions, deletions: review.deletions
        ))
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
            case .green: "On track"
            case .amber: "Due soon"
            case .red: "Overdue"
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

// MARK: - OutgoingReviewRow

struct OutgoingReviewRow: View {
    let review: OutgoingReview
    let density: RowDensity
    let isLast: Bool
    var indicatorStyle: StatusIndicatorStyle = .rail

    /// Action signal: failing CI or unresolved threads (running is NOT a signal per spec).
    var isSignal: Bool {
        review.ci == .failing || review.unresolved > 0
    }

    var body: some View {
        let cfg = density.cfg
        // Use the rail only when a non-colour CI cue exists elsewhere — the secondary line's CI
        // detail text. Compact rows have no secondary line, so they keep the CIBadgeView (whose
        // shape is the non-colour cue); otherwise CI would be conveyed by rail colour alone.
        let railColor: Color? = (indicatorStyle == .rail && cfg.secondary)
            ? HubberDesign.ciColor(for: review.ci)
            : nil
        RowShell(density: density, isLast: isLast, isSignal: isSignal, railColor: railColor) {
            if railColor == nil {
                CIBadgeView(ci: review.ci, size: cfg.ci)
                    .alignmentGuide(.top) { $0[.top] + 1 }
            }

            VStack(alignment: .leading, spacing: cfg.secondary ? 3 : 0) {
                PRTitleLine(number: review.number, title: review.title)

                if cfg.secondary {
                    SecondaryLine {
                        Text(review.repo)
                        RowDot()
                        // CI detail colored red when failing (non-color cue: also shows "failed" text)
                        Text(review.ciDetail)
                            .foregroundStyle(
                                review.ci == .failing
                                    ? HubberDesign.ciColor(for: review.ci)
                                    : HubberDesign.text2
                            )

                        if review.unresolved > 0 {
                            RowDot()
                            // Thread count — non-color cue: bubble icon + number
                            Label(
                                "\(review.unresolved) \(review.unresolved == 1 ? "thread" : "threads")",
                                systemImage: "text.bubble"
                            )
                            .labelStyle(.titleAndIcon)
                        }

                        if review.additions > 0 || review.deletions > 0 {
                            RowDot()
                            PRSizeView(additions: review.additions, deletions: review.deletions)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Review axis (pairs with the CI rail): the aggregate verdict as a labelled pill.
            ReviewPillView(verdict: review.reviewVerdict)
                .alignmentGuide(.top) { $0[.top] + 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessibilityText.outgoingRow(
            number: review.number, title: review.title, repo: review.repo,
            ci: review.ci, unresolved: review.unresolved, verdict: review.reviewVerdict,
            additions: review.additions, deletions: review.deletions
        ))
    }
}

// MARK: - DraftPRRow (named to avoid collision with old DraftRow in popover)

struct DraftPRRow: View {
    let draft: DraftReview
    let density: RowDensity
    let isLast: Bool
    var indicatorStyle: StatusIndicatorStyle = .rail

    var body: some View {
        let cfg = density.cfg
        // Same rule as OutgoingReviewRow: rail only when the secondary line carries CI text as a
        // non-colour cue; compact rows keep the CIBadgeView so CI is never colour-only.
        let railColor: Color? = (indicatorStyle == .rail && cfg.secondary)
            ? HubberDesign.ciColor(for: draft.ci)
            : nil
        RowShell(density: density, isLast: isLast, railColor: railColor) {
            // CI indicator as the leading status column — same position/treatment as
            // OutgoingReviewRow so it reads consistently across tabs. Rail mode shows a
            // CI-coloured rail (a muted gray for drafts without checks); badge mode shows
            // the CIBadgeView (a gray dash for no-pipeline drafts; real status otherwise).
            if railColor == nil {
                CIBadgeView(ci: draft.ci, size: cfg.ci)
                    .alignmentGuide(.top) { $0[.top] + 1 }
            }

            VStack(alignment: .leading, spacing: cfg.secondary ? 3 : 0) {
                PRTitleLine(number: draft.number, title: draft.title)

                if cfg.secondary {
                    SecondaryLine {
                        Text(draft.repo)
                        RowDot()
                        // CI detail as the non-colour cue for the rail (drafts otherwise show no
                        // CI text); red when failing, mirroring OutgoingReviewRow.
                        Text(draft.ciDetail)
                            .foregroundStyle(
                                draft.ci == .failing
                                    ? HubberDesign.ciColor(for: draft.ci)
                                    : HubberDesign.text2
                            )
                        RowDot()
                        Text("\(draft.commits) commits")
                        RowDot()
                        Text("updated \(elapsedText(hours: draft.updatedAgoHours))")
                        if draft.additions > 0 || draft.deletions > 0 {
                            RowDot()
                            PRSizeView(additions: draft.additions, deletions: draft.deletions)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessibilityText.draftRow(
            number: draft.number, title: draft.title, repo: draft.repo,
            ci: draft.ci, commits: draft.commits,
            additions: draft.additions, deletions: draft.deletions
        ))
    }
}

// MARK: - SLOPillView (public for use in rows)

struct SLOPillView: View {
    let status: SLOStatus
    let text: String
    var helpText: String?

    var body: some View {
        let tokens = HubberDesign.sloTokens(for: status)
        HStack(spacing: 5) {
            // Non-color cue: dot shape + text label
            Circle()
                .fill(tokens.fg)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(text)
                .hubberFont(.sloPill)
                .monospacedDigit()
                .foregroundStyle(tokens.fg)
        }
        .padding(.leading, 7)
        .padding(.trailing, 8)
        .padding(.vertical, 2.5)
        .background(tokens.bg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(tokens.border, lineWidth: 0.5)
        }
        .help(helpText ?? text)
        .accessibilityLabel("Review \(AccessibilityText.sloPhrase(status)), \(text)")
    }
}

// MARK: - ReviewPillView (review axis — pairs with the CI rail)

/// Trailing pill summarising a PR's aggregate review state. Text-labelled (not colour-only),
/// so the review axis stays legible in grayscale and for colour-blind users even though the
/// leading rail is colour-only — the two channels degrade independently. See `ReviewVerdict`.
struct ReviewPillView: View {
    let verdict: ReviewVerdict

    var body: some View {
        let tokens = HubberDesign.reviewVerdictTokens(for: verdict)
        HStack(spacing: 5) {
            // Non-color cue: dot shape + the word, so it survives grayscale.
            Circle()
                .fill(tokens.fg)
                .frame(width: 6, height: 6)

            Text(verdict.pillLabel)
                .hubberFont(.sloPill)
                .foregroundStyle(tokens.fg)
        }
        .padding(.leading, 7)
        .padding(.trailing, 8)
        .padding(.vertical, 2.5)
        .background(tokens.bg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(tokens.border, lineWidth: 0.5)
        }
        // Review state is spoken via the row's composed accessibility label.
        .accessibilityHidden(true)
    }
}

// MARK: - CIBadgeView (public for use in rows)

struct CIBadgeView: View {
    let ci: PullRequestCI
    let size: CGFloat

    var body: some View {
        let color = HubberDesign.ciColor(for: ci)
        ZStack {
            switch ci {
            case .passing:
                Circle().fill(color)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.50, weight: .bold))
                    .foregroundStyle(.white)
            case .failing:
                Circle().fill(color)
                Image(systemName: "xmark")
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(.white)
            case .running:
                ProgressView()
                    .controlSize(.small)
                    .tint(color)
                    .scaleEffect(size / 16)
            case .pending:
                Circle().stroke(color, lineWidth: 1.5)
                Image(systemName: "clock")
                    .font(.system(size: size * 0.44))
                    .foregroundStyle(color)
            case .noChecks:
                Circle().stroke(color, lineWidth: 1.5)
                Image(systemName: "minus")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(AccessibilityText.ciPhrase(ci))
    }
}

// MARK: - ReviewerStack

struct ReviewerStack: View {
    let reviewers: [Reviewer]
    let size: CGFloat
    var maxAvatars = 3

    var body: some View {
        HStack(spacing: -7) {
            ForEach(reviewers.prefix(maxAvatars)) { reviewer in
                AvatarView(user: reviewer.user, size: size, reviewerState: reviewer.state)
                    .zIndex(Double(maxAvatars - (reviewers.firstIndex(where: { $0.id == reviewer.id }) ?? 0)))
            }
        }
    }
}
