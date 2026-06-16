// Hubber row components + list states. Three row types (Reviews, Outgoing,
// Drafts), three densities, plus empty / error / loading states.

function densityCfg(d) {
  if (d === 1) return { padV: 6, padH: 14, avatar: 28, secondary: false, rv: 20, ci: 18, gap: 9, draftIcon: 28 };
  if (d === 3) return { padV: 13, padH: 16, avatar: 40, secondary: true, rv: 26, ci: 24, gap: 13, draftIcon: 40 };
  return { padV: 9.5, padH: 14, avatar: 36, secondary: true, rv: 24, ci: 22, gap: 11, draftIcon: 36 };
}

function sloPillText(status, elapsed, sloHours, mode) {
  const HR = window.HUB_DATA.HR;
  if (mode === "elapsed") return window.fmtElapsedSLO(elapsed);
  if (mode === "light") return status === "green" ? "On track" : status === "amber" ? "Due soon" : "Overdue";
  return window.fmtRemaining(sloHours * HR - elapsed);
}

// Shared row frame — handles padding, hover, optional signal treatment.
function RowFrame({ children, cfg, tk, signal, last }) {
  const [hover, setHover] = React.useState(false);
  return (
    <div
      onMouseEnter={() => setHover(true)} onMouseLeave={() => setHover(false)}
      style={{
        position: "relative",
        padding: `${cfg.padV}px ${cfg.padH}px ${cfg.padV}px ${signal ? cfg.padH - 3 : cfg.padH}px`,
        display: "flex", alignItems: cfg.secondary ? "flex-start" : "center", gap: cfg.gap,
        background: signal ? tk.signalTint : (hover ? tk.fill : "transparent"),
        borderLeft: signal ? `3px solid ${tk.signalAccent}` : "3px solid transparent",
        borderBottom: last ? "none" : `0.5px solid ${tk.sep}`,
        cursor: "default", transition: "background 0.12s",
      }}>
      {children}
    </div>
  );
}

function TitleLine({ number, title, tk }) {
  return (
    <div style={{
      display: "flex", alignItems: "baseline", gap: 6, minWidth: 0,
      whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
    }}>
      <span style={{ color: tk.text3, fontFamily: window.HUB_MONO, fontSize: 11, flexShrink: 0, fontWeight: 500 }}>
        #{number}
      </span>
      <span style={{
        fontFamily: window.HUB_FONT, fontSize: 13, fontWeight: 500, color: tk.text,
        letterSpacing: -0.1, overflow: "hidden", textOverflow: "ellipsis",
      }}>{title}</span>
    </div>
  );
}

function SecondaryLine({ children, tk }) {
  return (
    <div style={{
      display: "flex", alignItems: "center", gap: 5, marginTop: 3,
      fontFamily: window.HUB_FONT, fontSize: 11, fontWeight: 400, color: tk.text2,
      whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis",
    }}>{children}</div>
  );
}

function Dot({ tk }) { return <span style={{ color: tk.text3 }}>·</span>; }

// ── Reviews row ──────────────────────────────────────────────
function ReviewRow({ pr, density = 2, dark, sloMode = "remaining", sloHours = 4, last }) {
  const tk = window.T(dark);
  const cfg = densityCfg(density);
  const status = window.sloStatus(pr.assignedAgo, sloHours);
  const text = sloPillText(status, pr.assignedAgo, sloHours, sloMode);
  return (
    <RowFrame cfg={cfg} tk={tk} last={last}>
      <window.Avatar user={pr.author} size={cfg.avatar} dark={dark}/>
      <div style={{ flex: 1, minWidth: 0 }}>
        <TitleLine number={pr.number} title={pr.title} tk={tk}/>
        {cfg.secondary && (
          <SecondaryLine tk={tk}>
            <span style={{ overflow: "hidden", textOverflow: "ellipsis" }}>{pr.repo}</span>
            <Dot tk={tk}/>
            <span>{pr.author.login}</span>
            {pr.teamRequest && (<><Dot tk={tk}/><span style={{ color: tk.text3 }}>team</span></>)}
          </SecondaryLine>
        )}
      </div>
      <div style={{ alignSelf: cfg.secondary ? "flex-start" : "center", marginTop: cfg.secondary ? 1 : 0 }}>
        <window.SLOPill status={status} text={text} dark={dark}/>
      </div>
    </RowFrame>
  );
}

