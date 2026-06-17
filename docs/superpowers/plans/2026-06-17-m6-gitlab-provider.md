# M6 — GitLab Provider Implementation Plan (#60)

> Branch: `feat/m6-gitlab-provider` (off `main`). TDD task-by-task; commit per green task. Gate locally with **`make ci`** (build + `swift test` + swiftlint + `swiftformat --lint`) — the `.githooks/pre-push` hook runs it on push (CI is manual-only). One PR → main.

**Goal:** A `GitLabProvider` conforming to `CodeHostProvider`, mapping GitLab **Merge Requests** to Hubber's canonical models, so a GitLab account coexists with GitHub accounts on the existing multi-connection rails (aggregation, scheduling, notifications) shipped in #86. Validated by the QA plan's Area-K (MC-GL-01..09) + Area-L (MC-MIX-01..04) stories — all fixture/`MockURLProtocol`-based, **no real account needed** for the unit suite.

**Issues:** Closes #60. Refs #80. Builds on the `CodeHostProvider` protocol + `CodeHostAuthServicing` seam from #81/#86.

---

## Coordinator decisions (do not relitigate)

1. **GraphQL, not REST.** GitLab's GraphQL endpoint (`/api/graphql`, `Authorization: Bearer <PAT>`) returns MR + reviewers + approvals + diff stats + discussion counts + head pipeline in ONE query — mirroring `GitHubProvider`. REST would need per-MR `/approvals`, `/discussions`, and pipeline calls (N+1). Reuse the same dict-parsing + transport shape as `GitHubProvider.graphQL(...)`.
2. **PAT credential (spike).** `CodeHostProvider.fetch*` already takes `accessToken: String`; pass a GitLab **PAT** (scopes: `read_api`). OAuth device-flow and the GitLab credential path on `CodeHostAuthServicing` are a later refinement. `viewerLogin` is unused by GitLab (queries hang off `currentUser`); keep the param for protocol conformance.
3. **`baseURL`-parameterized from day one.** `GitLabProvider(baseURL: URL = https://gitlab.com)` so gitlab.com and self-managed (`https://gitlab.intra.acme.com`) share one class — GraphQL at `baseURL/api/graphql` (MC-GL-09). (This is the same dimension #82 adds to GitHub; GitLab gets it for free.)
4. **Scope boundary = the provider + its tests.** #60 delivers `GitLabProvider` + fixture unit tests + the cross-provider aggregation proof. **Adding a GitLab connection in the UI (provider switcher, PAT entry) is #61** — out of scope here. Cross-provider aggregation (#MC-MIX) already works because `ConnectionAggregator`/notifications are provider-agnostic; we only add tests.
5. **Free-tier reality.** Approval *rules* are Premium-only; on free GitLab.com `approvalsRequired == 0`. The parser must not crash on absent approval data and must default `requiredApprovals` to 0 (MC-GL-04). Reviewers, pipelines, and discussions are available on Free.
6. **Reuse `GitHubUser`** as the shared user view-model (it's the generic author/reviewer type despite the name; do **not** rename in this PR). SLO clock for an incoming MR = its `createdAt` (GitLab has no clean per-reviewer "requested at" in GraphQL; revisit if needed).

---

## Field mapping (GitLab MR → Hubber models — the authoritative contract)

**Pipeline status → `PullRequestCI`** (`SUCCESS`→`.passing`, `FAILED`→`.failing`, `RUNNING`→`.running`, everything else incl. `CREATED`/`PENDING`/`MANUAL`/`SCHEDULED`/`CANCELED`/`SKIPPED`/`null`→`.pending`). (MC-GL-03)

**Reviewer `reviewState` → `ReviewerState`** (`APPROVED`→`.approved`, `REQUESTED_CHANGES`→`.changesRequested`, `REVIEWED`→`.commented`, `UNREVIEWED`/`UNAPPROVED`/absent→`.pending`). (MC-GL-07)

| Model | Field | GitLab GraphQL source |
|---|---|---|
| `IncomingReview` | `id` | MR `id` (global gid) or `"gl-mr-\(iid)"` — stable + provider-prefixed |
| | `repo` | `project.fullPath` (`"namespace/project"`) |
| | `number` | `iid` |
| | `title` / `url` | `title` / `webUrl` |
| | `author` | `GitHubUser(login: author.username, …, avatarURL: author.avatarUrl)` |
| | `sloClockStart` | `createdAt` (ISO8601) |
| | `additions`/`deletions`/`files` | `diffStatsSummary.additions`/`.deletions`/`.fileCount` |
| `OutgoingReview` | `ci`/`ciDetail` | `headPipeline.status` (mapped) / raw status string (or "no pipeline") |
| | `unresolved` | `resolvableDiscussionsCount - resolvedDiscussionsCount` (≥0) (MC-GL-06) |
| | `requiredApprovals` | `approvalsRequired ?? 0` (MC-GL-04/05) |
| | `approvals` | `approvalsRequired - approvalsLeft`, or `approvedBy.nodes.count` |
| | `reviewers` | `reviewers.nodes` → `Reviewer(user:, state: reviewState)` |
| | `mergeable` | `mergeStatusEnum == "CAN_BE_MERGED"` (or `detailedMergeStatus`) |
| | `updatedAgoHours` | from `updatedAt` |
| `DraftReview` | (same id/repo/number/title/url) | `authoredMergeRequests` where `draft == true` |
| | `ci`/`ciDetail` | `headPipeline.status` (mapped) |
| | `commits` | `commitCount` |
| | `updatedAt` | `updatedAt` |

**Queries** (`currentUser` hangs the lists off the token's user — no `viewerLogin` needed):
- Incoming: `currentUser { reviewRequestedMergeRequests(state: opened, first: 100) { nodes { …MRFields } } }`
- Outgoing + Drafts: `currentUser { authoredMergeRequests(state: opened, first: 100) { nodes { …MRFields, draft, commitCount, reviewers{…}, approvalsRequired, approvalsLeft, resolvableDiscussionsCount, resolvedDiscussionsCount, mergeStatusEnum } } }` → split client-side on `draft`.

> **Implementer: verify the exact GraphQL field names/availability against GitLab's live schema via introspection** (`reviewState` path is `reviewers.nodes[].mergeRequestInteraction.reviewState`; `approvalsRequired`/`resolvableDiscussionsCount` exist on `MergeRequest`; some approval fields are Premium-gated → must degrade to 0, not error). The fixture tests pin the query↔fixture contract; the live-schema accuracy is validated at the E2E pass with a real PAT.

---

## File Map

| Action | Path | Responsibility |
|---|---|---|
| Create | `Sources/Hubber/GitLab/GitLabProvider.swift` | `CodeHostProvider` conformance; GraphQL transport (`baseURL`); incoming/outgoing/drafts parsing; CI + reviewer-state mappers |
| Create | `Sources/Hubber/GitLab/GitLabModels.swift` *(if needed)* | small mapping enums/helpers if they don't fit cleanly in the provider |
| Create | `Tests/HubberTests/GitLabProviderTests.swift` | MC-GL-01..09 fixture tests (`MockURLProtocol`, host/auth assertions) |
| Create | `Tests/HubberTests/Fixtures/` (or inline strings) | GitLab MR GraphQL response fixtures (free-tier no-approval-rules, Premium, failing pipeline, unresolved discussions, reviewer states) |
| Create | `Tests/HubberTests/CrossProviderMixingTests.swift` | MC-MIX-01..04: GitHub + GitLab stub providers aggregate via `ConnectionAggregator`; SLO/badge/notification baselines independent |

---

## Tasks

### Task 1 — `GitLabProvider` skeleton + GraphQL transport + conformance (TDD)
Create `GitLabProvider: CodeHostProvider` with `init(baseURL: URL = URL(string: "https://gitlab.com")!, session: URLSession = .shared)` and a `graphQL(query:variables:accessToken:)` mirroring `GitHubProvider` (POST `baseURL/api/graphql`, `Authorization: Bearer`, `Content-Type: application/json`; 401→`badCredentials`; 429→`rateLimited`; partial `data`+`errors[]` → return `data`). Stub the three `fetch*` to `[]`. **Tests:** MC-GL-01 — compile-time conformance assertion (`let p: any CodeHostProvider = GitLabProvider()`); a transport test asserting the request URL is `https://gitlab.com/api/graphql` and the `Authorization` header carries the PAT (`MockURLProtocol`). Commit: `feat(gitlab): GitLabProvider skeleton + GraphQL transport (baseURL) (#60)`.

### Task 2 — Incoming reviews + CI mapper (TDD)
Implement `fetchIncomingReviews` via `currentUser.reviewRequestedMergeRequests` → `IncomingReview` per the mapping table; add the `PullRequestCI` mapper. **Tests:** MC-GL-02 (fixture with 2 reviewer MRs → correct `id/repo/number/title/url/sloClockStart/additions/deletions/files`), MC-GL-03 (parameterized pipeline-status → CI mapping incl. unknown→`.pending`). Commit: `feat(gitlab): map merge requests to IncomingReview + pipeline CI mapping (#60)`.

### Task 3 — Outgoing PRs: approvals, discussions, reviewer states (TDD)
Implement `fetchOutgoingPullRequests` via `authoredMergeRequests` (`draft == false`) → `OutgoingReview`. **Tests:** MC-GL-04 (free-tier fixture, no `approval_rules` → `requiredApprovals == 0`, no crash), MC-GL-05 (Premium fixture `approvalsRequired: 2` → `requiredApprovals == 2`), MC-GL-06 (3 unresolved discussions → `unresolved == 3`), MC-GL-07 (reviewers APPROVED/REQUESTED_CHANGES/UNREVIEWED → `.approved`/`.changesRequested`/`.pending`). Commit: `feat(gitlab): map outgoing MRs — approvals, unresolved discussions, reviewer states (#60)`.

### Task 4 — Draft MRs (TDD)
Implement `fetchDraftPullRequests` via `authoredMergeRequests` (`draft == true`) → `DraftReview` (CI from head pipeline, `commits` from `commitCount`). **Tests:** fixture with mixed draft/non-draft authored MRs → only drafts returned, correct fields. Commit: `feat(gitlab): map draft merge requests to DraftReview (#60)`.

### Task 5 — Host routing + token isolation (TDD)
Confirm `baseURL` drives all requests. **Tests:** MC-GL-09 (`GitLabProvider(baseURL: "https://gitlab.intra.acme.com")` → request host is `gitlab.intra.acme.com`), MC-GL-08 (a `GitLabProvider` for `gitlab.com` and a GHES-style `GitHubProvider` in the same test → each token appears only in requests to its own host, asserted via `MockURLProtocol.lastRequest` per host — no cross-host credential leakage). Commit: `feat(gitlab): per-host base URL routing + token isolation (#60)`.

### Task 6 — Cross-provider mixing (TDD)
Prove a GitHub provider and a GitLab provider aggregate cleanly. **Tests (`CrossProviderMixingTests`):** MC-MIX-01 (2 GitHub incoming + 1 GitLab incoming → `ConnectionAggregator.aggregate` yields 3, sorted by `sloClockStart`), MC-MIX-02 (SLO independence — a 6h-old GitHub item past SLO makes `hasUrgentSLO` true regardless of a fresh GitLab item), MC-MIX-03 (per-connection notification baselines: a new GitLab MR fires one `newReview`, GitHub baseline untouched), MC-MIX-04 (badge attention aggregates a GitHub incoming + a GitLab failing-CI outgoing → count 2). These exercise existing provider-agnostic code with GitLab-shaped data. Commit: `test(m6): cross-provider GitHub+GitLab aggregation/SLO/notifications/badge (#60)`.

---

## Acceptance (whole PR)
- `make ci` green (build + `swift test` + swiftlint + `swiftformat --lint`); existing suite unaffected.
- MC-GL-01..09 + MC-MIX-01..04 covered by passing fixture tests; `GitLabProvider` satisfies all three `CodeHostProvider` methods; free-tier (0 approvals) and Premium paths both handled; no cross-host token leakage.
- Open PR → main with `Closes #60`, `Refs #80`; locally-green via the pre-push hook (CI manual-only).
- **Deferred (not this PR):** adding a GitLab connection in the UI + PAT entry (#61); E2E pass against a real free GitLab.com account + PAT (needs the account).

## Self-Review Checklist
- [ ] `GitLabProvider(baseURL:)` — gitlab.com default; all requests go to `baseURL/api/graphql`; PAT in `Authorization: Bearer`
- [ ] Incoming = `reviewRequestedMergeRequests`; outgoing/drafts split from `authoredMergeRequests` on `draft`
- [ ] CI + reviewer-state mappers match the table (unknown → `.pending`)
- [ ] Free-tier: `approvalsRequired` absent/0 → `requiredApprovals == 0`, no crash; unresolved = resolvable − resolved (≥0)
- [ ] No cross-host credential leakage (MC-GL-08); GraphQL field names sanity-checked vs live schema (note for E2E)
- [ ] Cross-provider aggregation/SLO/notification/badge tests green — no changes needed to `ConnectionAggregator`/notification code
