# PR Widget Phase 1a: Data Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `HubberKit` SPM library target containing the widget's Codable DTOs, `WidgetSnapshotStore`, filter/sort/staleness helpers, and a live→DTO mapper in the `Hubber` target — with full unit tests — without changing any existing app behavior.

**Architecture:** `HubberKit` is a new `libraryTarget` in `Package.swift` (no SwiftUI, no external deps, macOS 14+). The existing `Hubber` executable gets a `HubberKit` dependency added, and a new `WidgetSnapshotMapping.swift` file that maps live `HubberData` models to `HubberKit` DTOs. The widget's shared Codable types, store, and helpers live exclusively in `HubberKit`; the mapper sits in `Hubber` because it references the live model types. Nothing is moved or deleted.

**Tech Stack:** Swift 6.0, SwiftPM, XCTest (matching the repo — all existing tests use XCTest), no new external packages.

## Global Constraints

- Swift version: 6.0 (Package.swift `swift-tools-version: 6.0`)
- Platform: macOS 14+ (`.macOS(.v14)`)
- NO SwiftUI imports anywhere in `HubberKit`
- NO external dependencies in `HubberKit`
- ALL types in `HubberKit` must be `Codable` and `Sendable`
- Purely additive: do NOT move, rename, or delete any existing source file
- Do NOT touch `Sources/HubberWidgetSpike/` or `Sources/Hubber/Notifications/SnapshotStore.swift`
- App Group ID constant: `"group.com.osuritz.hubber"` — one place only
- Test framework: XCTest (not swift-testing — the repo uses XCTest throughout)
- `make ci` must pass: `swift build` + `swift test` + `swiftlint lint` + `swiftformat --lint`
- Line length: warning at 120, error at 160 (from `.swiftlint.yml`)
- Max file length: warning 800, error 1200 lines (from `.swiftlint.yml`)
- swiftformat indent: 4 spaces, `--allman false`, `--elseposition same-line`
- Commit trailers: NO `Co-Authored-By:` trailers (project rule)
- Changes must stay uncommitted for review

---

## File Map

### New files to create

| File | Responsibility |
|------|---------------|
| `Sources/HubberKit/WidgetSnapshot.swift` | `WidgetSnapshot`, `SnapshotMeta`, `ConnectionSummary`, `PRRowSnapshot`, `CIState`, `ReviewSummary`, `currentSchemaVersion` |
| `Sources/HubberKit/WidgetSnapshotStore.swift` | `WidgetSnapshotStore` — atomic JSON read/write via App Group container |
| `Sources/HubberKit/WidgetSnapshotHelpers.swift` | `needsAttentionOnly(_:)`, `PRSortOrder` enum, `sorted(_:by:)`, `SnapshotMeta.isStale(asOf:threshold:)` |
| `Sources/Hubber/WidgetSnapshotMapping.swift` | `WidgetSnapshot.from(...)` mapper using live `HubberData` types |
| `Tests/HubberKitTests/WidgetSnapshotCodableTests.swift` | Codable round-trip for all HubberKit types |
| `Tests/HubberKitTests/WidgetSnapshotStoreTests.swift` | Store write→read round-trip, nil/absent handling |
| `Tests/HubberKitTests/WidgetSnapshotHelpersTests.swift` | Filter, sort, staleness tests |
| `Tests/HubberTests/WidgetSnapshotMappingTests.swift` | Mapper tests: field-by-field + `needsAttention` cases |

### Existing files to modify

| File | Change |
|------|--------|
| `Package.swift` | Add `HubberKit` library target + product; add `HubberKit` dependency to `Hubber` executable; add `HubberKitTests` test target |

---

## Task 1: Add `HubberKit` library target to Package.swift

**Files:**
- Modify: `Package.swift`

**Interfaces:**
- Produces: `HubberKit` product importable by `Hubber` and by `HubberKitTests`

- [ ] **Step 1: Read the current Package.swift to understand exact structure**

```bash
cat Package.swift
```

Expected: See the current targets array with `Hubber`, `HubberWidgetSpike`, `HubberTests`.

- [ ] **Step 2: Add HubberKit library product, target, and test target to Package.swift**

In `Package.swift`, make these three changes:

**Change 1:** In the `products` array, add before the HubberWidgetSpike product:
```swift
.library(name: "HubberKit", targets: ["HubberKit"]),
```

**Change 2:** In the `targets` array, add a new library target after the closing bracket of the `HubberWidgetSpike` target:
```swift
.target(
    name: "HubberKit",
    path: "Sources/HubberKit"
),
```

**Change 3:** In the `Hubber` executableTarget's `dependencies` array, add:
```swift
"HubberKit",
```

**Change 4:** After the `HubberTests` testTarget, add:
```swift
.testTarget(
    name: "HubberKitTests",
    dependencies: ["HubberKit"],
    path: "Tests/HubberKitTests"
),
```

The final `Package.swift` targets array should look like:

```swift
targets: [
    .executableTarget(
        name: "Hubber",
        dependencies: [
            "HubberKit",
            .product(name: "TelemetryDeck", package: "SwiftSDK"),
            .product(name: "Sparkle", package: "Sparkle"),
        ],
        path: "Sources/Hubber",
        resources: [
            .process("Resources")
        ]
    ),
    .executableTarget(
        name: "HubberWidgetSpike",
        path: "Sources/HubberWidgetSpike",
        swiftSettings: [
            .unsafeFlags(["-framework", "WidgetKit", "-framework", "AppIntents", "-framework", "SwiftUI"],
                         .when(platforms: [.macOS]))
        ]
    ),
    .target(
        name: "HubberKit",
        path: "Sources/HubberKit"
    ),
    .testTarget(
        name: "HubberTests",
        dependencies: ["Hubber"],
        path: "Tests/HubberTests"
    ),
    .testTarget(
        name: "HubberKitTests",
        dependencies: ["HubberKit"],
        path: "Tests/HubberKitTests"
    ),
]
```

- [ ] **Step 3: Create the source directories**

```bash
mkdir -p /Users/oliviersuritz/dev/hubber/.claude/worktrees/widget/Sources/HubberKit
mkdir -p /Users/oliviersuritz/dev/hubber/.claude/worktrees/widget/Tests/HubberKitTests
```

- [ ] **Step 4: Verify Package.swift parses correctly**

```bash
cd /Users/oliviersuritz/dev/hubber/.claude/worktrees/widget && swift package dump-package 2>&1 | head -20
```

Expected: JSON output starting with `{`, no errors about missing targets.

---

## Task 2: Create `WidgetSnapshot.swift` with all DTOs and schema version