// ── Outgoing row ─────────────────────────────────────────────
function OutgoingRow({ pr, density = 2, dark, last }) {
  const tk = window.T(dark);
  const cfg = densityCfg(density);
  const signal = pr.ci === "failing" || pr.unresolved > 0; // running is NOT a signal
  const ciColor = tk.ci[pr.ci];
  return (
    <RowFrame cfg={cfg} tk={tk} signal={signal} last={last}>
      <div style={{ alignSelf: cfg.secondary ? "flex-start" : "center", marginTop: cfg.secondary ? 1 : 0 }}>
        <window.CIBadge status={pr.ci} size={cfg.ci} dark={dark}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <TitleLine number={pr.number} title={pr.title} tk={tk}/>
        {cfg.secondary && (
          <SecondaryLine tk={tk}>
            <span>{pr.repo}</span>
            <Dot tk={tk}/>
            <span style={{ color: pr.ci === "failing" ? ciColor : tk.text2 }}>{pr.ciDetail}</span>
            {pr.unresolved > 0 && (
              <>
                <Dot tk={tk}/>
                <span style={{ display: "inline-flex", alignItems: "center", gap: 3, color: tk.text2 }}>
                  <window.SFIcon name="chat" size={11} color={tk.text2} weight={1.5}/>
                  {pr.unresolved} {pr.unresolved === 1 ? "thread" : "threads"}
                </span>
              </>
            )}
          </SecondaryLine>
        )}
      </div>
      {/* reviewer avatar stack */}
      <div style={{ display: "flex", alignSelf: "center", paddingLeft: 4 }}>
        {pr.reviewers.slice(0, 3).map((r, i) => (
          <div key={r.login} style={{ marginLeft: i === 0 ? 0 : -7, zIndex: 3 - i }}>
            <window.Avatar user={r} size={cfg.rv} state={r.state} dark={dark}/>
          </div>
        ))}
      </div>
    </RowFrame>
  );
}

// ── Drafts row ───────────────────────────────────────────────
function DraftRow({ pr, density = 2, dark, last }) {
  const tk = window.T(dark);
  const cfg = densityCfg(density);
  const ciColor = pr.ci === "passing" ? tk.ci.passing : pr.ci === "failing" ? tk.ci.failing : tk.text2;
  return (
    <RowFrame cfg={cfg} tk={tk} last={last}>
      <div style={{ alignSelf: cfg.secondary ? "flex-start" : "center" }}>
        <window.DraftDocIcon size={cfg.draftIcon} dark={dark}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <TitleLine number={pr.number} title={pr.title} tk={tk}/>
        {cfg.secondary && (
          <SecondaryLine tk={tk}>
            <span>{pr.repo}</span>
            <Dot tk={tk}/>
            <span>{pr.commits} commits</span>
            <Dot tk={tk}/>
            <span>updated {window.fmtElapsed(pr.updatedAgo)}</span>
          </SecondaryLine>
        )}
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 5, alignSelf: "center" }}>
        <window.CIBadge status={pr.ci} size={cfg.ci - 4} dark={dark}/>
        {cfg.secondary && (
          <span style={{
            fontFamily: window.HUB_FONT, fontSize: 11, color: ciColor, fontWeight: 400,
          }}>{pr.ci === "passing" ? "Passing" : pr.ci === "failing" ? "Failing" : pr.ci === "running" ? "Running" : "Pending"}</span>
        )}
      </div>
    </RowFrame>
  );
}

