// Hubber popover chrome + the three list screens. The popover is the
// 420×540 vibrancy panel: header (title + gear), segmented tabs, scrolling
// list, footer. Settings replaces the body (see settings.jsx).

// ── Reusable macOS segmented control ─────────────────────────
function Segmented({ options, value, onChange, dark, size = "md", full = true }) {
  const tk = window.T(dark);
  const padV = size === "sm" ? 4 : 5;
  const fs = size === "sm" ? 11.5 : 12.5;
  return (
    <div style={{
      display: "flex", gap: 2, padding: 2, borderRadius: size === "sm" ? 6 : 7,
      background: tk.ctrlTrack, width: full ? "100%" : "auto",
    }}>
      {options.map((o) => {
        const active = value === o.id;
        return (
          <button key={o.id} onClick={() => onChange(o.id)} disabled={o.disabled}
            style={{
              flex: full ? 1 : "0 0 auto", padding: `${padV}px 8px`, borderRadius: size === "sm" ? 4.5 : 5.5,
              border: "none", cursor: o.disabled ? "default" : "pointer",
              background: active ? tk.ctrlThumb : "transparent",
              boxShadow: active ? tk.ctrlShadow : "none",
              color: o.disabled ? tk.text3 : (active ? tk.text : tk.text2),
              fontFamily: window.HUB_FONT, fontSize: fs, fontWeight: active ? 590 : 500,
              letterSpacing: -0.1, transition: "color .12s, background .12s",
              display: "flex", alignItems: "center", justifyContent: "center", gap: 5,
              opacity: o.disabled ? 0.55 : 1, whiteSpace: "nowrap",
            }}>
            <span>{o.label}</span>
            {o.badge != null && o.badge > 0 && (
              <span style={{
                fontSize: 10, fontWeight: 600, fontVariantNumeric: "tabular-nums",
                color: active ? tk.text : tk.text2,
                background: active ? (dark ? "rgba(255,255,255,0.16)" : "rgba(0,0,0,0.08)")
                                   : (dark ? "rgba(255,255,255,0.10)" : "rgba(0,0,0,0.06)"),
                borderRadius: 6, padding: "0 5px", minWidth: 16, textAlign: "center", lineHeight: "15px",
              }}>{o.badge}</span>
            )}
          </button>
        );
      })}
    </div>
  );
}

// ── Popover shell ────────────────────────────────────────────
function HubberPopover({ dark, init = {} }) {
  const tk = window.T(dark);
  const [tab, setTab] = React.useState(init.tab || "reviews");
  const [settingsOpen, setSettingsOpen] = React.useState(!!init.openSettings);
  const density = init.density || 2;
  const sloMode = init.sloMode || "remaining";
  const sloHours = init.sloHours || 4;
  const listState = init.listState || "normal";
  const signedOut = init.signedOut;

  const D = window.HUB_DATA;

  return (
    <div style={{
      width: 420, height: 540, borderRadius: 26, overflow: "hidden",
      background: tk.material,
      backdropFilter: "blur(50px) saturate(180%)", WebkitBackdropFilter: "blur(50px) saturate(180%)",
      border: dark ? "0.5px solid rgba(255,255,255,0.14)" : "0.5px solid rgba(0,0,0,0.10)",
      boxShadow: dark
        ? "0 20px 60px rgba(0,0,0,0.55), 0 0 0 0.5px rgba(0,0,0,0.4)"
        : "0 20px 60px rgba(0,0,0,0.28), 0 0 0 0.5px rgba(0,0,0,0.06)",
      display: "flex", flexDirection: "column", fontFamily: window.HUB_FONT,
      position: "relative",
    }}>
      {signedOut ? (
        <window.SignInScreen dark={dark}/>
      ) : settingsOpen ? (
        <window.SettingsScreen dark={dark} onBack={() => setSettingsOpen(false)} init={init}/>
      ) : (
        <>
          {/* Header */}
          <div style={{ padding: "13px 14px 10px", flexShrink: 0 }}>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 11 }}>
              <div style={{ display: "flex", alignItems: "center", gap: 7 }}>
                <window.SFIcon name="pullRequest" size={15} color={tk.accent} weight={1.7}/>
                <span style={{ fontFamily: window.HUB_FONT_D, fontSize: 15, fontWeight: 600, color: tk.text, letterSpacing: -0.3 }}>
                  Hubber
                </span>
              </div>
              <button onClick={() => setSettingsOpen(true)} title="Settings (⌘,)" style={{
                border: "none", background: "transparent", cursor: "pointer", padding: 4, borderRadius: 6,
                color: tk.text2, lineHeight: 0,
              }}>
                <window.SFIcon name="gear" size={15} color={tk.text2}/>
              </button>
            </div>
            <Segmented dark={dark}
              value={tab} onChange={setTab}
              options={[
                { id: "reviews",  label: "Reviews",  badge: D.incoming.length },
                { id: "outgoing", label: "Outgoing", badge: D.outgoing.filter(p => p.ci === "failing" || p.unresolved > 0).length },
                { id: "drafts",   label: "Drafts",   badge: D.drafts.length },
              ]}/>
          </div>

          {/* Body */}
          <div className="hub-scroll" style={{ flex: 1, overflowY: "auto", display: "flex", flexDirection: "column" }}>
            {tab === "reviews" && <ReviewsScreen dark={dark} density={density} sloMode={sloMode} sloHours={sloHours} listState={listState}/>}
            {tab === "outgoing" && <OutgoingScreen dark={dark} density={density} listState={listState}/>}
            {tab === "drafts" && <DraftsScreen dark={dark} density={density} listState={listState}/>}
          </div>

          {/* Footer */}
          <div style={{
            flexShrink: 0, padding: "7px 14px", borderTop: `0.5px solid ${tk.sep}`,
            display: "flex", alignItems: "center", justifyContent: "space-between",
            fontFamily: window.HUB_FONT, fontSize: 11, color: tk.text2,
          }}>
            <span>Updated 2m ago</span>
            <button title="Refresh (⌘R)" style={{
              border: "none", background: "transparent", cursor: "pointer",
              display: "flex", alignItems: "center", gap: 5, color: tk.text2, padding: "2px 4px", borderRadius: 5,
              fontFamily: window.HUB_FONT, fontSize: 11,
            }}>
              <window.SFIcon name="arrowClockwise" size={12} color={tk.text2} weight={1.6}/>
              <span>Refresh</span>
            </button>
          </div>
        </>
      )}
    </div>
  );
}

