// Hubber — mock GitHub data.
// Times stored as ms offsets from "now" so SLO countdowns can tick live.

const MIN = 60 * 1000;
const HR = 60 * MIN;

// Signed-in user
const ACCOUNT = {
  login: "dani-ortega",
  name: "Dani Ortega",
  avatar: "DO",
  color: "#5b8def",
};

// Incoming review requests — sorted oldest-first (most urgent at top).
const INCOMING = [
  {
    id: "pr-9788", repo: "acme/mobile-ios", number: 9788,
    title: "Fix biometric prompt race on cold launch",
    author: { login: "priyanka", avatar: "PV", color: "#e8a13a" },
    assignedAgo: 5.2 * HR, // RED — overdue
    additions: 54, deletions: 29, files: 3, teamRequest: false,
  },
  {
    id: "pr-9805", repo: "acme/infra", number: 9805,
    title: "Bump Postgres to 16.4 + reindex migration",
    author: { login: "kenji", avatar: "KS", color: "#d6699a" },
    assignedAgo: 3.7 * HR, // amber, near red
    additions: 86, deletions: 41, files: 4, teamRequest: true,
  },
  {
    id: "pr-9817", repo: "acme/web", number: 9817,
    title: "Switch checkout flow to server components",
    author: { login: "tobi-l", avatar: "TL", color: "#5fb98a" },
    assignedAgo: 2.3 * HR, // amber
    additions: 612, deletions: 188, files: 24, teamRequest: false,
  },
  {
    id: "pr-9776", repo: "acme/design-system", number: 9776,
    title: "Tokens: replace hex with semantic refs in Button",
    author: { login: "ines", avatar: "IF", color: "#c98ad6" },
    assignedAgo: 1.1 * HR, // green
    additions: 318, deletions: 290, files: 12, teamRequest: false,
  },
  {
    id: "pr-9821", repo: "acme/payments-api", number: 9821,
    title: "Idempotency keys for refund retries",
    author: { login: "marisol", avatar: "MR", color: "#8a8fe0" },
    assignedAgo: 0.4 * HR, // fresh green
    additions: 142, deletions: 38, files: 7, teamRequest: false,
  },
];

// Authored PRs that need attention.
const OUTGOING = [
  {
    id: "pr-9826", repo: "acme/web", number: 9826,
    title: "Search: debounce typeahead + cancel stale fetches",
    ci: "failing", ciDetail: "9/11 checks passing", unresolved: 4,
    reviewers: [
      { login: "tobi-l", avatar: "TL", color: "#5fb98a", state: "changes_requested" },
      { login: "ines", avatar: "IF", color: "#c98ad6", state: "pending" },
    ],
    updatedAgo: 1.6 * HR, signal: true,
  },
  {
    id: "pr-9802", repo: "acme/cli", number: 9802,
    title: "Add `env diff` subcommand",
    ci: "passing", ciDetail: "9/9 checks passing", unresolved: 2,
    reviewers: [
      { login: "marisol", avatar: "MR", color: "#8a8fe0", state: "commented" },
    ],
    updatedAgo: 4.2 * HR, signal: true,
  },
  {
    id: "pr-9819", repo: "acme/infra", number: 9819,
    title: "Terraform: split staging VPC modules",
    ci: "running", ciDetail: "8/14 checks running", unresolved: 0,
    reviewers: [
      { login: "kenji", avatar: "KS", color: "#d6699a", state: "approved" },
      { login: "priyanka", avatar: "PV", color: "#e8a13a", state: "pending" },
    ],
    updatedAgo: 0.1 * HR, signal: false,
  },
  {
    id: "pr-9830", repo: "acme/payments-api", number: 9830,
    title: "Webhook signature rotation playbook",
    ci: "passing", ciDetail: "12/12 checks passing", unresolved: 0,
    reviewers: [
      { login: "marisol", avatar: "MR", color: "#8a8fe0", state: "approved" },
      { login: "kenji", avatar: "KS", color: "#d6699a", state: "approved" },
      { login: "tobi-l", avatar: "TL", color: "#5fb98a", state: "approved" },
    ],
    updatedAgo: 0.3 * HR, signal: false,
  },
];

