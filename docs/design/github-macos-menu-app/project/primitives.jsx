// Hubber primitives — pure components used by both the spec boards and the
// live mocks. Everything reads tokens from window.T(dark).

// ── SF Symbol-style icons (clean SVG approximations) ─────────
function SFIcon({ name, size = 14, color = "currentColor", weight = 1.6 }) {
  const p = {
    gear: <path d="M8 5.4a2.6 2.6 0 100 5.2 2.6 2.6 0 000-5.2zm6.3 2.6c0-.4 0-.7-.1-1.1l1.5-1.1-1.4-2.4-1.7.6c-.5-.4-1.1-.8-1.7-1L10.6.3H7.4l-.6 1.7c-.6.2-1.2.6-1.7 1l-1.7-.6L2 4.8l1.5 1.1c-.1.4-.1.7-.1 1.1s0 .7.1 1.1L2 9.2l1.4 2.4 1.7-.6c.5.4 1.1.8 1.7 1l.6 1.7h3.2l.6-1.7c.6-.2 1.2-.6 1.7-1l1.7.6 1.4-2.4-1.5-1.1c.1-.4.1-.7.1-1.1z" fill={color} stroke="none"/>,
    arrowClockwise: <g fill="none" stroke={color} strokeWidth={weight} strokeLinecap="round"><path d="M13.5 8a5.5 5.5 0 11-1.7-4"/><path d="M13.7 2.5V6h-3.5"/></g>,
    magnifier: <g fill="none" stroke={color} strokeWidth={weight} strokeLinecap="round"><circle cx="6.8" cy="6.8" r="4.6"/><path d="M10.3 10.3 14 14"/></g>,
    chevronRight: <path d="M6 3.5 10.5 8 6 12.5" fill="none" stroke={color} strokeWidth={weight} strokeLinecap="round" strokeLinejoin="round"/>,
    chat: <path d="M2.2 3.2h11.6v7.2H8.4L5.4 13v-2.6H2.2z" fill="none" stroke={color} strokeWidth={weight} strokeLinejoin="round"/>,
    person: <g fill={color}><circle cx="8" cy="5" r="3"/><path d="M2.5 14c0-3 2.5-4.6 5.5-4.6s5.5 1.6 5.5 4.6z"/></g>,
    checkSeal: <g fill="none" stroke={color} strokeWidth={weight} strokeLinecap="round" strokeLinejoin="round"><path d="M8 1.5l1.7 1.2 2-.3.9 1.9 1.8.9-.3 2 1.2 1.7-1.2 1.7.3 2-1.8.9-.9 1.9-2-.3L8 14.5l-1.7-1.2-2 .3-.9-1.9-1.8-.9.3-2L0 7.1l1.2-1.7-.3-2 1.8-.9.9-1.9 2 .3z"/><path d="M5.5 8l1.8 1.8L10.7 6"/></g>,
    pullRequest: <g fill="none" stroke={color} strokeWidth={weight} strokeLinecap="round" strokeLinejoin="round"><circle cx="4" cy="3.5" r="1.8"/><circle cx="4" cy="12.5" r="1.8"/><circle cx="12" cy="12.5" r="1.8"/><path d="M4 5.3v5.4"/><path d="M12 10.7V7.5a2.5 2.5 0 00-2.5-2.5H7.2"/><path d="M9 3l-1.8 2L9 7"/></g>,
    arrowDown: <path d="M8 2.5v9m0 0L4.5 8M8 11.5 11.5 8" fill="none" stroke={color} strokeWidth={weight} strokeLinecap="round" strokeLinejoin="round"/>,
    copy: <g fill="none" stroke={color} strokeWidth={weight} strokeLinejoin="round"><rect x="5" y="5" width="9" height="9" rx="2"/><path d="M11 5V3.5A1.5 1.5 0 009.5 2h-6A1.5 1.5 0 002 3.5v6A1.5 1.5 0 003.5 11H5"/></g>,
    trash: <g fill="none" stroke={color} strokeWidth={weight} strokeLinecap="round" strokeLinejoin="round"><path d="M2.5 4h11"/><path d="M5.5 4V2.8c0-.5.4-.8.8-.8h3.4c.4 0 .8.3.8.8V4"/><path d="M3.7 4l.6 9c0 .6.5 1 1 1h5.4c.5 0 1-.4 1-1l.6-9"/></g>,
    lock: <g fill="none" stroke={color} strokeWidth={weight} strokeLinejoin="round"><rect x="3" y="7" width="10" height="7" rx="1.6"/><path d="M5 7V5a3 3 0 016 0v2"/></g>,
    info: <g fill="none" stroke={color} strokeWidth={weight} strokeLinecap="round"><circle cx="8" cy="8" r="6.3"/><path d="M8 7.2v3.6"/><circle cx="8" cy="5.1" r="0.2" fill={color}/></g>,
  };
  return <svg width={size} height={size} viewBox="0 0 16 16" style={{ display: "block", flexShrink: 0 }}>{p[name]}</svg>;
}

