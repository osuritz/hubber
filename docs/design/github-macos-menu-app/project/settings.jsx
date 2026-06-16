// Hubber Settings screen — full-height scroll view that replaces the list.
// Native grouped sections: account, reviews, outgoing, appearance, badge,
// privacy, and a debug-only developer log viewer.

// ── macOS switch ─────────────────────────────────────────────
function Switch({ on, onChange, dark, disabled }) {
  const tk = window.T(dark);
  return (
    <button onClick={() => !disabled && onChange(!on)} disabled={disabled}
      style={{
        width: 38, height: 23, borderRadius: 12, border: "none", padding: 0,
        position: "relative", cursor: disabled ? "default" : "pointer",
        background: on ? (dark ? "#30D158" : "#34C759") : (dark ? "rgba(255,255,255,0.16)" : "rgba(0,0,0,0.16)"),
        opacity: disabled ? 0.5 : 1, transition: "background .18s", flexShrink: 0,
        boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.06)",
      }}>
      <span style={{
        position: "absolute", top: 2, left: on ? 17 : 2, width: 19, height: 19, borderRadius: "50%",
        background: "#fff", boxShadow: "0 1px 3px rgba(0,0,0,0.3), 0 0 0 0.5px rgba(0,0,0,0.04)",
        transition: "left .18s cubic-bezier(.2,.7,.3,1)",
      }}/>
    </button>
  );
}

// ── Slider ───────────────────────────────────────────────────
function Slider({ value, min, max, step = 1, onChange, dark, disabled }) {
  const tk = window.T(dark);
  const pct = ((value - min) / (max - min)) * 100;
  return (
    <div style={{ position: "relative", flex: 1, height: 18, display: "flex", alignItems: "center", opacity: disabled ? 0.5 : 1 }}>
      <div style={{ position: "absolute", left: 0, right: 0, height: 4, borderRadius: 2, background: tk.ctrlTrack }}/>
      <div style={{ position: "absolute", left: 0, width: `${pct}%`, height: 4, borderRadius: 2, background: disabled ? tk.text3 : tk.accent }}/>
      <input type="range" min={min} max={max} step={step} value={value} disabled={disabled}
        onChange={(e) => onChange(parseInt(e.target.value))}
        style={{
          position: "absolute", left: -2, right: -2, width: "calc(100% + 4px)", margin: 0,
          background: "transparent", WebkitAppearance: "none", cursor: disabled ? "default" : "pointer",
        }}/>
    </div>
  );
}

// ── Layout helpers ───────────────────────────────────────────
function SectionLabel({ children, chip, tk }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 7, padding: "0 4px 6px" }}>
      <span style={{
        fontFamily: window.HUB_FONT, fontSize: 11, fontWeight: 600, color: tk.text2,
        textTransform: "uppercase", letterSpacing: 0.4,
      }}>{children}</span>
      {chip && (
        <span style={{
          fontFamily: window.HUB_MONO, fontSize: 9.5, fontWeight: 600, color: dark2(tk),
          background: tk.dark ? "rgba(255,159,10,0.18)" : "rgba(255,149,0,0.14)",
          padding: "1px 5px", borderRadius: 4, letterSpacing: 0.3,
          textTransform: "uppercase",
        }}>{chip}</span>
      )}
    </div>
  );
}
function dark2(tk) { return tk.dark ? "#FFA00A" : "#9A5B00"; }

function Group({ children, tk }) {
  return (
    <div style={{
      borderRadius: 10, overflow: "hidden",
      background: tk.dark ? "rgba(255,255,255,0.05)" : "rgba(255,255,255,0.5)",
      border: `0.5px solid ${tk.sep}`,
    }}>{children}</div>
  );
}

function GRow({ children, tk, last, align = "center", stack }) {
  return (
    <div style={{
      padding: stack ? "9px 12px" : "8px 12px",
      borderBottom: last ? "none" : `0.5px solid ${tk.sep}`,
      display: "flex", flexDirection: stack ? "column" : "row",
      alignItems: stack ? "stretch" : align, gap: stack ? 8 : 12,
      minHeight: 22,
    }}>{children}</div>
  );
}