// In-progress drafts, not ready for review.
const DRAFTS = [
  {
    id: "pr-9835", repo: "acme/payments-api", number: 9835,
    title: "Spike: ledger double-entry rewrite",
    ci: "running", ciDetail: "Running", commits: 6, updatedAgo: 0.5 * HR,
  },
  {
    id: "pr-9831", repo: "acme/web", number: 9831,
    title: "Experiment: streaming cart updates over SSE",
    ci: "passing", ciDetail: "Passing", commits: 14, updatedAgo: 8 * HR,
  },
  {
    id: "pr-9812", repo: "acme/design-system", number: 9812,
    title: "RFC: motion tokens",
    ci: "failing", ciDetail: "1 failing", commits: 3, updatedAgo: 26 * HR,
  },
];

// Developer log — last entries shown in Settings › Developer.
const DEV_LOG = [
  { t: "09:41:48", msg: "Refresh complete · 5 incoming, 4 outgoing, 3 drafts" },
  { t: "09:41:47", msg: "GET /notifications → 200 (412ms)" },
  { t: "09:41:47", msg: "GET /user/issues?filter=review-requested → 200" },
  { t: "09:41:46", msg: "Token refreshed · expires in 59m" },
  { t: "09:39:12", msg: "SLO breach: acme/mobile-ios#9788 crossed 4h" },
  { t: "09:38:01", msg: "Badge updated → 1 attention-needed" },
  { t: "09:36:55", msg: "Refresh complete · no changes" },
  { t: "09:34:55", msg: "GET /notifications → 200 (388ms)" },
  { t: "09:34:54", msg: "Scheduled refresh (interval 120s)" },
  { t: "09:31:20", msg: "CI status changed: acme/web#9826 → failing" },
  { t: "09:31:19", msg: "Webhook event: check_suite.completed" },
  { t: "09:28:40", msg: "Refresh complete · 1 new review request" },
];

// ── format helpers ──────────────────────────────────────────
function fmtElapsed(ms) {
  const m = Math.floor(ms / MIN);
  if (m < 1) return "just now";
  if (m < 60) return `${m}m ago`;
  const h = Math.floor(m / 60), rm = m % 60;
  if (h < 24) return rm > 0 ? `${h}h ${rm}m ago` : `${h}h ago`;
  return `${Math.floor(h / 24)}d ago`;
}

// SLO remaining/elapsed text. Overdue → "1h overdue".
function fmtRemaining(ms) {
  if (ms <= 0) {
    const over = -ms, m = Math.floor(over / MIN);
    if (m < 60) return `${m}m overdue`;
    const h = Math.floor(m / 60), rm = m % 60;
    return rm > 0 ? `${h}h ${rm}m overdue` : `${h}h overdue`;
  }
  const m = Math.floor(ms / MIN);
  if (m < 60) return `${m}m left`;
  const h = Math.floor(m / 60), rm = m % 60;
  return rm > 0 ? `${h}h ${rm}m left` : `${h}h left`;
}

function fmtElapsedSLO(ms) {
  const m = Math.floor(ms / MIN);
  if (m < 60) return `${m}m elapsed`;
  const h = Math.floor(m / 60), rm = m % 60;
  return rm > 0 ? `${h}h ${rm}m elapsed` : `${h}h elapsed`;
}

// SLO bucket: green <50%, amber 50–100%, red ≥100% of budget consumed.
function sloStatus(elapsedMs, sloHours) {
  const r = elapsedMs / (sloHours * HR);
  if (r < 0.5) return "green";
  if (r < 1) return "amber";
  return "red";
}

function sloPct(elapsedMs, sloHours) {
  return Math.min(100, (elapsedMs / (sloHours * HR)) * 100);
}

Object.assign(window, {
  HUB_DATA: { incoming: INCOMING, outgoing: OUTGOING, drafts: DRAFTS, account: ACCOUNT, devLog: DEV_LOG, MIN, HR },
  fmtElapsed, fmtRemaining, fmtElapsedSLO, sloStatus, sloPct,
});