**Files:**
- Create: `Sources/HubberKit/WidgetSnapshot.swift`

**Interfaces:**
- Produces:
  - `public let currentSchemaVersion: Int = 1`
  - `public struct SnapshotMeta: Codable, Sendable` with `lastUpdated: Date`, `isSignedIn: Bool`
  - `public struct ConnectionSummary: Codable, Sendable` with `id: String`, `displayName: String`
  - `public enum CIState: String, Codable, Sendable` with cases `passing`, `failing`, `running`, `pending`, `noChecks`
  - `public enum ReviewSummary: String, Codable, Sendable` with cases `approved`, `changesRequested`, `commented`, `pending`, `none`
  - `public struct PRRowSnapshot: Codable, Sendable` — full field list below
  - `public struct WidgetSnapshot: Codable, Sendable` with `schemaVersion`, `meta`, `connections`, `incoming`, `outgoing`, `drafts`

- [ ] **Step 1: Write the failing Codable test first (in Task 3 below — skip ahead to verify understanding, come back)**

Actually write the source now since we need it to compile before the test.

- [ ] **Step 2: Create `Sources/HubberKit/WidgetSnapshot.swift`**

```swift
import Foundation

// MARK: - Schema version

public let currentSchemaVersion = 1

// MARK: - SnapshotMeta

public struct SnapshotMeta: Codable, Sendable, Equatable {
    public let lastUpdated: Date
    public let isSignedIn: Bool

    public init(lastUpdated: Date, isSignedIn: Bool) {
        self.lastUpdated = lastUpdated
        self.isSignedIn = isSignedIn
    }
}

// MARK: - ConnectionSummary

public struct ConnectionSummary: Codable, Sendable, Equatable {
    public let id: String
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

// MARK: - CIState

/// Maps `PullRequestCI` from the live app to a Codable DTO.
/// `.passing` → CI checks all green.
/// `.failing` → at least one check failed.
/// `.running` → checks in progress.
/// `.pending` → checks have not started yet.
/// `.noChecks` → PR has no CI checks configured.
public enum CIState: String, Codable, Sendable, Equatable {
    case passing
    case failing
    case running
    case pending
    case noChecks
}

// MARK: - ReviewSummary

/// Aggregate review verdict for a PR row, distilled to Codable DTO.
/// `.approved` → required approvals met.
/// `.changesRequested` → at least one reviewer blocked the PR.
/// `.commented` → reviewers engaged but no decision.
/// `.pending` → awaiting first reviewer action.
/// `.none` → no reviewers assigned.
public enum ReviewSummary: String, Codable, Sendable, Equatable {
    case approved
    case changesRequested
    case commented
    case pending
    case none
}

// MARK: - PRRowSnapshot

public struct PRRowSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let connectionID: String
    public let repo: String
    public let number: Int
    public let title: String
    public let url: URL?
    public let ci: CIState
    public let review: ReviewSummary
    public let ageHours: Double
    public let additions: Int
    public let deletions: Int
    public let files: Int
    public let needsAttention: Bool

    public init(
        id: String,
        connectionID: String,
        repo: String,
        number: Int,
        title: String,
        url: URL?,
        ci: CIState,
        review: ReviewSummary,
        ageHours: Double,
        additions: Int,
        deletions: Int,
        files: Int,
        needsAttention: Bool
    ) {
        self.id = id
        self.connectionID = connectionID
        self.repo = repo
        self.number = number
        self.title = title
        self.url = url
        self.ci = ci
        self.review = review
        self.ageHours = ageHours
        self.additions = additions
        self.deletions = deletions
        self.files = files
        self.needsAttention = needsAttention
    }
}

// MARK: - WidgetSnapshot

public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let meta: SnapshotMeta
    public let connections: [ConnectionSummary]
    public let incoming: [PRRowSnapshot]
    public let outgoing: [PRRowSnapshot]
    public let drafts: [PRRowSnapshot]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        meta: SnapshotMeta,
        connections: [ConnectionSummary],
        incoming: [PRRowSnapshot],
        outgoing: [PRRowSnapshot],
        drafts: [PRRowSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.meta = meta
        self.connections = connections
        self.incoming = incoming
        self.outgoing = outgoing
        self.drafts = drafts
    }
}
```

- [ ] **Step 3: Verify it compiles**

```bash
cd /Users/oliviersuritz/dev/hubber/.claude/worktrees/widget && swift build --target HubberKit 2>&1
```

Expected: `Build complete!` with no errors.

---

## Task 3: Create `WidgetSnapshotStore.swift`

**Files:**
- Create: `Sources/HubberKit/WidgetSnapshotStore.swift`

**Interfaces:**
- Consumes: `WidgetSnapshot` from Task 2, `currentSchemaVersion` from Task 2
- Produces:
  - `public let appGroupID = "group.com.osuritz.hubber"`
  - `public final class WidgetSnapshotStore: Sendable`
    - `public init(containerURL: URL)` — testable, uses injected base dir
    - `public init?()` — convenience, uses real App Group container (fails gracefully if nil)
    - `public func write(_ snapshot: WidgetSnapshot) throws`
    - `public func read() -> WidgetSnapshot?`

- [ ] **Step 1: Create `Sources/HubberKit/WidgetSnapshotStore.swift`**

```swift
import Foundation

// MARK: - App Group ID

public let appGroupID = "group.com.osuritz.hubber"

// MARK: - WidgetSnapshotStore

/// Atomic JSON read/write for the widget's shared snapshot.
///
/// Use the injected `init(containerURL:)` in unit tests to avoid the real App Group
/// container, which requires signing. Use `init?()` in the app and widget.
public final class WidgetSnapshotStore: Sendable {
    private let fileURL: URL

    /// Designated initialiser for testing: point at any writable directory.
    public init(containerURL: URL) {
        fileURL = containerURL.appendingPathComponent("snapshot.json")
    }

    /// Convenience initialiser backed by the real App Group container.
    /// Returns `nil` when the container is unavailable (unsigned build / wrong entitlements).
    public init?() {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return nil }
        fileURL = container.appendingPathComponent("snapshot.json")
    }

    // MARK: - Write

    /// Atomically writes the snapshot as JSON. Throws on encode or I/O failure.
    public func write(_ snapshot: WidgetSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
    }

    // MARK: - Read

    /// Returns the stored snapshot, or `nil` if absent, corrupt, or unreadable.
    /// Never throws — corrupt data is treated the same as absent.
    public func read() -> WidgetSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd /Users/oliviersuritz/dev/hubber/.claude/worktrees/widget && swift build --target HubberKit 2>&1
```

Expected: `Build complete!`

---