// ── Avatar ───────────────────────────────────────────────────
// size: 36 (row), 24 (reviewer), 20 (reviewer compact). Circular,
// initials on deterministic color. Optional reviewer state dot.
function Avatar({ user, size = 36, state, dark, ringColor }) {
  const tk = window.T(dark);
  const dotSize = Math.max(8, Math.round(size * 0.30));
  const stateColor = state ? tk.rv[state] : null;
  const hollow = state === "pending";
  return (
    <div style={{ position: "relative", width: size, height: size, flexShrink: 0 }}>
      <div style={{
        width: size, height: size, borderRadius: "50%",
        background: user.color, color: "#fff",
        display: "flex", alignItems: "center", justifyContent: "center",
        fontFamily: window.HUB_FONT, fontWeight: 600,
        fontSize: Math.round(size * 0.40), letterSpacing: 0.2,
        boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.18)",
        userSelect: "none",
      }}>{user.avatar}</div>
      {stateColor && (
        <div style={{
          position: "absolute", right: -1, bottom: -1,
          width: dotSize, height: dotSize, borderRadius: "50%",
          background: hollow ? "transparent" : stateColor,
          border: hollow
            ? `1.5px solid ${tk.rv.pending}`
            : `1.5px solid ${ringColor || tk.materialSolid}`,
          boxShadow: hollow ? `0 0 0 1.5px ${ringColor || tk.materialSolid}` : "none",
          boxSizing: "border-box",
        }}/>
      )}
    </div>
  );
}

// ── SLO pill ─────────────────────────────────────────────────
// status: green | amber | red. Always dot + text (non-color cue).
function SLOPill({ status, text, dark }) {
  const tk = window.T(dark);
  const c = tk.slo[status];
  return (
    <div style={{
      display: "inline-flex", alignItems: "center", gap: 5,
      padding: "2.5px 8px 2.5px 7px", borderRadius: 6,
      background: c.bg, border: `0.5px solid ${c.border}`,
      flexShrink: 0,
    }}>
      <span style={{ width: 6, height: 6, borderRadius: "50%", background: c.fg, flexShrink: 0 }}/>
      <span style={{
        fontFamily: window.HUB_FONT, fontSize: 11, fontWeight: 590,
        color: c.fg, fontVariantNumeric: "tabular-nums", letterSpacing: -0.1,
        whiteSpace: "nowrap",
      }}>{text}</span>
    </div>
  );
}

// ── CI badge ─────────────────────────────────────────────────
// passing (green check) | failing (red x) | running (neutral spinner)
// | pending (grey clock). size scales the glyph.
function CIBadge({ status, size = 22, dark }) {
  const tk = window.T(dark);
  const c = tk.ci[status];
  if (status === "passing") return (
    <svg width={size} height={size} viewBox="0 0 22 22" style={{ display: "block", flexShrink: 0 }}>
      <circle cx="11" cy="11" r="11" fill={c}/>
      <path d="M6.3 11.3 9.4 14.4 15.7 8" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  );
  if (status === "failing") return (
    <svg width={size} height={size} viewBox="0 0 22 22" style={{ display: "block", flexShrink: 0 }}>
      <circle cx="11" cy="11" r="11" fill={c}/>
      <path d="M7.5 7.5l7 7M14.5 7.5l-7 7" stroke="#fff" strokeWidth="2" strokeLinecap="round"/>
    </svg>
  );
  if (status === "running") return (
    <svg width={size} height={size} viewBox="0 0 22 22" style={{ display: "block", flexShrink: 0 }}>
      <circle cx="11" cy="11" r="9" fill="none" stroke={tk.dark ? "rgba(255,255,255,0.18)" : "rgba(0,0,0,0.12)"} strokeWidth="2"/>
      <circle cx="11" cy="11" r="9" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeDasharray="14 42">
        <animateTransform attributeName="transform" type="rotate" from="0 11 11" to="360 11 11" dur="1.1s" repeatCount="indefinite"/>
      </circle>
    </svg>
  );
  // pending — grey clock
  return (
    <svg width={size} height={size} viewBox="0 0 22 22" style={{ display: "block", flexShrink: 0 }}>
      <circle cx="11" cy="11" r="9" fill="none" stroke={c} strokeWidth="2"/>
      <path d="M11 6.5V11l3 1.8" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  );
}