// ── States ───────────────────────────────────────────────────
// Shared centered panel: icon disc + title + body + optional meta + action.
// Backs every empty / offline / error state across the three tabs.
function StatePanel({ dark, icon, tone = "neutral", title, body, meta, action }) {
  const tk = window.T(dark);
  const tones = {
    green:   { bg: tk.slo.green.bg, border: tk.slo.green.border, fg: tk.slo.green.fg },
    red:     { bg: tk.slo.red.bg,   border: tk.slo.red.border,   fg: tk.error },
    neutral: { bg: tk.fill,         border: tk.sep,              fg: tk.text2 },
  };
  const c = tones[tone] || tones.neutral;
  return (
    <div style={{
      flex: 1, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center",
      gap: 9, padding: "32px 40px", textAlign: "center", minHeight: 300,
    }}>
      <div style={{
        width: 56, height: 56, borderRadius: "50%", background: c.bg,
        border: `0.5px solid ${c.border}`, display: "flex", alignItems: "center", justifyContent: "center",
        color: c.fg, marginBottom: 2,
      }}>{icon}</div>
      <div style={{ fontFamily: window.HUB_FONT_D, fontSize: 15, fontWeight: 600, color: tk.text, letterSpacing: -0.2 }}>{title}</div>
      <div style={{ fontFamily: window.HUB_FONT, fontSize: 12, color: tk.text2, maxWidth: 252, lineHeight: 1.45 }}>{body}</div>
      {meta && <div style={{ fontFamily: window.HUB_FONT, fontSize: 11, color: tk.text3, marginTop: 1, fontVariantNumeric: "tabular-nums" }}>{meta}</div>}
      {action && (
        <button onClick={action.onClick} style={{
          marginTop: 9, display: "inline-flex", alignItems: "center", gap: 6,
          fontFamily: window.HUB_FONT, fontSize: 12.5, fontWeight: 560, color: "#fff",
          background: tk.accent, border: "none", borderRadius: 7, padding: "7px 15px",
          cursor: "pointer", boxShadow: "0 1px 2px rgba(0,0,0,0.16)",
        }}>
          {action.icon}<span>{action.label}</span>
        </button>
      )}
    </div>
  );
}

const TAB_NOUN = { reviews: "reviews", outgoing: "pull requests", drafts: "drafts" };

// Per-tab empty states.
function EmptyState({ dark, tab = "reviews", title, body }) {
  const tk = window.T(dark);
  const cfg = {
    reviews:  { tone: "green",   title: "All clear",         body: "No reviews waiting on you. Enjoy the deep work." },
    outgoing: { tone: "neutral", title: "Nothing in flight", body: "Pull requests you open show up here with their CI status and review progress." },
    drafts:   { tone: "neutral", title: "No drafts",          body: "Draft pull requests you\u2019re still shaping live here until you mark them ready." },
  }[tab] || {};
  let icon;
  if (tab === "reviews") {
    icon = (
      <svg width="27" height="27" viewBox="0 0 28 28">
        <path d="M7 14.5l4.5 4.5L21 9" fill="none" stroke={tk.slo.green.fg} strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>
    );
  } else if (tab === "outgoing") {
    icon = <window.SFIcon name="paperplane" size={26} color={tk.text2} weight={1.5}/>;
  } else {
    icon = (
      <svg width="22" height="26" viewBox="0 0 18 22">
        <path d="M3 1.2h8l4 4v13.6a1.6 1.6 0 01-1.6 1.6H3a1.6 1.6 0 01-1.6-1.6V2.8A1.6 1.6 0 013 1.2z" fill="none" stroke={tk.text2} strokeWidth="1.4" strokeDasharray="2.4 2"/>
        <path d="M11 1.2V5h4" fill="none" stroke={tk.text2} strokeWidth="1.4" strokeLinejoin="round"/>
      </svg>
    );
  }
  return <StatePanel dark={dark} tone={cfg.tone} icon={icon} title={title || cfg.title} body={body || cfg.body}/>;
}

// Full-panel OFFLINE state (no cached data to fall back on).
function OfflinePanel({ dark, tab = "reviews", lastSynced = "8m ago", onRetry }) {
  const tk = window.T(dark);
  return <StatePanel dark={dark} tone="neutral"
    icon={<window.SFIcon name="wifiSlash" size={26} color={tk.text2} weight={1.6}/>}
    title="You're offline"
    body={`Hubber can\u2019t reach GitHub right now. Your ${TAB_NOUN[tab]} will refresh automatically once you\u2019re back online.`}
    meta={`Last synced ${lastSynced}`}
    action={{ label: "Try again", onClick: onRetry, icon: <window.SFIcon name="arrowClockwise" size={13} color="#fff" weight={1.8}/> }}/>;
}