function RowLabel({ children, sub, tk, disabled }) {
  return (
    <div style={{ flex: 1, minWidth: 0, opacity: disabled ? 0.5 : 1 }}>
      <div style={{ fontFamily: window.HUB_FONT, fontSize: 12.5, fontWeight: 400, color: tk.text }}>{children}</div>
      {sub && <div style={{ fontFamily: window.HUB_FONT, fontSize: 11, color: tk.text2, marginTop: 1 }}>{sub}</div>}
    </div>
  );
}

// ── Settings screen ──────────────────────────────────────────
function SettingsScreen({ dark, onBack, init = {} }) {
  const tk = window.T(dark);
  const D = window.HUB_DATA;
  const [sloOn, setSloOn] = React.useState(init.sloOn ?? true);
  const [sloHours, setSloHours] = React.useState(init.sloHours ?? 4);
  const [sloMode, setSloMode] = React.useState(init.sloMode ?? "remaining");
  const [incomingMode, setIncomingMode] = React.useState("explicit");
  const [threadsMode, setThreadsMode] = React.useState("all");
  const [density, setDensity] = React.useState(init.density === 1 ? "compact" : init.density === 3 ? "spacious" : "default");
  const [badgeMode, setBadgeMode] = React.useState("attention");
  const [analytics, setAnalytics] = React.useState(true);
  const [crash, setCrash] = React.useState(true);
  const [collectOpen, setCollectOpen] = React.useState(false);
  const reauth = init.reauth;

  const hoursLabel = `${sloHours} ${sloHours === 1 ? "hour" : "hours"}`;

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
      {/* header */}
      <div style={{
        flexShrink: 0, padding: "11px 10px 11px 8px", display: "flex", alignItems: "center", gap: 4,
        borderBottom: `0.5px solid ${tk.sep}`,
      }}>
        <button onClick={onBack} style={{
          border: "none", background: "transparent", cursor: "pointer", padding: "4px 6px", borderRadius: 6,
          display: "flex", alignItems: "center", gap: 3, color: tk.accent,
          fontFamily: window.HUB_FONT, fontSize: 13,
        }}>
          <svg width="10" height="14" viewBox="0 0 10 14"><path d="M8 2 3 7l5 5" fill="none" stroke={tk.accent} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/></svg>
          <span>Hubber</span>
        </button>
        <span style={{ position: "absolute", left: 0, right: 0, textAlign: "center", fontFamily: window.HUB_FONT_D, fontSize: 13, fontWeight: 600, color: tk.text, pointerEvents: "none" }}>
          Settings
        </span>
      </div>

      {/* scroll */}
      <div className="hub-scroll" style={{ flex: 1, overflowY: "auto", padding: "14px 14px 18px" }}>
        {/* Account */}
        <SectionLabel tk={tk}>GitHub Account</SectionLabel>
        <Group tk={tk}>
          {reauth ? (
            <GRow tk={tk} last align="center">
              <div style={{ display: "flex", alignItems: "center", gap: 10, flex: 1 }}>
                <div style={{ width: 34, height: 34, borderRadius: "50%", background: tk.slo.amber.bg, display: "flex", alignItems: "center", justifyContent: "center", border: `0.5px solid ${tk.slo.amber.border}` }}>
                  <window.SFIcon name="lock" size={15} color={tk.slo.amber.fg}/>
                </div>
                <div>
                  <div style={{ fontFamily: window.HUB_FONT, fontSize: 12.5, fontWeight: 500, color: tk.text }}>Session expired</div>
                  <div style={{ fontFamily: window.HUB_FONT, fontSize: 11, color: tk.text2, marginTop: 1 }}>Sign in again to keep syncing</div>
                </div>
              </div>
              <button style={btn(tk, true)}>Sign in</button>
            </GRow>
          ) : (
            <GRow tk={tk} last align="center">
              <window.Avatar user={D.account} size={34} dark={dark}/>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontFamily: window.HUB_FONT, fontSize: 12.5, fontWeight: 500, color: tk.text }}>{D.account.name}</div>
                <div style={{ fontFamily: window.HUB_MONO, fontSize: 11, color: tk.text2, marginTop: 1 }}>@{D.account.login}</div>
              </div>
              <button style={btn(tk)}>Sign out</button>
            </GRow>
          )}
        </Group>

        {/* Incoming Reviews */}
        <div style={{ height: 18 }}/>
        <SectionLabel tk={tk}>Incoming Reviews</SectionLabel>
        <Group tk={tk}>
          <GRow tk={tk}>
            <RowLabel tk={tk} sub="Flag reviews against a time budget">Review SLO</RowLabel>
            <Switch on={sloOn} onChange={setSloOn} dark={dark}/>
          </GRow>
          <GRow tk={tk} align="center">
            <RowLabel tk={tk} disabled={!sloOn}>Review window</RowLabel>
            <div style={{ display: "flex", alignItems: "center", gap: 12, flex: 1.3, maxWidth: 220 }}>
              <Slider value={sloHours} min={1} max={24} onChange={setSloHours} dark={dark} disabled={!sloOn}/>
              <span style={{ fontFamily: window.HUB_FONT, fontSize: 12, fontWeight: 500, color: sloOn ? tk.text : tk.text3, minWidth: 56, textAlign: "right", fontVariantNumeric: "tabular-nums" }}>{hoursLabel}</span>
            </div>
          </GRow>
          <GRow tk={tk} stack>
            <RowLabel tk={tk} disabled={!sloOn}>Show SLO as</RowLabel>
            <window.Segmented dark={dark} size="sm" value={sloMode} onChange={setSloMode}
              options={[
                { id: "remaining", label: "Remaining", disabled: !sloOn },
                { id: "elapsed", label: "Elapsed", disabled: !sloOn },
                { id: "light", label: "Light only", disabled: !sloOn },
              ]}/>
          </GRow>
          <GRow tk={tk} stack last>
            <RowLabel tk={tk}>Incoming requests</RowLabel>
            <window.Segmented dark={dark} size="sm" value={incomingMode} onChange={setIncomingMode}
              options={[
                { id: "explicit", label: "Explicit requests" },
                { id: "team", label: "Include team" },
              ]}/>
          </GRow>
        </Group>

        {/* Outgoing */}
        <div style={{ height: 18 }}/>
        <SectionLabel tk={tk}>Outgoing</SectionLabel>
        <Group tk={tk}>
          <GRow tk={tk} stack last>
            <RowLabel tk={tk} sub="Which threads count as unresolved">Unresolved threads</RowLabel>
            <window.Segmented dark={dark} size="sm" value={threadsMode} onChange={setThreadsMode}
              options={[
                { id: "all", label: "All threads" },
                { id: "review", label: "Review" },
                { id: "changes", label: "Changes req." },
              ]}/>
          </GRow>
        </Group>

        {/* Appearance */}
        <div style={{ height: 18 }}/>
        <SectionLabel tk={tk}>Appearance</SectionLabel>
        <Group tk={tk}>
          <GRow tk={tk} stack last>
            <RowLabel tk={tk}>Row density</RowLabel>
            <window.Segmented dark={dark} size="sm" value={density} onChange={setDensity}
              options={[
                { id: "compact", label: "Compact" },
                { id: "default", label: "Default" },
                { id: "spacious", label: "Spacious" },
              ]}/>
          </GRow>
        </Group>

        {/* Badge */}
        <div style={{ height: 18 }}/>
        <SectionLabel tk={tk}>Menubar Badge</SectionLabel>
        <Group tk={tk}>
          <GRow tk={tk} stack last>
            <RowLabel tk={tk}>Badge shows</RowLabel>
            <window.Segmented dark={dark} size="sm" value={badgeMode} onChange={setBadgeMode}
              options={[
                { id: "incoming", label: "Incoming" },
                { id: "attention", label: "Attention" },
                { id: "off", label: "Off" },
              ]}/>
          </GRow>
        </Group>

        {/* Privacy */}
        <div style={{ height: 18 }}/>
        <SectionLabel tk={tk}>Privacy</SectionLabel>
        <Group tk={tk}>
          <GRow tk={tk}>
            <RowLabel tk={tk}>Send anonymous usage analytics</RowLabel>
            <Switch on={analytics} onChange={setAnalytics} dark={dark}/>
          </GRow>
          <GRow tk={tk}>
            <RowLabel tk={tk}>Crash reporting</RowLabel>
            <Switch on={crash} onChange={setCrash} dark={dark}/>
          </GRow>
          <GRow tk={tk} stack={collectOpen} last align="center">
            <button onClick={() => setCollectOpen(!collectOpen)} style={{
              border: "none", background: "transparent", cursor: "pointer", padding: 0,
              display: "flex", alignItems: "center", gap: 6, color: tk.accent,
              fontFamily: window.HUB_FONT, fontSize: 12.5, width: "100%", textAlign: "left",
            }}>
              <window.SFIcon name="info" size={13} color={tk.accent}/>
              <span style={{ flex: 1, textAlign: "left" }}>What we collect</span>
              <svg width="9" height="13" viewBox="0 0 9 13" style={{ transform: collectOpen ? "rotate(90deg)" : "none", transition: "transform .15s" }}>
                <path d="M2 2l4.5 4.5L2 11" fill="none" stroke={tk.accent} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/>
              </svg>
            </button>
            {collectOpen && (
              <div style={{ fontFamily: window.HUB_FONT, fontSize: 11.5, color: tk.text2, lineHeight: 1.5, paddingTop: 2 }}>
                Anonymous event counts (tabs opened, refreshes) and aggregate timing. Never your code, PR contents, repo names, or tokens. Crash reports include a stack trace and app version only.
              </div>
            )}
          </GRow>
        </Group>

        {/* Developer (debug) */}
        <div style={{ height: 18 }}/>
        <SectionLabel tk={tk} chip="debug">Developer</SectionLabel>
        <DeveloperLog dark={dark}/>
      </div>
    </div>
  );
}