// ── Drafts document icon — dashed (signals "not ready") ──────
function DraftDocIcon({ size = 36, dark }) {
  const tk = window.T(dark);
  const w = Math.round(size * 0.62), h = Math.round(size * 0.78);
  return (
    <div style={{
      width: size, height: size, borderRadius: "50%",
      background: tk.fill, display: "flex", alignItems: "center", justifyContent: "center",
      flexShrink: 0,
    }}>
      <svg width={w} height={h} viewBox="0 0 18 22" style={{ display: "block" }}>
        <path d="M3 1.2h8l4 4v13.6a1.6 1.6 0 01-1.6 1.6H3a1.6 1.6 0 01-1.6-1.6V2.8A1.6 1.6 0 013 1.2z"
          fill="none" stroke={tk.text3} strokeWidth="1.4" strokeDasharray="2.4 2"/>
        <path d="M11 1.2V5h4" fill="none" stroke={tk.text3} strokeWidth="1.4" strokeLinejoin="round"/>
        <circle cx="13.2" cy="15.4" r="3.4" fill={tk.materialSolid} stroke={tk.text2} strokeWidth="1.2"/>
        <path d="M13.2 13.6v1.8l1.2.8" fill="none" stroke={tk.text2} strokeWidth="1.1" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>
    </div>
  );
}

// ── Menubar status icon (the menu-bar item itself) ───────────
// state: normal | attention | refreshing. menubarDark toggles the bar.
function MenubarIcon({ state = "normal", menubarDark, scale = 2 }) {
  const fg = menubarDark ? "rgba(255,255,255,0.92)" : "rgba(0,0,0,0.82)";
  const s = 18;
  return (
    <div style={{ position: "relative", width: s, height: s, transform: `scale(${scale})`, transformOrigin: "center" }}>
      <svg width={s} height={s} viewBox="0 0 16 16" style={{
        display: "block",
        animation: state === "refreshing" ? "hub-spin 1.1s linear infinite" : "none",
      }}>
        <g fill="none" stroke={fg} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="4" cy="3.5" r="1.7"/><circle cx="4" cy="12.5" r="1.7"/><circle cx="12" cy="12.5" r="1.7"/>
          <path d="M4 5.2v5.6"/><path d="M12 10.8V7.4A2.4 2.4 0 009.6 5H7.2"/><path d="M9 3l-1.8 2L9 7"/>
        </g>
      </svg>
      {state === "attention" && (
        <div style={{
          position: "absolute", top: -3, right: -4,
          minWidth: 9, height: 9, borderRadius: 5,
          background: "#FF3B30",
          boxShadow: `0 0 0 1.4px ${menubarDark ? "#1c1c1e" : "#f2f2f2"}`,
        }}/>
      )}
    </div>
  );
}

if (typeof document !== "undefined" && !document.getElementById("hub-keys")) {
  const st = document.createElement("style");
  st.id = "hub-keys";
  st.textContent = `
    @keyframes hub-spin { to { transform: rotate(360deg); } }
    @keyframes hub-shimmer { 0% { background-position: -200px 0; } 100% { background-position: 200px 0; } }
  `;
  document.head.appendChild(st);
}

Object.assign(window, { SFIcon, Avatar, SLOPill, CIBadge, DraftDocIcon, MenubarIcon });
