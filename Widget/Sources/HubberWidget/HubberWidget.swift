import WidgetKit
import SwiftUI
import HubberKit

// MARK: - Timeline Entry

struct PRWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

// MARK: - Timeline Provider

struct PRWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> PRWidgetEntry {
        PRWidgetEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PRWidgetEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PRWidgetEntry>) -> Void) {
        let entry = makeEntry()
        // Reload in 5 minutes as a backstop; the host triggers WidgetCenter reloads after writes.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry() -> PRWidgetEntry {
        PRWidgetEntry(date: Date(), snapshot: WidgetSnapshotStore()?.read())
    }
}

// MARK: - Row View

private struct PRRowView: View {
    let row: PRRowSnapshot

    var body: some View {
        HStack(spacing: 6) {
            // CI rail — colored leading dot
            Circle()
                .fill(ciColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                // repo #number
                Text("\(row.repo) #\(row.number)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                // title
                Text(row.title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Trailing: verdict pill or age
            trailingView
        }
    }

    // MARK: CI color

    private var ciColor: Color {
        switch row.ci {
        case .passing:   Color.green
        case .failing:   Color.red
        case .running:   Color.yellow
        case .pending:   Color.orange
        case .noChecks:  Color.secondary
        }
    }

    // MARK: Trailing

    @ViewBuilder
    private var trailingView: some View {
        HStack(spacing: 4) {
            if row.needsAttention {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            verdictPill
        }
    }

    @ViewBuilder
    private var verdictPill: some View {
        switch row.review {
        case .approved:
            Text("✓")
                .font(.caption2)
                .foregroundStyle(.green)
        case .changesRequested:
            Text("✗")
                .font(.caption2)
                .foregroundStyle(.red)
        case .commented:
            Text("●")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .pending, .none:
            Text(ageText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var ageText: String {
        let h = row.ageHours
        if h < 1 { return "<1h" }
        if h < 24 { return "\(Int(h))h" }
        return "\(Int(h / 24))d"
    }
}

// MARK: - Main Widget View

struct PRWidgetView: View {
    let entry: PRWidgetEntry
    @Environment(\.widgetFamily) private var family

    // Row count per family
    private var maxRows: Int {
        switch family {
        case .systemMedium:     return 3
        case .systemLarge:      return 6
        case .systemExtraLarge: return 12
        default:                return 6
        }
    }

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                snapshotView(snapshot)
            } else {
                placeholderView
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: Placeholder

    private var placeholderView: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerPlaceholder
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(height: 28)
            }
        }
        .padding(12)
    }

    private var headerPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.3))
            .frame(height: 18)
    }

    // MARK: Snapshot view

    @ViewBuilder
    private func snapshotView(_ snapshot: WidgetSnapshot) -> some View {
        if !snapshot.meta.isSignedIn {
            signedOutView
        } else {
            incomingView(snapshot)
        }
    }

    // MARK: Signed-out

    private var signedOutView: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open Hubber to sign in")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    // MARK: Incoming PR list

    private func incomingView(_ snapshot: WidgetSnapshot) -> some View {
        let allRows = sorted(snapshot.incoming, by: .urgency)
        let displayRows = Array(allRows.prefix(maxRows))
        let overflow = allRows.count - displayRows.count

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            header(count: allRows.count)
                .padding(.bottom, 6)

            if allRows.isEmpty {
                emptyView
            } else {
                // Rows
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(displayRows, id: \.id) { row in
                        if let url = row.url {
                            Link(destination: url) {
                                PRRowView(row: row)
                            }
                            .buttonStyle(.plain)
                        } else {
                            PRRowView(row: row)
                        }
                    }
                }

                // Overflow
                if overflow > 0 {
                    Text("+\(overflow) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)

            // Stale indicator
            if snapshot.meta.isStale(threshold: 60 * 30) {
                staleLine(lastUpdated: snapshot.meta.lastUpdated)
            }
        }
        .padding(12)
    }

    // MARK: Header

    private func header(count: Int) -> some View {
        Link(destination: URL(string: "hubber://open") ?? URL(string: "https://github.com")!) {
            HStack(spacing: 4) {
                Text("Reviews")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(count > 0 ? .primary : .secondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Empty

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.title3)
                .foregroundStyle(.green)
            Text("You're all caught up")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Stale indicator

    private func staleLine(lastUpdated: Date) -> some View {
        let mins = Int(Date().timeIntervalSince(lastUpdated) / 60)
        let label = mins < 60 ? "Updated \(mins)m ago" : "Updated \(mins / 60)h ago"
        return Text(label)
            .font(.caption2)
            .foregroundStyle(.quaternary)
    }
}

// MARK: - Widget Definition

struct HubberPRWidget: Widget {
    let kind: String = HubberWidgetKind.prList

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PRWidgetProvider()) { entry in
            PRWidgetView(entry: entry)
        }
        .configurationDisplayName("Hubber Reviews")
        .description("See pull requests waiting for your review.")
        .supportedFamilies([.systemMedium, .systemLarge, .systemExtraLarge])
    }
}

// MARK: - Widget Bundle

@main
struct HubberWidgetBundle: WidgetBundle {
    var body: some Widget {
        HubberPRWidget()
    }
}