// Full-panel ERROR state (request failed, no cached data).
function ErrorPanel({ dark, tab = "reviews", code = "502", onRetry }) {
  const tk = window.T(dark);
  return <StatePanel dark={dark} tone="red"
    icon={<window.SFIcon name="warning" size={27} color={tk.error} weight={1.7}/>}
    title="Couldn't reach GitHub"
    body={`Something went wrong loading your ${TAB_NOUN[tab]}. This is usually temporary \u2014 give it another try.`}
    meta={`Error ${code} \u00b7 Last synced 3m ago`}
    action={{ label: "Retry", onClick: onRetry, icon: <window.SFIcon name="arrowClockwise" size={13} color="#fff" weight={1.8}/> }}/>;
}

// Slim inline banner shown ABOVE stale rows when a refresh fails but cached
// data is still on screen. kind: offline | error.
function InlineBanner({ dark, kind = "offline", lastSynced = "8m ago", onRetry }) {
  const tk = window.T(dark);
  const isErr = kind === "error";
  const c = isErr ? tk.slo.red : tk.slo.amber;
  return (
    <div style={{
      margin: "9px 12px 3px", padding: "7px 9px 7px 11px", borderRadius: 8,
      background: c.bg, border: `0.5px solid ${c.border}`,
      display: "flex", alignItems: "center", gap: 9,
    }}>
      <window.SFIcon name={isErr ? "warning" : "wifiSlash"} size={15} color={c.fg} weight={1.6}/>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontFamily: window.HUB_FONT, fontSize: 11.5, fontWeight: 560, color: tk.text, letterSpacing: -0.05 }}>
          {isErr ? "Couldn\u2019t refresh" : "You\u2019re offline"}
        </div>
        <div style={{ fontFamily: window.HUB_FONT, fontSize: 11, color: tk.text2, marginTop: 0.5, fontVariantNumeric: "tabular-nums" }}>
          Showing data from {lastSynced}
        </div>
      </div>
      <button onClick={onRetry} style={{
        fontFamily: window.HUB_FONT, fontSize: 11.5, fontWeight: 560, color: c.fg,
        background: "transparent", border: "none", cursor: "pointer", padding: "3px 5px", whiteSpace: "nowrap",
      }}>Retry</button>
    </div>
  );
}



function SkeletonRow({ dark, last }) {
  const tk = window.T(dark);
  const bar = (w, h = 9) => (
    <div style={{
      width: w, height: h, borderRadius: 4,
      background: dark
        ? "linear-gradient(90deg, rgba(255,255,255,0.05) 25%, rgba(255,255,255,0.11) 37%, rgba(255,255,255,0.05) 63%)"
        : "linear-gradient(90deg, rgba(0,0,0,0.04) 25%, rgba(0,0,0,0.08) 37%, rgba(0,0,0,0.04) 63%)",
      backgroundSize: "400px 100%",
      animation: "hub-shimmer 1.4s ease-in-out infinite",
    }}/>
  );
  return (
    <div style={{
      padding: "9.5px 14px", display: "flex", alignItems: "flex-start", gap: 11,
      borderBottom: last ? "none" : `0.5px solid ${tk.sep}`,
    }}>
      <div style={{
        width: 36, height: 36, borderRadius: "50%",
        background: dark
          ? "linear-gradient(90deg, rgba(255,255,255,0.05) 25%, rgba(255,255,255,0.11) 37%, rgba(255,255,255,0.05) 63%)"
          : "linear-gradient(90deg, rgba(0,0,0,0.04) 25%, rgba(0,0,0,0.08) 37%, rgba(0,0,0,0.04) 63%)",
        backgroundSize: "400px 100%", animation: "hub-shimmer 1.4s ease-in-out infinite", flexShrink: 0,
      }}/>
      <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 7, paddingTop: 3 }}>
        {bar("70%")}
        {bar("42%", 8)}
      </div>
      <div style={{ paddingTop: 3 }}>{bar(58, 16)}</div>
    </div>
  );
}

Object.assign(window, {
  densityCfg, sloPillText, ReviewRow, OutgoingRow, DraftRow,
  StatePanel, EmptyState, OfflinePanel, ErrorPanel, InlineBanner, SkeletonRow,
  ErrorState: InlineBanner, // back-compat alias
});