// ── Sign-in (signed-out one-off) ─────────────────────────────
function SignInScreen({ dark }) {
  const tk = window.T(dark);
  return (
    <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center",
      textAlign: "center", padding: "36px 40px" }}>
      <div style={{
        width: 64, height: 64, borderRadius: 16, background: dark ? "#0d1117" : "#1f2328",
        display: "flex", alignItems: "center", justifyContent: "center",
        boxShadow: "0 8px 22px rgba(0,0,0,0.30), inset 0 0.5px 0 rgba(255,255,255,0.12)", marginBottom: 20,
      }}>
        <window.SFIcon name="pullRequest" size={30} color="#fff" weight={1.8}/>
      </div>
      <div style={{ fontFamily: window.HUB_FONT_D, fontSize: 19, fontWeight: 650, color: tk.text, letterSpacing: -0.4, marginBottom: 8 }}>
        Welcome to Hubber
      </div>
      <div style={{ fontFamily: window.HUB_FONT, fontSize: 12.5, color: tk.text2, maxWidth: 264, lineHeight: 1.5, marginBottom: 24 }}>
        Keep an eye on your PR reviews, CI, and drafts — right from the menu bar. Sign in to get started.
      </div>
      <button style={{
        display: "flex", alignItems: "center", justifyContent: "center", gap: 8,
        width: "100%", maxWidth: 264, padding: "10px 16px", borderRadius: 9, border: "none", cursor: "pointer",
        background: dark ? "#f6f6f8" : "#1f2328", color: dark ? "#1f2328" : "#fff",
        fontFamily: window.HUB_FONT, fontSize: 13.5, fontWeight: 590, letterSpacing: -0.1,
        boxShadow: "0 1px 3px rgba(0,0,0,0.20)",
      }}>
        <window.SFIcon name="githubMark" size={17} color={dark ? "#1f2328" : "#fff"}/>
        <span>Sign in with GitHub</span>
      </button>
      <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 16, color: tk.text3,
        fontFamily: window.HUB_FONT, fontSize: 11 }}>
        <window.SFIcon name="lock" size={12} color={tk.text3}/>
        <span>Read-only access to your pull requests</span>
      </div>
    </div>
  );
}

// ── Shared tab-body renderer (handles every list state) ──────
function TabBody({ dark, tab, items, listState, RowComp, rowProps = {} }) {
  if (listState === "loading")
    return <div>{[0,1,2,3,4].map((i) => <window.SkeletonRow key={i} dark={dark} last={i === 4}/>)}</div>;
  if (listState === "offline")
    return <window.OfflinePanel dark={dark} tab={tab}/>;
  if (listState === "error")
    return <window.ErrorPanel dark={dark} tab={tab}/>;
  if (listState === "empty" || items.length === 0)
    return <window.EmptyState dark={dark} tab={tab}/>;
  const cached = listState === "offlineCached" || listState === "errorCached";
  return (
    <div>
      {cached && <window.InlineBanner dark={dark} kind={listState === "errorCached" ? "error" : "offline"}/>}
      {items.map((pr, i) => (
        <RowComp key={pr.id} pr={pr} dark={dark} last={i === items.length - 1} {...rowProps}/>
      ))}
    </div>
  );
}

// ── Reviews screen ───────────────────────────────────────────
function ReviewsScreen({ dark, density, sloMode, sloHours, listState }) {
  return <TabBody dark={dark} tab="reviews" items={window.HUB_DATA.incoming} listState={listState}
    RowComp={window.ReviewRow} rowProps={{ density, sloMode, sloHours }}/>;
}

// ── Outgoing screen ──────────────────────────────────────────
function OutgoingScreen({ dark, density, listState }) {
  return <TabBody dark={dark} tab="outgoing" items={window.HUB_DATA.outgoing} listState={listState}
    RowComp={window.OutgoingRow} rowProps={{ density }}/>;
}

// ── Drafts screen ────────────────────────────────────────────
function DraftsScreen({ dark, density, listState }) {
  return <TabBody dark={dark} tab="drafts" items={window.HUB_DATA.drafts} listState={listState}
    RowComp={window.DraftRow} rowProps={{ density }}/>;
}

if (typeof document !== "undefined" && !document.getElementById("hub-scroll-css")) {
  const st = document.createElement("style");
  st.id = "hub-scroll-css";
  st.textContent = `
    .hub-scroll::-webkit-scrollbar { width: 7px; }
    .hub-scroll::-webkit-scrollbar-thumb { background: rgba(140,140,150,0.4); border-radius: 4px; border: 2px solid transparent; background-clip: padding-box; }
    .hub-scroll:hover::-webkit-scrollbar-thumb { background: rgba(140,140,150,0.55); background-clip: padding-box; }
    .hub-scroll::-webkit-scrollbar-track { background: transparent; }
  `;
  document.head.appendChild(st);
}

Object.assign(window, { Segmented, HubberPopover, SignInScreen, TabBody, ReviewsScreen, OutgoingScreen, DraftsScreen });
