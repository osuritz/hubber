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
function EmptyState({ dark, title = "All clear", body = "No reviews waiting on you. Enjoy the deep work." }) {
  const tk = window.T(dark);
  return (
    <div style={{
      flex: 1, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center",
      gap: 10, padding: "40px 36px", textAlign: "center",
    }}>
      <div style={{
        width: 54, height: 54, borderRadius: "50%", background: tk.slo.green.bg,
        display: "flex", alignItems: "center", justifyContent: "center",
        border: `0.5px solid ${tk.slo.green.border}`,
      }}>
        <svg width="28" height="28" viewBox="0 0 28 28">
          <path d="M7 14.5l4.5 4.5L21 9" fill="none" stroke={tk.slo.green.fg} strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
      </div>
      <div style={{ fontFamily: window.HUB_FONT_D, fontSize: 15, fontWeight: 600, color: tk.text, letterSpacing: -0.2 }}>{title}</div>
      <div style={{ fontFamily: window.HUB_FONT, fontSize: 12, color: tk.text2, maxWidth: 240, lineHeight: 1.45 }}>{body}</div>
    </div>
  );
}

function ErrorState({ dark, onRetry }) {
  const tk = window.T(dark);
  return (
    <div style={{
      margin: "10px 12px", padding: "10px 12px", borderRadius: 8,
      background: tk.slo.red.bg, border: `0.5px solid ${tk.slo.red.border}`,
      display: "flex", alignItems: "center", gap: 10,
    }}>
      <svg width="16" height="16" viewBox="0 0 16 16" style={{ flexShrink: 0 }}>
        <circle cx="8" cy="8" r="7" fill="none" stroke={tk.error} strokeWidth="1.5"/>
        <path d="M8 4.5V9" stroke={tk.error} strokeWidth="1.5" strokeLinecap="round"/>
        <circle cx="8" cy="11.4" r="0.4" fill={tk.error}/>
      </svg>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontFamily: window.HUB_FONT, fontSize: 12, fontWeight: 500, color: tk.text }}>
          Couldn't load reviews
        </div>
        <div style={{ fontFamily: window.HUB_FONT, fontSize: 11, color: tk.text2, marginTop: 1 }}>
          Last updated 3m ago
        </div>
      </div>
      <button style={{
        fontFamily: window.HUB_FONT, fontSize: 12, fontWeight: 500, color: tk.accent,
        background: "transparent", border: "none", cursor: "pointer", padding: "2px 4px",
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
  EmptyState, ErrorState, SkeletonRow,
});
