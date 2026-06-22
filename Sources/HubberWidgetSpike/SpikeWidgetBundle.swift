// HubberWidgetSpike — Phase 0 de-risking spike
// NOT production code. Throwaway. Delete after gate results are recorded.
//
// Exercises the EXACT combination that could fail outside Xcode:
//   • AppIntentConfiguration (not StaticConfiguration)
//   • A real AppEntity + EntityQuery backed by the App Group file
//   • TimelineProvider that reads spike.json from the App Group container
//
// Build: this target is NOT built by plain `swift build` (it's an executable
// that uses WidgetKit — not a library — so SPM won't link it as a widget extension
// without the appex wrapper). It is only built by `make widget-spike`.

import AppIntents
import SwiftUI
import WidgetKit

// MARK: — App Group constant (same for host probe + widget)

let spikeAppGroupID = "group.com.osuritz.hubber"
let spikeJSONFileName = "spike.json"

// MARK: — Shared model

struct SpikePayload: Codable {
    var value: String
    var writtenAt: Double // epoch seconds
}

// MARK: — App Group reader (used by EntityQuery + TimelineProvider)

enum SpikeStore {
    static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: spikeAppGroupID)
    }

    static func jsonURL() -> URL? {
        containerURL()?.appendingPathComponent(spikeJSONFileName)
    }

    static func read() -> SpikePayload? {
        guard let url = jsonURL() else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SpikePayload.self, from: data)
    }
}

// MARK: — AppEntity (connection stand-in)

struct SpikeConnectionEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Spike Connection")
    static let defaultQuery = SpikeConnectionQuery()

    var id: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
}

struct SpikeConnectionQuery: EntityQuery {
    func entities(for ids: [String]) async throws -> [SpikeConnectionEntity] {
        allConnections().filter { ids.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SpikeConnectionEntity] {
        allConnections()
    }

    private func allConnections() -> [SpikeConnectionEntity] {
        // Fixed list + one entry read from the App Group file (proves the EntityQuery
        // can read the container even when the host app is NOT running).
        var connections: [SpikeConnectionEntity] = [
            SpikeConnectionEntity(id: "github.com"),
            SpikeConnectionEntity(id: "gitlab.com"),
        ]
        // Attempt App Group read: if the file exists, surface its value as a synthetic entry.
        if let payload = SpikeStore.read() {
            connections.append(SpikeConnectionEntity(id: "live:\(payload.value)"))
        }
        return connections
    }
}

// MARK: — ConfigurationAppIntent

struct SpikeWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Spike Widget Configuration"
    static let description = IntentDescription("Phase-0 spike: proves AppIntentConfiguration works.")

    @Parameter(title: "Connection", default: nil)
    var connection: SpikeConnectionEntity?
}

// MARK: — TimelineProvider

struct SpikeEntry: TimelineEntry {
    let date: Date
    let sharedValue: String // read from App Group container
    let containerNonNil: Bool // Gate 1 signal
    let chosenConnection: String?
}

struct SpikeProvider: AppIntentTimelineProvider {
    typealias Intent = SpikeWidgetIntent
    typealias Entry = SpikeEntry

    func placeholder(in context: Context) -> SpikeEntry {
        SpikeEntry(date: .now, sharedValue: "—", containerNonNil: false, chosenConnection: nil)
    }

    func snapshot(for configuration: SpikeWidgetIntent, in context: Context) async -> SpikeEntry {
        makeEntry(for: configuration)
    }

    func timeline(for configuration: SpikeWidgetIntent, in context: Context) async -> Timeline<SpikeEntry> {
        let entry = makeEntry(for: configuration)
        // Refresh every 15 minutes.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: entry.date) ?? entry.date
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func makeEntry(for configuration: SpikeWidgetIntent) -> SpikeEntry {
        let payload = SpikeStore.read()
        return SpikeEntry(
            date: .now,
            sharedValue: payload?.value ?? "(no spike.json)",
            containerNonNil: SpikeStore.containerURL() != nil,
            chosenConnection: configuration.connection?.id
        )
    }
}

// MARK: — Widget view

struct SpikeWidgetView: View {
    var entry: SpikeEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hubber Spike")
                .font(.headline)
            Divider()
            Label {
                Text(entry.sharedValue)
                    .foregroundStyle(entry.containerNonNil ? .primary : .secondary)
            } icon: {
                Image(systemName: entry.containerNonNil ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(entry.containerNonNil ? .green : .red)
            }
            if let conn = entry.chosenConnection {
                Text("Connection: \(conn)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Gate 1: container \(entry.containerNonNil ? "NON-NIL ✓" : "NIL ✗")")
                .font(.caption2)
                .foregroundStyle(entry.containerNonNil ? .green : .red)
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

// MARK: — Widget definition

struct SpikeWidget: Widget {
    let kind = "com.osuritz.hubber.widget.spike"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SpikeWidgetIntent.self,
            provider: SpikeProvider()
        ) { entry in
            SpikeWidgetView(entry: entry)
        }
        .configurationDisplayName("Hubber Spike")
        .description("Phase-0 de-risking spike widget.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: — Widget bundle (@main)

@main
struct SpikeWidgetBundle: WidgetBundle {
    var body: some Widget {
        SpikeWidget()
    }
}