## Task 4: Create `WidgetSnapshotHelpers.swift` with filter, sort, and staleness

**Files:**
- Create: `Sources/HubberKit/WidgetSnapshotHelpers.swift`

**Interfaces:**
- Consumes: `PRRowSnapshot` and `SnapshotMeta` from Task 2
- Produces:
  - `public func needsAttentionOnly(_ rows: [PRRowSnapshot]) -> [PRRowSnapshot]`
  - `public enum PRSortOrder: String, Sendable, CaseIterable` with cases `urgency`, `recentlyUpdated`, `size`
  - `public func sorted(_ rows: [PRRowSnapshot], by order: PRSortOrder) -> [PRRowSnapshot]`
  - `extension SnapshotMeta { public func isStale(asOf: Date, threshold: TimeInterval) -> Bool }`

- [ ] **Step 1: Create `Sources/HubberKit/WidgetSnapshotHelpers.swift`**

```swift
import Foundation

// MARK: - Attention filter

/// Returns only rows where `needsAttention == true`. Pure, no side effects.
public func needsAttentionOnly(_ rows: [PRRowSnapshot]) -> [PRRowSnapshot] {
    rows.filter(\.needsAttention)
}

// MARK: - Sort order

public enum PRSortOrder: String, Sendable, CaseIterable, Equatable {
    /// Oldest by `ageHours` first — the PR that has been waiting longest sits at the top.
    case urgency
    /// Most-recently-updated first (smallest `ageHours`).
    case recentlyUpdated
    /// Largest diff (additions + deletions) first.
    case size
}

/// Returns `rows` sorted by `order`. Ties are broken by `id` for determinism.
public func sorted(_ rows: [PRRowSnapshot], by order: PRSortOrder) -> [PRRowSnapshot] {
    switch order {
    case .urgency:
        rows.sorted {
            $0.ageHours != $1.ageHours
                ? $0.ageHours > $1.ageHours
                : $0.id < $1.id
        }
    case .recentlyUpdated:
        rows.sorted {
            $0.ageHours != $1.ageHours
                ? $0.ageHours < $1.ageHours
                : $0.id < $1.id
        }
    case .size:
        rows.sorted {
            let lhs = $0.additions + $0.deletions
            let rhs = $1.additions + $1.deletions
            return lhs != rhs ? lhs > rhs : $0.id < $1.id
        }
    }
}

// MARK: - Staleness

extension SnapshotMeta {
    /// Returns `true` when more than `threshold` seconds have elapsed since `lastUpdated`.
    public func isStale(asOf now: Date = Date(), threshold: TimeInterval) -> Bool {
        now.timeIntervalSince(lastUpdated) > threshold
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd /Users/oliviersuritz/dev/hubber/.claude/worktrees/widget && swift build --target HubberKit 2>&1
```

Expected: `Build complete!`

---

## Task 5: Create `WidgetSnapshotMapping.swift` in the `Hubber` target

**Files:**
- Create: `Sources/Hubber/WidgetSnapshotMapping.swift`

**Interfaces:**
- Consumes: `IncomingReview`, `OutgoingReview`, `DraftReview`, `ConnectionID`, `PullRequestCI`, `ReviewVerdict` (from `Models.swift` and `ConnectionID.swift` in the `Hubber` target); `HubberKit` types from Tasks 2–4
- Produces:
  - `extension WidgetSnapshot { static func from(incoming:outgoing:drafts:connections:isSignedIn:lastUpdated:) -> WidgetSnapshot }`

**Key: `needsAttention` derivation**

The rule is taken verbatim from `Sources/Hubber/Core/AttentionState.swift` `attentionItems(data:)` and `Sources/Hubber/Core/TabBadgePresentation.swift`:

