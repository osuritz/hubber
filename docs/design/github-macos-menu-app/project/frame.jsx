// Hubber desktop frame — floats the popover over a blurred macOS desktop
// with the menu bar, to communicate real context. The popover's vibrancy
// blurs the wallpaper behind it.

const WALLPAPERS = {
  dawn: "radial-gradient(120% 90% at 20% 0%, #ff9d5c 0%, transparent 52%), radial-gradient(110% 100% at 88% 12%, #c0569e 0%, transparent 56%), radial-gradient(130% 110% at 55% 100%, #3b2d8a 0%, transparent 60%), linear-gradient(165deg, #f0824b 0%, #9c3f86 48%, #2a225e 100%)",
  night: "radial-gradient(120% 90% at 18% 4%, #3a2f6e 0%, transparent 52%), radial-gradient(110% 100% at 85% 14%, #1f4a78 0%, transparent 56%), radial-gradient(130% 110% at 60% 100%, #0a1840 0%, transparent 62%), linear-gradient(170deg, #241a4d 0%, #16204e 52%, #070b22 100%)",
};

// Menu bar with the Hubber status item highlighted/pressed.
function MenuBarStrip({ menubarDark, badgeState, pressed }) {
  const fg = menubarDark ? "rgba(255,255,255,0.95)" : "rgba(255,255,255,0.96)";
  const dim = "rgba(255,255,255,0.9)";
  return (
    <div style={{
      position: "absolute", top: 0, left: 0, right: 0, height: 26,
      background: "rgba(0,0,0,0.16)",
      backdropFilter: "blur(22px) saturate(180%)", WebkitBackdropFilter: "blur(22px) saturate(180%)",
      borderBottom: "0.5px solid rgba(255,255,255,0.10)",
      display: "flex", alignItems: "center", padding: "0 10px", gap: 14,
      fontFamily: window.HUB_FONT, fontSize: 13, color: fg, zIndex: 5,
    }}>
      <svg width="13" height="15" viewBox="0 0 14 16" fill={fg} style={{ opacity: 0.96 }}>
        <path d="M11.6 12.5c-.5 1.2-1.1 2.4-2 2.4-.9 0-1.2-.6-2.3-.6-1.1 0-1.4.6-2.3.6-.9 0-1.5-1.1-2.1-2.3C1.5 10.2.6 6.6 2.5 4.3c.9-1.1 2.1-1.4 3-1.4.9 0 1.6.6 2.4.6.8 0 1.3-.6 2.4-.6.9 0 1.8.5 2.4 1.3-2.1 1.2-1.8 4.2.4 5 .1.1-.6 1.7-1.5 3.3zM8.5 2.7c.4-.5.8-1.3.7-2.1-.7 0-1.5.5-2 1-.4.5-.8 1.3-.7 2.1.8 0 1.6-.5 2-1z"/>
      </svg>
      <span style={{ fontWeight: 600 }}>Hubber</span>
      {["File", "View", "Window", "Help"].map((l) => <span key={l} style={{ color: dim, fontWeight: 400 }}>{l}</span>)}
      <div style={{ flex: 1 }}/>
      <div style={{ display: "flex", alignItems: "center", gap: 13 }}>
        {/* battery */}
        <svg width="22" height="11" viewBox="0 0 22 11" fill="none">
          <rect x="0.5" y="0.5" width="18" height="10" rx="2" stroke={fg} strokeOpacity="0.6"/>
          <rect x="2" y="2" width="13" height="7" rx="1" fill={fg}/>
          <rect x="19.5" y="3.5" width="1.5" height="4" rx="0.5" fill={fg} fillOpacity="0.6"/>
        </svg>
        {/* wifi */}
        <svg width="15" height="11" viewBox="0 0 15 11" fill="none">
          <path d="M7.5 9.6a1 1 0 100-2 1 1 0 000 2z" fill={fg}/>
          <path d="M4 6.4a5 5 0 017 0M1.6 4.2a8.4 8.4 0 0111.8 0" stroke={fg} strokeWidth="1.2" strokeLinecap="round"/>
        </svg>
        {/* control center */}
        <svg width="14" height="13" viewBox="0 0 14 13" fill="none">
          <rect x="1" y="1" width="5" height="5" rx="1.2" fill={fg}/>
          <rect x="8" y="1" width="5" height="5" rx="1.2" stroke={fg} strokeWidth="1.1"/>
          <rect x="1" y="8" width="5" height="3.6" rx="1" stroke={fg} strokeWidth="1.1"/>
          <rect x="8" y="8" width="5" height="3.6" rx="1" fill={fg}/>
        </svg>
        {/* Hubber status item — pressed when popover open */}
        <div style={{
          display: "flex", alignItems: "center", height: 21, padding: "0 7px", borderRadius: 5,
          background: pressed ? "rgba(255,255,255,0.24)" : "transparent",
        }}>
          <window.MenubarIcon state={badgeState} menubarDark={menubarDark} scale={1}/>
        </div>
        <span style={{ fontVariantNumeric: "tabular-nums", color: fg }}>Thu&nbsp;9:42&nbsp;AM</span>
      </div>
    </div>
  );
}

// Full desktop with floating popover.
// props: dark (popover appearance), wallpaper ('dawn'|'night'),
// badgeState, init (popover init).
function DesktopMock({ dark, wallpaper = "dawn", badgeState = "attention", init = {} }) {
  return (
    <div style={{
      position: "absolute", inset: 0, overflow: "hidden",
      background: WALLPAPERS[wallpaper] || WALLPAPERS.dawn,
      fontFamily: window.HUB_FONT,
    }}>
      <MenuBarStrip menubarDark={wallpaper === "night"} badgeState={badgeState} pressed/>
      {/* popover anchored under the status item (upper-right) */}
      <div style={{ position: "absolute", top: 34, right: 18, zIndex: 8 }}>
        {/* arrow */}
        <div style={{ position: "absolute", top: -7, right: 60, width: 16, height: 8, overflow: "hidden", zIndex: 9 }}>
          <div style={{
            position: "absolute", top: 4, left: 3, width: 9, height: 9,
            background: window.T(dark).material, transform: "rotate(45deg)",
            borderLeft: dark ? "0.5px solid rgba(255,255,255,0.14)" : "0.5px solid rgba(0,0,0,0.10)",
            borderTop: dark ? "0.5px solid rgba(255,255,255,0.14)" : "0.5px solid rgba(0,0,0,0.10)",
            backdropFilter: "blur(50px) saturate(180%)", WebkitBackdropFilter: "blur(50px) saturate(180%)",
          }}/>
        </div>
        <window.HubberPopover dark={dark} init={init}/>
      </div>
    </div>
  );
}

Object.assign(window, { DesktopMock, MenuBarStrip, WALLPAPERS });
