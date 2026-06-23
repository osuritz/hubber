import SwiftUI
import WidgetKit
import HubberKit

// Throwaway VALIDATION host: an AUTHORIZED (xcodebuild-provisioned) non-sandboxed app that
// writes a sample WidgetSnapshot to the shared App Group store on launch, then reloads the
// widget. If the embedded sandboxed widget renders these rows, authorized cross-process
// sharing is confirmed (Codex's root-cause fix).

@main
struct HubberHostStubApp: App {
    init() {
        let snapshot = WidgetSnapshot(
            meta: SnapshotMeta(lastUpdated: Date(), isSignedIn: true),
            connections: [ConnectionSummary(id: "github:olivier", displayName: "GitHub · @olivier")],
            incoming: [
                PRRowSnapshot(
                    id: "1", connectionID: "github:olivier", repo: "acme/api", number: 412,
                    title: "AUTHORIZED host round-trip works", url: URL(string: "https://example.com/1"),
                    ci: .passing, review: .pending, ageHours: 3, additions: 120, deletions: 8,
                    files: 5, needsAttention: true
                ),
                PRRowSnapshot(
                    id: "2", connectionID: "github:olivier", repo: "acme/web", number: 77,
                    title: "Second sample row", url: URL(string: "https://example.com/2"),
                    ci: .failing, review: .changesRequested, ageHours: 26, additions: 5, deletions: 2,
                    files: 1, needsAttention: true
                ),
            ],
            outgoing: [],
            drafts: []
        )
        let store = WidgetSnapshotStore()
        do {
            try store?.write(snapshot)
            NSLog("[HostStub] wrote snapshot; store=%@", store == nil ? "nil(suite-unavailable)" : "present")
        } catch {
            NSLog("[HostStub] write FAILED: %@", String(describing: error))
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    var body: some Scene {
        WindowGroup {
            Text("Hubber host stub — wrote a sample snapshot to the App Group. Check the widget.")
                .padding()
                .frame(width: 380, height: 120)
        }
    }
}
