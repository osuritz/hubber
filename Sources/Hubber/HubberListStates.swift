import SwiftUI

// MARK: - AllClearState (per rows.jsx EmptyState)

/// "All clear" — no reviews waiting. Green check icon + encouraging copy.
struct AllClearState: View {
    var title = "All clear"
    var message = "No reviews waiting on you. Enjoy the deep work."

    var body: some View {
        VStack(spacing: 10) {
            // Green check circle (non-color cue: checkmark icon + green fill)
            ZStack {
                Circle()
                    .fill(HubberDesign.sloGreen.bg)
                    .overlay {
                        Circle().stroke(HubberDesign.sloGreen.border, lineWidth: 0.5)
                    }
                    .frame(width: 54, height: 54)

                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(HubberDesign.sloGreen.fg)
            }

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HubberDesign.text)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(HubberDesign.text2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 36)
        .padding(.vertical, 40)
    }
}

// MARK: - ErrorState (per rows.jsx ErrorState)

/// Error banner shown above rows or in place of them (no data + error).
struct ErrorState: View {
    var message: String
    var lastUpdated: String?
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            // Error circle icon (non-color cue: icon shape + "error" text)
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(HubberDesign.error)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HubberDesign.text)

                if let lastUpdated {
                    Text(lastUpdated)
                        .font(HubberType.secondary)
                        .foregroundStyle(HubberDesign.text2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onRetry {
                Button("Retry", action: onRetry)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HubberDesign.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(HubberDesign.sloRed.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(HubberDesign.sloRed.border, lineWidth: 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - LoadingState (skeleton rows per rows.jsx SkeletonRow)

struct LoadingState: View {
    var count = 5

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                SkeletonRow(isLast: i == count - 1)
            }
        }
    }
}

// MARK: - SkeletonRow

struct SkeletonRow: View {
    var isLast = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            // Avatar placeholder
            Circle()
                .fill(shimmerColor)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 7) {
                // Title bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 9)
                    .padding(.trailing, 60)

                // Secondary bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerColor)
                    .frame(height: 8)
                    .padding(.trailing, 100)
            }
            .padding(.top, 3)

            // Pill placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(shimmerColor)
                .frame(width: 58, height: 16)
                .padding(.top, 3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9.5)
        .overlay(alignment: .bottom) {
            if !isLast {
                HubberDesign.sep.frame(height: 0.5)
            }
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var shimmerColor: Color {
        colorScheme == .dark
            ? .white.opacity(0.08)
            : .black.opacity(0.05)
    }
}

// MARK: - EmptyDraftsState

/// Empty state for the Drafts tab — "No drafts" with a generic icon.
struct EmptyDraftsState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.badge.clock")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(HubberDesign.text3)

            Text("No draft pull requests")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HubberDesign.text)

            Text("Draft PRs you create will appear here.")
                .font(.system(size: 12))
                .foregroundStyle(HubberDesign.text2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 36)
        .padding(.vertical, 40)
    }
}

// MARK: - EmptyOutgoingState

/// Empty state for the Outgoing tab.
struct EmptyOutgoingState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.up.doc")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(HubberDesign.text3)

            Text("No open pull requests")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(HubberDesign.text)

            Text("Pull requests you've opened will appear here.")
                .font(.system(size: 12))
                .foregroundStyle(HubberDesign.text2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 36)
        .padding(.vertical, 40)
    }
}

// MARK: - ReauthBanner

/// Session-expired banner shown in-popover (not a full screen takeover).
struct ReauthBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            // Lock icon (non-color cue: lock shape + "expired" text)
            ZStack {
                Circle()
                    .fill(HubberDesign.sloAmber.bg)
                    .overlay {
                        Circle().stroke(HubberDesign.sloAmber.border, lineWidth: 0.5)
                    }
                    .frame(width: 34, height: 34)

                Image(systemName: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(HubberDesign.sloAmber.fg)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Session expired")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(HubberDesign.text)

                Text("Sign in again to keep syncing")
                    .font(HubberType.secondary)
                    .foregroundStyle(HubberDesign.text2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