function btn(tk, filled) {
  return {
    fontFamily: window.HUB_FONT, fontSize: 12, fontWeight: 500,
    color: filled ? "#fff" : tk.text,
    background: filled ? tk.accent : (tk.dark ? "rgba(255,255,255,0.10)" : "rgba(0,0,0,0.05)"),
    border: filled ? "none" : `0.5px solid ${tk.sep}`,
    borderRadius: 6, padding: "4px 12px", cursor: "pointer", flexShrink: 0,
    boxShadow: filled ? "0 1px 2px rgba(0,0,0,0.12)" : "none",
  };
}

// ── Developer log viewer ─────────────────────────────────────
function DeveloperLog({ dark }) {
  const tk = window.T(dark);
  const [log, setLog] = React.useState(window.HUB_DATA.devLog);
  const [copied, setCopied] = React.useState(false);

  const copy = () => {
    const text = log.map((e) => `[${e.t}] ${e.msg}`).join("\n");
    try { navigator.clipboard?.writeText(text); } catch (e) {}
    setCopied(true); setTimeout(() => setCopied(false), 1400);
  };

  return (
    <Group tk={tk}>
      <div style={{
        height: 168, overflowY: "auto", padding: "8px 12px",
        background: tk.dark ? "rgba(0,0,0,0.22)" : "rgba(0,0,0,0.03)",
      }} className="hub-scroll">
        {log.length === 0 ? (
          <div style={{ fontFamily: window.HUB_FONT, fontSize: 11.5, color: tk.text2, padding: "8px 0" }}>No logs yet</div>
        ) : (
          log.map((e, i) => (
            <div key={i} style={{
              fontFamily: window.HUB_MONO, fontSize: 11, lineHeight: 1.65,
              color: tk.text2, display: "flex", gap: 8, whiteSpace: "nowrap",
            }}>
              <span style={{ color: tk.text3, flexShrink: 0 }}>{e.t}</span>
              <span style={{ color: tk.text, overflow: "hidden", textOverflow: "ellipsis" }}>{e.msg}</span>
            </div>
          ))
        )}
      </div>
      <div style={{
        display: "flex", gap: 8, padding: "8px 12px", borderTop: `0.5px solid ${tk.sep}`,
        alignItems: "center",
      }}>
        <button onClick={copy} style={{ ...btn(tk), display: "flex", alignItems: "center", gap: 5 }}>
          <window.SFIcon name="copy" size={12} color={tk.text}/>
          {copied ? "Copied" : "Copy"}
        </button>
        <button onClick={() => setLog([])} style={{ ...btn(tk), display: "flex", alignItems: "center", gap: 5 }}>
          <window.SFIcon name="trash" size={12} color={tk.text}/>
          Clear
        </button>
        <div style={{ flex: 1 }}/>
        <span style={{ fontFamily: window.HUB_FONT, fontSize: 11, color: tk.text3 }}>{log.length} entries</span>
      </div>
    </Group>
  );
}

Object.assign(window, { SettingsScreen, Switch, Slider, DeveloperLog });