- **Incoming**: every `IncomingReview` needs attention (reviewing is the user's task).
- **Outgoing**: needs attention when `ci == .failing` OR `unresolved > 0`.
- **Draft**: needs attention when `ci == .failing`.

This is the same rule used by `TabBadgePresentation.counts(data:mode:.needsAttention)`.

**`ReviewSummary` mapping from `ReviewVerdict`:**

```
ReviewVerdict.approved         → ReviewSummary.approved
ReviewVerdict.changesRequested → ReviewSummary.changesRequested
ReviewVerdict.inReview         → ReviewSummary.commented
ReviewVerdict.awaitingReview   → ReviewSummary.pending
```

For `IncomingReview` (no verdict concept) → `ReviewSummary.none`.

**`CIState` mapping from `PullRequestCI`:**

```
PullRequestCI.passing  → CIState.passing
PullRequestCI.failing  → CIState.failing
PullRequestCI.running  → CIState.running
PullRequestCI.pending  → CIState.pending
PullRequestCI.noChecks → CIState.noChecks
```

- [ ] **Step 1: Create `Sources/Hubber/WidgetSnapshotMapping.swift`**

```swift
import Foundation
import HubberKit

// MARK: - Live model → DTO mapping

extension WidgetSnapshot {
    /// Maps the app's live `HubberData` per-connection arrays to a `WidgetSnapshot` DTO.
    ///
    /// `needsAttention` is computed with the same rule used by
    /// `AttentionState.attentionItems(data:)` and `TabBadgePresentation.counts(data:mode:.needsAttention)`:
    ///   - Incoming: every review needs attention (it is a pending request on the viewer).
    ///   - Outgoing: failing CI (`ci == .failing`) or unresolved threads (`unresolved > 0`).
    ///   - Draft:    failing CI only (`ci == .failing`).
    static func from(
        incoming: [IncomingReview],
        outgoing: [OutgoingReview],
        drafts: [DraftReview],
        connections: [(id: ConnectionID, displayName: String)],
        isSignedIn: Bool,
        lastUpdated: Date
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            meta: SnapshotMeta(lastUpdated: lastUpdated, isSignedIn: isSignedIn),
            connections: connections.map {
                ConnectionSummary(id: $0.id.description, displayName: $0.displayName)
            },
            incoming: incoming.map(mapIncoming),
            outgoing: outgoing.map(mapOutgoing),
            drafts: drafts.map(mapDraft)
        )
    }
}

// MARK: - Per-row mappers

private func mapIncoming(_ r: IncomingReview) -> PRRowSnapshot {
    PRRowSnapshot(
        id: r.id,
        connectionID: "",
        repo: r.repo,
        number: r.number,
        title: r.title,
        url: r.url,
        ci: .noChecks,
        review: .none,
        ageHours: r.assignedAgoHours,
        additions: r.additions,
        deletions: r.deletions,
        files: r.files,
        // Every incoming review needs attention — the viewer has been asked to review it.
        // Source: AttentionState.attentionItems iterates data.incoming unconditionally.
        needsAttention: true
    )
}

private func mapOutgoing(_ r: OutgoingReview) -> PRRowSnapshot {
    PRRowSnapshot(
        id: r.id,
        connectionID: "",
        repo: r.repo,
        number: r.number,
        title: r.title,
        url: r.url,
        ci: ciState(from: r.ci),
        review: reviewSummary(from: r.reviewVerdict),
        ageHours: r.updatedAgoHours,
        additions: r.additions,
        deletions: r.deletions,
        files: r.files,
        // Source: AttentionState.attentionItems: `if pr.ci == .failing || pr.unresolved > 0`
        // TabBadgePresentation.counts mode .needsAttention: same condition for .outgoing.
        needsAttention: r.ci == .failing || r.unresolved > 0
    )
}

private func mapDraft(_ r: DraftReview) -> PRRowSnapshot {
    PRRowSnapshot(
        id: r.id,
        connectionID: "",
        repo: r.repo,
        number: r.number,
        title: r.title,
        url: r.url,
        ci: ciState(from: r.ci),
        review: .none,
        ageHours: r.updatedAgoHours,
        additions: r.additions,
        deletions: r.deletions,
        files: r.files,
        // Source: TabBadgePresentation.counts mode .needsAttention for .drafts:
        // `data.drafts.count(where: { $0.ci == .failing })` — only failing CI triggers attention.
        needsAttention: r.ci == .failing
    )
}

// MARK: - Enum bridges

private func ciState(from ci: PullRequestCI) -> CIState {
    switch ci {
    case .passing: .passing
    case .failing: .failing
    case .running: .running
    case .pending: .pending
    case .noChecks: .noChecks
    }
}

private func reviewSummary(from verdict: ReviewVerdict) -> ReviewSummary {
    switch verdict {
    case .approved: .approved
    case .changesRequested: .changesRequested
    case .inReview: .commented
    case .awaitingReview: .pending
    }
}
```

- [ ] **Step 2: Verify the full build still compiles (both Hubber and HubberKit)**

```bash
cd /Users/oliviersuritz/dev/hubber/.claude/worktrees/widget && swift build 2>&1
```

Expected: `Build complete!` — no errors in either target.

**Note on `connectionID`:** The mapper above leaves `connectionID` as `""` on each row because the caller must supply it. The spec says the mapper signature takes `connections: [(id: ConnectionID, displayName: String)]` but the rows themselves need to know which connection they belong to. The live types (`IncomingReview`, `OutgoingReview`, `DraftReview`) do NOT currently carry a `connectionID` field — connection association happens at the `HubberStore` layer where per-connection `data` is aggregated. Phase 1a intentionally does not wire the mapper into `HubberStore`, so the `connectionID` is left as `""` for now. The mapper signature will be extended in Phase 1b when `HubberStore.refresh` calls it with per-connection data. The tests in Task 8 cover this limitation explicitly.

---

## Task 6: Write `Tests/HubberKitTests/WidgetSnapshotCodableTests.swift`

**Files:**
- Create: `Tests/HubberKitTests/WidgetSnapshotCodableTests.swift`

**Interfaces:**
- Consumes: `HubberKit` — `WidgetSnapshot`, `SnapshotMeta`, `ConnectionSummary`, `PRRowSnapshot`, `CIState`, `ReviewSummary`, `currentSchemaVersion`

- [ ] **Step 1: Create the test file**

```swift
import Foundation
import XCTest
@testable import HubberKit

final class WidgetSnapshotCodableTests: XCTestCase {

    // MARK: - Fixtures

    private let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func makeSnapshot(schemaVersion: Int = currentSchemaVersion) -> WidgetSnapshot {
        WidgetSnapshot(
            schemaVersion: schemaVersion,
            meta: SnapshotMeta(lastUpdated: fixedDate, isSignedIn: true),
            connections: [ConnectionSummary(id: "github:github.com:alice", displayName: "GitHub")],
            incoming: [
                PRRowSnapshot(
                    id: "pr-1",
                    connectionID: "github:github.com:alice",
                    repo: "acme/app",
                    number: 42,
                    title: "Fix the thing",
                    url: URL(string: "https://github.com/acme/app/pull/42"),
                    ci: .passing,
                    review: .approved,
                    ageHours: 2.5,
                    additions: 10,
                    deletions: 3,
                    files: 2,
                    needsAttention: true
                ),
            ],
            outgoing: [],
            drafts: []
        )
    }

    // MARK: - Round-trip

    func testCodableRoundTrip() throws {
        let original = makeSnapshot()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testSchemaVersionIsPreservedInRoundTrip() throws {
        let snapshot = makeSnapshot(schemaVersion: 99)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 99)
    }

    func testCurrentSchemaVersionIsOne() {
        XCTAssertEqual(currentSchemaVersion, 1)
    }

    // MARK: - CIState raw values

    func testCIStateRawValues() {
        XCTAssertEqual(CIState.passing.rawValue, "passing")
        XCTAssertEqual(CIState.failing.rawValue, "failing")
        XCTAssertEqual(CIState.running.rawValue, "running")
        XCTAssertEqual(CIState.pending.rawValue, "pending")
        XCTAssertEqual(CIState.noChecks.rawValue, "noChecks")
    }

    func testCIStateDecodesFromRawString() throws {
        let json = #"{"ci": "failing"}"#.data(using: .utf8)!
        struct Wrapper: Decodable { let ci: CIState }
        let decoded = try JSONDecoder().decode(Wrapper.self, from: json)
        XCTAssertEqual(decoded.ci, .failing)
    }

    // MARK: - ReviewSummary raw values

    func testReviewSummaryRawValues() {
        XCTAssertEqual(ReviewSummary.approved.rawValue, "approved")
        XCTAssertEqual(ReviewSummary.changesRequested.rawValue, "changesRequested")
        XCTAssertEqual(ReviewSummary.commented.rawValue, "commented")
        XCTAssertEqual(ReviewSummary.pending.rawValue, "pending")
        XCTAssertEqual(ReviewSummary.none.rawValue, "none")
    }

    // MARK: - Nil URL round-trips as absent

    func testNilURLRoundTrips() throws {
        let row = PRRowSnapshot(
            id: "pr-2",
            connectionID: "c",
            repo: "acme/api",
            number: 1,
            title: "Draft",
            url: nil,
            ci: .pending,
            review: .none,
            ageHours: 0,
            additions: 0,
            deletions: 0,
            files: 0,
            needsAttention: false
        )
        let snapshot = WidgetSnapshot(
            meta: SnapshotMeta(lastUpdated: fixedDate, isSignedIn: false),
            connections: [],
            incoming: [row],
            outgoing: [],
            drafts: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)
        XCTAssertNil(decoded.incoming.first?.url)
    }

    // MARK: - Signed-out meta

    func testSignedOutMetaRoundTrips() throws {
        let snapshot = WidgetSnapshot(
            meta: SnapshotMeta(lastUpdated: fixedDate, isSignedIn: false),
            connections: [],
            incoming: [],
            outgoing: [],
            drafts: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)
        XCTAssertFalse(decoded.meta.isSignedIn)
    }
}
```

- [ ] **Step 2: Run the tests to verify they pass**

```bash
cd /Users/oliviersuritz/dev/hubber/.claude/worktrees/widget && swift test --filter HubberKitTests.WidgetSnapshotCodableTests 2>&1
```

Expected: All tests pass with `Test Suite 'WidgetSnapshotCodableTests' passed`.

---

## Task 7: Write `Tests/HubberKitTests/WidgetSnapshotStoreTests.swift`

**Files:**
- Create: `Tests/HubberKitTests/WidgetSnapshotStoreTests.swift`

**Interfaces:**
- Consumes: `WidgetSnapshotStore`, `WidgetSnapshot`, `SnapshotMeta`, `currentSchemaVersion` from HubberKit

- [ ] **Step 1: Create the test file**

```swift
import Foundation
import XCTest
@testable import HubberKit

final class WidgetSnapshotStoreTests: XCTestCase {

    // MARK: - Setup

    private var tempDir: URL!
    private var sut: WidgetSnapshotStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotStoreTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = WidgetSnapshotStore(containerURL: tempDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func makeSnapshot(isSignedIn: Bool = true) -> WidgetSnapshot {
        WidgetSnapshot(
            meta: SnapshotMeta(lastUpdated: fixedDate, isSignedIn: isSignedIn),
            connections: [ConnectionSummary(id: "conn-1", displayName: "GitHub")],
            incoming: [
                PRRowSnapshot(
                    id: "pr-99",
                    connectionID: "conn-1",
                    repo: "acme/app",
                    number: 99,
                    title: "Test PR",
                    url: URL(string: "https://github.com/acme/app/pull/99"),
                    ci: .passing,
                    review: .pending,
                    ageHours: 1.5,
                    additions: 20,
                    deletions: 5,
                    files: 3,
                    needsAttention: true
                ),
            ],
            outgoing: [],
            drafts: []
        )
    }

    // MARK: - Read when absent → nil

    func testReadWhenAbsentReturnsNil() {
        XCTAssertNil(sut.read())
    }

    // MARK: - Write → Read round-trip

    func testWriteAndReadRoundTrip() throws {
        let snapshot = makeSnapshot()
        try sut.write(snapshot)
        let loaded = sut.read()
        XCTAssertEqual(loaded, snapshot)
    }

    func testWriteOverwritesPreviousSnapshot() throws {
        let first = makeSnapshot(isSignedIn: true)
        let second = makeSnapshot(isSignedIn: false)
        try sut.write(first)
        try sut.write(second)
        let loaded = sut.read()
        XCTAssertEqual(loaded?.meta.isSignedIn, false)
    }

    // MARK: - Corrupt file → nil (no crash)

    func testCorruptFileReturnsNil() throws {
        let corruptData = "not valid json at all {{{".data(using: .utf8)!
        let fileURL = tempDir.appendingPathComponent("snapshot.json")
        try corruptData.write(to: fileURL)
        XCTAssertNil(sut.read())
    }

    // MARK: - Schema version preserved

    func testSchemaVersionIsPreservedInStoreRoundTrip() throws {
        let snapshot = makeSnapshot()
        try sut.write(snapshot)
        let loaded = sut.read()
        XCTAssertEqual(loaded?.schemaVersion, currentSchemaVersion)
    }

    // MARK: - File is written atomically (file exists after write)

    func testFileExistsAfterWrite() throws {
        let snapshot = makeSnapshot()
        try sut.write(snapshot)
        let fileURL = tempDir.appendingPathComponent("snapshot.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - Two stores at different dirs are independent

    func testTwoStoresAtDifferentDirectoriesAreIndependent() throws {
        let tempDir2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotStoreTests-B-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir2, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir2) }

        let storeB = WidgetSnapshotStore(containerURL: tempDir2)
        let snapshotA = makeSnapshot(isSignedIn: true)
        let snapshotB = makeSnapshot(isSignedIn: false)
        try sut.write(snapshotA)
        try storeB.write(snapshotB)

        XCTAssertEqual(sut.read()?.meta.isSignedIn, true)
        XCTAssertEqual(storeB.read()?.meta.isSignedIn, false)
    }
}
```

- [ ] **Step 2: Run these tests**

```bash
cd /Users/oliviersuritz/dev/hubber/.claude/worktrees/widget && swift test --filter HubberKitTests.WidgetSnapshotStoreTests 2>&1
```

Expected: All tests pass.

---

## Task 8: Write `Tests/HubberKitTests/WidgetSnapshotHelpersTests.swift`

**Files:**
- Create: `Tests/HubberKitTests/WidgetSnapshotHelpersTests.swift`

**Interfaces:**
- Consumes: `PRRowSnapshot`, `PRSortOrder`, `SnapshotMeta`, `needsAttentionOnly`, `sorted(_:by:)`, `SnapshotMeta.isStale(asOf:threshold:)` from HubberKit

- [ ] **Step 1: Create the test file**

```swift
import Foundation
import XCTest
@testable import HubberKit

final class WidgetSnapshotHelpersTests: XCTestCase {

    // MARK: - Fixtures

    private func makeRow(
        id: String,
        needsAttention: Bool = false,
        ageHours: Double = 1,
        additions: Int = 0,
        deletions: Int = 0
    ) -> PRRowSnapshot {
        PRRowSnapshot(
            id: id,
            connectionID: "conn",
            repo: "acme/app",
            number: 1,
            title: "PR \(id)",
            url: nil,
            ci: .pending,
            review: .none,
            ageHours: ageHours,
            additions: additions,
            deletions: deletions,
            files: 0,
            needsAttention: needsAttention
        )
    }

    // MARK: - needsAttentionOnly

    func testNeedsAttentionOnlyFiltersCorrectly() {
        let rows = [
            makeRow(id: "a", needsAttention: true),
            makeRow(id: "b", needsAttention: false),
            makeRow(id: "c", needsAttention: true),
        ]
        let result = needsAttentionOnly(rows)
        XCTAssertEqual(result.map(\.id), ["a", "c"])
    }

    func testNeedsAttentionOnlyOnEmptyArrayReturnsEmpty() {
        XCTAssertEqual(needsAttentionOnly([]).count, 0)
    }

    func testNeedsAttentionOnlyWhenNoneNeedAttentionReturnsEmpty() {
        let rows = [makeRow(id: "a"), makeRow(id: "b")]
        XCTAssertEqual(needsAttentionOnly(rows).count, 0)
    }

    func testNeedsAttentionOnlyWhenAllNeedAttentionReturnsAll() {
        let rows = [makeRow(id: "a", needsAttention: true), makeRow(id: "b", needsAttention: true)]
        XCTAssertEqual(needsAttentionOnly(rows).count, 2)
    }

    // MARK: - sorted by urgency (oldest first)

    func testSortedUrgencyPutsOldestFirst() {
        let rows = [
            makeRow(id: "new", ageHours: 1),
            makeRow(id: "old", ageHours: 10),
            makeRow(id: "mid", ageHours: 5),
        ]
        let result = sorted(rows, by: .urgency)
        XCTAssertEqual(result.map(\.id), ["old", "mid", "new"])
    }

    func testSortedUrgencyTiesBreakByID() {
        let rows = [
            makeRow(id: "z", ageHours: 5),
            makeRow(id: "a", ageHours: 5),
        ]
        let result = sorted(rows, by: .urgency)
        XCTAssertEqual(result.map(\.id), ["a", "z"])
    }

    // MARK: - sorted by recentlyUpdated (smallest ageHours first)

    func testSortedRecentlyUpdatedPutsNewestFirst() {
        let rows = [
            makeRow(id: "old", ageHours: 10),
            makeRow(id: "new", ageHours: 0.5),
            makeRow(id: "mid", ageHours: 3),
        ]
        let result = sorted(rows, by: .recentlyUpdated)
        XCTAssertEqual(result.map(\.id), ["new", "mid", "old"])
    }

    func testSortedRecentlyUpdatedTiesBreakByID() {
        let rows = [
            makeRow(id: "z", ageHours: 2),
            makeRow(id: "a", ageHours: 2),
        ]
        let result = sorted(rows, by: .recentlyUpdated)
        XCTAssertEqual(result.map(\.id), ["a", "z"])
    }

    // MARK: - sorted by size (additions + deletions, largest first)

    func testSortedSizePutsLargestFirst() {
        let rows = [
            makeRow(id: "small", additions: 5, deletions: 2),
            makeRow(id: "large", additions: 100, deletions: 50),
            makeRow(id: "mid", additions: 20, deletions: 10),
        ]
        let result = sorted(rows, by: .size)
        XCTAssertEqual(result.map(\.id), ["large", "mid", "small"])
    }

    func testSortedSizeTiesBreakByID() {
        let rows = [
            makeRow(id: "z", additions: 10, deletions: 5),
            makeRow(id: "a", additions: 10, deletions: 5),
        ]
        let result = sorted(rows, by: .size)
        XCTAssertEqual(result.map(\.id), ["a", "z"])
    }

    func testSortedEmptyArrayReturnsEmpty() {
        XCTAssertEqual(sorted([], by: .urgency).count, 0)
        XCTAssertEqual(sorted([], by: .recentlyUpdated).count, 0)
        XCTAssertEqual(sorted([], by: .size).count, 0)
    }

    // MARK: - SnapshotMeta.isStale

    func testIsStaleReturnsTrueWhenThresholdExceeded() {
        let now = Date()
        let lastUpdated = now.addingTimeInterval(-3600) // 1 hour ago
        let meta = SnapshotMeta(lastUpdated: lastUpdated, isSignedIn: true)
        XCTAssertTrue(meta.isStale(asOf: now, threshold: 1800)) // 30 min threshold
    }

    func testIsStaleReturnsFalseWhenWithinThreshold() {
        let now = Date()
        let lastUpdated = now.addingTimeInterval(-600) // 10 min ago
        let meta = SnapshotMeta(lastUpdated: lastUpdated, isSignedIn: true)
        XCTAssertFalse(meta.isStale(asOf: now, threshold: 1800)) // 30 min threshold
    }

    func testIsStaleReturnsFalseWhenExactlyAtThreshold() {
        let now = Date()
        let lastUpdated = now.addingTimeInterval(-1800) // exactly 30 min ago
        let meta = SnapshotMeta(lastUpdated: lastUpdated, isSignedIn: true)
        // > threshold, not >=, so exactly at threshold is NOT stale
        XCTAssertFalse(meta.isStale(asOf: now, threshold: 1800))
    }

    func testIsStaleReturnsTrueOneSecondPastThreshold() {
        let now = Date()
        let lastUpdated = now.addingTimeInterval(-1801) // 30 min + 1 sec ago
        let meta = SnapshotMeta(lastUpdated: lastUpdated, isSignedIn: true)
        XCTAssertTrue(meta.isStale(asOf: now, threshold: 1800))
    }
}
```

- [ ] **Step 2: Run these tests**

```bash
cd /Users/oliviersuritz/dev/hubber/.claude/worktrees/widget && swift test --filter HubberKitTests.WidgetSnapshotHelpersTests 2>&1
```

Expected: All tests pass.

---

## Task 9: Write `Tests/HubberTests/WidgetSnapshotMappingTests.swift`

**Files:**
- Create: `Tests/HubberTests/WidgetSnapshotMappingTests.swift`

**Interfaces:**
- Consumes: `WidgetSnapshot.from(...)` from `WidgetSnapshotMapping.swift`; live `IncomingReview`, `OutgoingReview`, `DraftReview`, `PullRequestCI`, `Reviewer`, `ReviewerState`, `CodeHostUser`, `ConnectionID` from `Hubber` target; `CIState`, `ReviewSummary` from `HubberKit`

**Critical `needsAttention` cases to cover:**
1. Any incoming review → `needsAttention: true`
2. Outgoing with `ci == .failing` → `needsAttention: true`
3. Outgoing with `ci == .passing, unresolved == 0` → `needsAttention: false`
4. Outgoing with `ci == .passing, unresolved > 0` → `needsAttention: true`
5. Draft with `ci == .failing` → `needsAttention: true`
6. Draft with `ci == .passing` → `needsAttention: false`

- [ ] **Step 1: Create the test file**

```swift
import Foundation
import XCTest
import HubberKit
@testable import Hubber

@MainActor
final class WidgetSnapshotMappingTests: XCTestCase {

    // MARK: - Fixtures

    private let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let connectionID = ConnectionID.gitHubDotCom(login: "alice")

    private func makeConnections() -> [(id: ConnectionID, displayName: String)] {
        [(id: connectionID, displayName: "GitHub")]
    }

    private func makeIncoming(
        id: String = "pr-in-1",
        sloClockStart: Date? = nil
    ) -> IncomingReview {
        IncomingReview(
            id: id,
            repo: "acme/app",
            number: 10,
            title: "Review me",
            url: URL(string: "https://github.com/acme/app/pull/10"),
            author: CodeHostUser(login: "bob", initials: "BO", color: .gray),
            sloClockStart: sloClockStart ?? fixedDate,
            additions: 5,
            deletions: 2,
            files: 1
        )
    }

    private func makeOutgoing(
        id: String = "pr-out-1",
        ci: PullRequestCI = .passing,
        unresolved: Int = 0,
        reviewers: [Reviewer] = [],
        approvals: Int = 1,
        requiredApprovals: Int = 1
    ) -> OutgoingReview {
        OutgoingReview(
            id: id,
            repo: "acme/api",
            number: 20,
            title: "My PR",
            url: URL(string: "https://github.com/acme/api/pull/20"),
            ci: ci,
            ciDetail: ci.rawValue,
            unresolved: unresolved,
            approvals: approvals,
            requiredApprovals: requiredApprovals,
            reviewers: reviewers,
            updatedAgoHours: 3.0,
            mergeable: true,
            additions: 40,
            deletions: 10,
            files: 4
        )
    }

    private func makeDraft(
        id: String = "pr-draft-1",
        ci: PullRequestCI = .pending
    ) -> DraftReview {
        DraftReview(
            id: id,
            repo: "acme/new",
            number: 30,
            title: "WIP draft",
            url: URL(string: "https://github.com/acme/new/pull/30"),
            ci: ci,
            ciDetail: ci.rawValue,
            commits: 3,
            updatedAt: fixedDate,
            additions: 100,
            deletions: 20,
            files: 8
        )
    }

    // MARK: - Basic field mapping for incoming

    func testIncomingFieldsAreMappedCorrectly() {
        let review = makeIncoming()
        let snapshot = WidgetSnapshot.from(
            incoming: [review],
            outgoing: [],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        let row = try! XCTUnwrap(snapshot.incoming.first)
        XCTAssertEqual(row.id, "pr-in-1")
        XCTAssertEqual(row.repo, "acme/app")
        XCTAssertEqual(row.number, 10)
        XCTAssertEqual(row.title, "Review me")
        XCTAssertEqual(row.url, URL(string: "https://github.com/acme/app/pull/10"))
        XCTAssertEqual(row.additions, 5)
        XCTAssertEqual(row.deletions, 2)
        XCTAssertEqual(row.files, 1)
        XCTAssertEqual(row.ci, .noChecks)
        XCTAssertEqual(row.review, .none)
    }

    // MARK: - needsAttention: Incoming

    func testIncomingAlwaysNeedsAttention() {
        let snapshot = WidgetSnapshot.from(
            incoming: [makeIncoming()],
            outgoing: [],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertTrue(snapshot.incoming[0].needsAttention)
    }

    // MARK: - needsAttention: Outgoing

    func testOutgoingWithFailingCINeedsAttention() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [makeOutgoing(ci: .failing)],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertTrue(snapshot.outgoing[0].needsAttention)
    }

    func testOutgoingWithPassingCIAndNoUnresolvedDoesNotNeedAttention() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [makeOutgoing(ci: .passing, unresolved: 0)],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertFalse(snapshot.outgoing[0].needsAttention)
    }

    func testOutgoingWithUnresolvedThreadsNeedsAttention() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [makeOutgoing(ci: .passing, unresolved: 2)],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertTrue(snapshot.outgoing[0].needsAttention)
    }

    func testOutgoingWithRunningCIAndNoUnresolvedDoesNotNeedAttention() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [makeOutgoing(ci: .running, unresolved: 0)],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertFalse(snapshot.outgoing[0].needsAttention)
    }

    // MARK: - needsAttention: Draft

    func testDraftWithFailingCINeedsAttention() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [],
            drafts: [makeDraft(ci: .failing)],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertTrue(snapshot.drafts[0].needsAttention)
    }

    func testDraftWithPassingCIDoesNotNeedAttention() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [],
            drafts: [makeDraft(ci: .passing)],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertFalse(snapshot.drafts[0].needsAttention)
    }

    func testDraftWithPendingCIDoesNotNeedAttention() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [],
            drafts: [makeDraft(ci: .pending)],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertFalse(snapshot.drafts[0].needsAttention)
    }

    // MARK: - CIState mapping

    func testCIStateMappingAllCases() {
        let cases: [(PullRequestCI, CIState)] = [
            (.passing, .passing),
            (.failing, .failing),
            (.running, .running),
            (.pending, .pending),
            (.noChecks, .noChecks),
        ]
        for (liveCi, expectedDto) in cases {
            let snapshot = WidgetSnapshot.from(
                incoming: [],
                outgoing: [makeOutgoing(ci: liveCi)],
                drafts: [],
                connections: makeConnections(),
                isSignedIn: true,
                lastUpdated: fixedDate
            )
            XCTAssertEqual(snapshot.outgoing[0].ci, expectedDto, "Expected \(liveCi) → \(expectedDto)")
        }
    }

    // MARK: - ReviewSummary mapping from ReviewVerdict

    func testReviewSummaryApproved() {
        let outgoing = makeOutgoing(approvals: 1, requiredApprovals: 1, reviewers: [])
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [outgoing],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertEqual(snapshot.outgoing[0].review, .approved)
    }

    func testReviewSummaryChangesRequested() {
        let reviewer = Reviewer(
            user: CodeHostUser(login: "carol", initials: "CA", color: .blue),
            state: .changesRequested
        )
        let outgoing = makeOutgoing(approvals: 0, requiredApprovals: 1, reviewers: [reviewer])
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [outgoing],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertEqual(snapshot.outgoing[0].review, .changesRequested)
    }

    func testReviewSummaryPendingWhenNoReviewers() {
        // No reviewers, 0 approvals → awaitingReview → .pending
        let outgoing = makeOutgoing(approvals: 0, requiredApprovals: 1, reviewers: [])
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [outgoing],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertEqual(snapshot.outgoing[0].review, .pending)
    }

    func testReviewSummaryCommentedWhenInReview() {
        let reviewer = Reviewer(
            user: CodeHostUser(login: "dave", initials: "DA", color: .green),
            state: .commented
        )
        let outgoing = makeOutgoing(approvals: 0, requiredApprovals: 1, reviewers: [reviewer])
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [outgoing],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertEqual(snapshot.outgoing[0].review, .commented)
    }

    // MARK: - Meta and connection list

    func testMetaIsSignedInPreserved() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [],
            drafts: [],
            connections: [],
            isSignedIn: false,
            lastUpdated: fixedDate
        )
        XCTAssertFalse(snapshot.meta.isSignedIn)
    }

    func testConnectionListMapped() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [],
            drafts: [],
            connections: [(id: connectionID, displayName: "My GitHub")],
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertEqual(snapshot.connections.count, 1)
        XCTAssertEqual(snapshot.connections[0].displayName, "My GitHub")
        XCTAssertEqual(snapshot.connections[0].id, connectionID.description)
    }

    func testEmptyInputsProduceEmptyLists() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [],
            drafts: [],
            connections: [],
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertTrue(snapshot.incoming.isEmpty)
        XCTAssertTrue(snapshot.outgoing.isEmpty)
        XCTAssertTrue(snapshot.drafts.isEmpty)
    }

    // MARK: - Outgoing field mapping

    func testOutgoingFieldsAreMappedCorrectly() {
        let outgoing = makeOutgoing(ci: .passing, unresolved: 0)
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [outgoing],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        let row = try! XCTUnwrap(snapshot.outgoing.first)
        XCTAssertEqual(row.id, "pr-out-1")
        XCTAssertEqual(row.repo, "acme/api")
        XCTAssertEqual(row.number, 20)
        XCTAssertEqual(row.title, "My PR")
        XCTAssertEqual(row.additions, 40)
        XCTAssertEqual(row.deletions, 10)
        XCTAssertEqual(row.files, 4)
        XCTAssertEqual(row.ageHours, 3.0)
    }

    // MARK: - Draft field mapping

    func testDraftFieldsAreMappedCorrectly() {
        let draft = makeDraft(ci: .running)
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [],
            drafts: [draft],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        let row = try! XCTUnwrap(snapshot.drafts.first)
        XCTAssertEqual(row.id, "pr-draft-1")
        XCTAssertEqual(row.repo, "acme/new")
        XCTAssertEqual(row.number, 30)
        XCTAssertEqual(row.title, "WIP draft")
        XCTAssertEqual(row.ci, .running)
        XCTAssertEqual(row.additions, 100)
        XCTAssertEqual(row.deletions, 20)
        XCTAssertEqual(row.files, 8)
    }
}
```

- [ ] **Step 2: Run these tests**

```bash
cd /Users/oliviersuritz/dev/hubber/.claude/worktrees/widget && swift test --filter HubberTests.WidgetSnapshotMappingTests 2>&1
```

Expected: All tests pass.

---

## Task 10: Run `make format` then `make ci` and fix any lint/format issues

**Files:**
- Potentially modify: any new file that fails format/lint

- [ ] **Step 1: Run `make format` to auto-fix formatting**

```bash
cd /Users/oliviersuritz/dev/hubber/.claude/worktrees/widget && make format 2>&1
```

Expected: swiftformat rewrites any formatting deviations in the new files. No failures on this step (it auto-fixes).

- [ ] **Step 2: Run `make ci` and check for failures**

```bash
cd /Users/oliviersuritz/dev/hubber/.claude/worktrees/widget && make ci 2>&1
```

Expected: `Build complete!` then all tests pass then `Done linting! Found 0 violations.` then `No formatting issues found.`

- [ ] **Step 3: Fix any swiftlint violations**

If `make ci` reports lint errors, fix each one:

Common issues to anticipate:
- `force_unwrapping` violation for `try! XCTUnwrap(...)` → replace with `guard let row = snapshot.incoming.first else { XCTFail("no row"); return }`
- `force_try` violation for `try!` → use `try` in throwing test context or refactor to `XCTAssertNoThrow`
- Line length violations → break long lines at argument boundaries
- `multiline_arguments` → when a function call has 3+ args, put each on its own line

For `try! XCTUnwrap`, replace with:

```swift
// Instead of:
let row = try! XCTUnwrap(snapshot.incoming.first)

// Use:
let row = try XCTUnwrap(snapshot.incoming.first)
```

(The test methods must be marked `throws` for this to work — add `throws` to any method using `try XCTUnwrap`.)

- [ ] **Step 4: Run `make ci` again to confirm green**

```bash
cd /Users/oliviersuritz/dev/hubber/.claude/worktrees/widget && make ci 2>&1
```

Expected: Full green output ending with swiftformat finding no issues. Paste this output in the final delivery.

---

## Spec Coverage Self-Review

| Spec requirement | Covered by |
|-----------------|-----------|
| `HubberKit` library target, macOS 14, no external deps | Task 1 |
| `WidgetSnapshot` with `schemaVersion` | Task 2 |
| `SnapshotMeta { lastUpdated, isSignedIn }` | Task 2 |
| `ConnectionSummary { id, displayName }` | Task 2 |
| `PRRowSnapshot` with all fields | Task 2 |
| `CIState` enum mirroring `PullRequestCI` | Task 2 |
| `ReviewSummary` enum mirroring `ReviewVerdict` semantics | Task 2 |
| `currentSchemaVersion` constant | Task 2 |
| `WidgetSnapshotStore` with injected container URL | Task 3 |
| `WidgetSnapshotStore` convenience `init?()` via real App Group | Task 3 |
| App Group ID behind ONE constant | Task 3 |
| Atomic write, nil-on-absent/corrupt read | Task 3 |
| `needsAttentionOnly([PRRowSnapshot])` | Task 4 |
| `PRSortOrder` enum + `sorted(_:by:)` | Task 4 |
| `SnapshotMeta.isStale(asOf:threshold:)` | Task 4 |
| Mapper in `Hubber` target (NOT HubberKit) | Task 5 |
| `WidgetSnapshot.from(...)` signature | Task 5 |
| `needsAttention` using existing app rule (cited) | Task 5 |
| Existing `Hubber` executable depends on `HubberKit` | Task 1 |
| `HubberKit` product exported | Task 1 |
| No SwiftUI in HubberKit | All HubberKit tasks |
| All types `Codable + Sendable` | Task 2, 3, 4 |
| Do NOT touch `HubberWidgetSpike` or `SnapshotStore.swift` | Constraint (not touched) |
| Codable round-trip test incl. `schemaVersion` | Task 6 |
| Store write→read round-trip via temp dir | Task 7 |
| Nil/absent handling test | Task 7 |
| Filter + sort tests | Task 8 |
| Staleness tests | Task 8 |
| Mapper tests field-by-field incl. `needsAttention` cases | Task 9 |
| `make ci` green | Task 10 |
| Changes left UNCOMMITTED | Constraint — no commit steps in this plan |
