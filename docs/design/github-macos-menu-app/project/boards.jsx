// Hubber design-system spec boards: color tokens, type scale, and component
// state matrices. These are documentation surfaces (not the live app).

const BOARD_BG = "#ffffff";
const BOARD_INK = "#1d1d1f";
const BOARD_SUB = "#86868b";
const BOARD_LINE = "rgba(0,0,0,0.08)";

function BoardCard({ title, subtitle, children, pad = 24, width }) {
  return (
    <div style={{
      width: width || "100%", minHeight: "100%", boxSizing: "border-box",
      background: BOARD_BG, padding: pad, fontFamily: window.HUB_FONT,
      display: "flex", flexDirection: "column",
    }}>
      <div style={{ marginBottom: 18 }}>
        <div style={{ fontFamily: window.HUB_FONT_D, fontSize: 19, fontWeight: 600, color: BOARD_INK, letterSpacing: -0.4 }}>{title}</div>
        {subtitle && <div style={{ fontSize: 12.5, color: BOARD_SUB, marginTop: 3 }}>{subtitle}</div>}
      </div>
      <div style={{ flex: 1 }}>{children}</div>
    </div>
  );
}

// Mini light/dark surface to preview components in context.
function MiniSurface({ dark, children, label, h = "auto", pad = 14 }) {
  const tk = window.T(dark);
  return (
    <div style={{ flex: 1 }}>
      {label && <div style={{ fontSize: 10.5, fontWeight: 600, color: BOARD_SUB, textTransform: "uppercase", letterSpacing: 0.5, marginBottom: 7 }}>{label}</div>}
      <div style={{
        borderRadius: 12, padding: pad, height: h, boxSizing: "border-box",
        background: dark
          ? "radial-gradient(120% 100% at 30% 0%, #4a3a6e 0%, #241a3e 70%)"
          : "radial-gradient(120% 100% at 30% 0%, #fbe3cf 0%, #e7dcf5 70%)",
        border: "0.5px solid rgba(0,0,0,0.06)",
        display: "flex", flexDirection: "column", gap: 10,
      }}>
        <div style={{
          background: tk.material, borderRadius: 10, padding: pad - 4,
          backdropFilter: "blur(40px) saturate(180%)", WebkitBackdropFilter: "blur(40px) saturate(180%)",
          border: dark ? "0.5px solid rgba(255,255,255,0.12)" : "0.5px solid rgba(0,0,0,0.08)",
          display: "flex", flexDirection: "column", gap: 12,
        }}>{children}</div>
      </div>
    </div>
  );
}

// ── Color tokens board ───────────────────────────────────────
function ColorTokensBoard() {
  const TL = window.T(false), TD = window.T(true);
  const groups = [
    { title: "SLO buckets", note: "Pill fill = 12–18% tint · text + dot = solid", items: [
      { name: "slo.green", role: "< 50% budget", l: TL.slo.green.fg, d: TD.slo.green.fg, lt: TL.slo.green.bg, dt: TD.slo.green.bg },
      { name: "slo.amber", role: "50–100%", l: TL.slo.amber.fg, d: TD.slo.amber.fg, lt: TL.slo.amber.bg, dt: TD.slo.amber.bg },
      { name: "slo.red", role: "≥ 100% · overdue", l: TL.slo.red.fg, d: TD.slo.red.fg, lt: TL.slo.red.bg, dt: TD.slo.red.bg },
    ]},
    { title: "CI status", note: "running is neutral — not an action signal", items: [
      { name: "ci.passing", role: "checkmark", l: TL.ci.passing, d: TD.ci.passing },
      { name: "ci.failing", role: "cross", l: TL.ci.failing, d: TD.ci.failing },
      { name: "ci.running", role: "spinner", l: TL.ci.running, d: TD.ci.running },
      { name: "ci.pending", role: "clock", l: TL.ci.pending, d: TD.ci.pending },
    ]},
    { title: "Reviewer state dots", note: "8pt dot, bottom-right of avatar", items: [
      { name: "rv.approved", role: "filled", l: TL.rv.approved, d: TD.rv.approved },
      { name: "rv.changes_requested", role: "filled", l: TL.rv.changes_requested, d: TD.rv.changes_requested },
      { name: "rv.commented", role: "filled", l: TL.rv.commented, d: TD.rv.commented },
      { name: "rv.pending", role: "hollow ring", l: TL.rv.pending, d: TD.rv.pending, ring: true },
    ]},
    { title: "System", note: null, items: [
      { name: "accent", role: "controls, links", l: TL.accent, d: TD.accent },
      { name: "error", role: "load failures", l: TL.error, d: TD.error },
      { name: "signalAccent", role: "row left-edge", l: TL.signalAccent, d: TD.signalAccent },
    ]},
  ];
  return (
    <BoardCard title="Color tokens" subtitle="Every signal has a light + dark value. Maps 1:1 to SwiftUI Color assets. All color carries a non-color cue (icon, dot, or text label).">
      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "22px 32px" }}>
        {groups.map((g) => (
          <div key={g.title}>
            <div style={{ fontSize: 12.5, fontWeight: 600, color: BOARD_INK, marginBottom: 2 }}>{g.title}</div>
            {g.note && <div style={{ fontSize: 10.5, color: BOARD_SUB, marginBottom: 9 }}>{g.note}</div>}
            <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
              {g.items.map((it) => (
                <div key={it.name} style={{ display: "flex", alignItems: "center", gap: 10 }}>
                  <Swatch color={it.l} tint={it.lt} ring={it.ring}/>
                  <Swatch color={it.d} tint={it.dt} ring={it.ring} dark/>
                  <div style={{ minWidth: 0, flex: 1 }}>
                    <div style={{ fontFamily: window.HUB_MONO, fontSize: 11, color: BOARD_INK, fontWeight: 500 }}>{it.name}</div>
                    <div style={{ fontSize: 10.5, color: BOARD_SUB }}>{it.role}</div>
                  </div>
                  <div style={{ fontFamily: window.HUB_MONO, fontSize: 10, color: BOARD_SUB, textAlign: "right" }}>
                    <div>{it.l}</div><div>{it.d}</div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
    </BoardCard>
  );
}

function Swatch({ color, tint, ring, dark }) {
  return (
    <div style={{
      width: 30, height: 30, borderRadius: 7, flexShrink: 0,
      background: tint || (dark ? "#241a3e" : "#f0eef5"),
      display: "flex", alignItems: "center", justifyContent: "center",
      border: "0.5px solid rgba(0,0,0,0.08)",
    }} title={dark ? "Dark" : "Light"}>
      <div style={{
        width: 16, height: 16, borderRadius: "50%",
        background: ring ? "transparent" : color,
        border: ring ? `2px solid ${color}` : "0.5px solid rgba(0,0,0,0.12)",
      }}/>
    </div>
  );
}

// ── Type scale board ─────────────────────────────────────────
function TypeScaleBoard() {
  const TY = window.TYPE;
  const order = ["title", "secondary", "sloPill", "ciDetail", "log", "section", "footer"];
  const samples = {
    title: "Idempotency keys for refund retries",
    secondary: "acme/payments-api · marisol",
    sloPill: "2h 14m left",
    ciDetail: "9/11 checks passing",
    log: "09:41:48 · Refresh complete",
    section: "Incoming Reviews",
    footer: "Updated 2m ago",
  };
  return (
    <BoardCard title="Typography" subtitle="SF Pro Text / Display and SF Mono only. No custom typefaces.">
      <div style={{ display: "flex", flexDirection: "column" }}>
        {order.map((k, i) => {
          const t = TY[k];
          return (
            <div key={k} style={{
              display: "flex", alignItems: "baseline", gap: 20, padding: "13px 0",
              borderBottom: i === order.length - 1 ? "none" : `0.5px solid ${BOARD_LINE}`,
            }}>
              <div style={{ width: 116, flexShrink: 0 }}>
                <div style={{ fontSize: 12, fontWeight: 600, color: BOARD_INK }}>{t.label}</div>
                <div style={{ fontSize: 10.5, color: BOARD_SUB, marginTop: 2 }}>{t.spec}</div>
              </div>
              <div style={{
                flex: 1,
                fontFamily: t.font, fontSize: t.size, fontWeight: t.weight, color: BOARD_INK,
                textTransform: k === "section" ? "uppercase" : "none",
                letterSpacing: k === "section" ? 0.4 : (t.font === window.HUB_MONO ? 0 : -0.1),
                fontVariantNumeric: t.mono ? "tabular-nums" : "normal",
              }}>{samples[k]}</div>
            </div>
          );
        })}
      </div>
    </BoardCard>
  );
}

// ── Components board ─────────────────────────────────────────
function ComponentsBoard() {
  return (
    <BoardCard title="Core components" subtitle="SLO pill, CI badge, and avatar — shown in light and dark vibrancy context.">
      <div style={{ display: "flex", flexDirection: "column", gap: 22 }}>
        {/* SLO pill */}
        <div>
          <CompLabel>SLO pill — three states · dot + monospaced-digit label</CompLabel>
          <div style={{ display: "flex", gap: 16 }}>
            {[false, true].map((d) => (
              <MiniSurface key={String(d)} dark={d} label={d ? "Dark" : "Light"}>
                <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
                  <window.SLOPill status="green" text="2h 14m left" dark={d}/>
                  <window.SLOPill status="amber" text="48m left" dark={d}/>
                  <window.SLOPill status="red" text="1h overdue" dark={d}/>
                </div>
              </MiniSurface>
            ))}
          </div>
        </div>
        {/* CI badge */}
        <div>
          <CompLabel>CI badge — four states · passing & failing are the action signals</CompLabel>
          <div style={{ display: "flex", gap: 16 }}>
            {[false, true].map((d) => (
              <MiniSurface key={String(d)} dark={d} label={d ? "Dark" : "Light"}>
                <div style={{ display: "flex", gap: 22, alignItems: "center" }}>
                  {["passing", "failing", "running", "pending"].map((s) => (
                    <div key={s} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
                      <window.CIBadge status={s} size={24} dark={d}/>
                      <span style={{ fontSize: 10, color: window.T(d).text2, fontFamily: window.HUB_FONT }}>{s}</span>
                    </div>
                  ))}
                </div>
              </MiniSurface>
            ))}
          </div>
        </div>
        {/* Avatar */}
        <div>
          <CompLabel>Avatar — 36 / 24 / 20pt · initials fallback · reviewer state dots</CompLabel>
          <div style={{ display: "flex", gap: 16 }}>
            {[false, true].map((d) => (
              <MiniSurface key={String(d)} dark={d} label={d ? "Dark" : "Light"}>
                <div style={{ display: "flex", gap: 18, alignItems: "center", flexWrap: "wrap" }}>
                  <window.Avatar user={{ avatar: "MR", color: "#8a8fe0" }} size={36} dark={d}/>
                  <window.Avatar user={{ avatar: "KS", color: "#d6699a" }} size={24} dark={d}/>
                  <window.Avatar user={{ avatar: "TL", color: "#5fb98a" }} size={20} dark={d}/>
                  <div style={{ width: 1, height: 28, background: window.T(d).sep }}/>
                  {["approved", "changes_requested", "commented", "pending"].map((st) => (
                    <window.Avatar key={st} user={{ avatar: "IF", color: "#c98ad6" }} size={24} state={st} dark={d}/>
                  ))}
                </div>
              </MiniSurface>
            ))}
          </div>
        </div>
      </div>
    </BoardCard>
  );
}

function CompLabel({ children }) {
  return <div style={{ fontSize: 11.5, fontWeight: 600, color: BOARD_INK, marginBottom: 11 }}>{children}</div>;
}

// ── Row spec board (each row type, all sub-states) ───────────
function RowSpecBoard({ dark }) {
  const tk = window.T(dark);
  const D = window.HUB_DATA;
  return (
    <div style={{
      position: "absolute", inset: 0, padding: 24, boxSizing: "border-box",
      background: dark
        ? "radial-gradient(120% 100% at 30% 0%, #3a2d5e 0%, #1a1430 70%)"
        : "radial-gradient(120% 100% at 30% 0%, #fbe3cf 0%, #e7dcf5 70%)",
      fontFamily: window.HUB_FONT, overflow: "auto",
    }} className="hub-scroll">
      <div style={{ fontFamily: window.HUB_FONT_D, fontSize: 18, fontWeight: 600, color: tk.text, letterSpacing: -0.3, marginBottom: 4 }}>
        Row components — {dark ? "Dark" : "Light"}
      </div>
      <div style={{ fontSize: 12, color: tk.text2, marginBottom: 18 }}>Normal density. Each row type with its sub-states.</div>

      <RowSpecGroup label="Reviews — SLO green / amber / red" tk={tk}>
        {D.incoming.slice(0, 1).map((p) => <window.ReviewRow key={p.id} pr={p} dark={dark}/>)}
        {D.incoming.slice(2, 3).map((p) => <window.ReviewRow key={p.id} pr={p} dark={dark}/>)}
        {D.incoming.slice(4, 5).map((p) => <window.ReviewRow key={p.id} pr={p} dark={dark} last/>)}
      </RowSpecGroup>

      <RowSpecGroup label="Outgoing — failing (signal) / passing / running" tk={tk}>
        {D.outgoing.slice(0, 1).map((p) => <window.OutgoingRow key={p.id} pr={p} dark={dark}/>)}
        {D.outgoing.slice(3, 4).map((p) => <window.OutgoingRow key={p.id} pr={p} dark={dark}/>)}
        {D.outgoing.slice(2, 3).map((p) => <window.OutgoingRow key={p.id} pr={p} dark={dark} last/>)}
      </RowSpecGroup>

      <RowSpecGroup label="Drafts — recently updated / stale" tk={tk}>
        {D.drafts.slice(0, 1).map((p) => <window.DraftRow key={p.id} pr={p} dark={dark}/>)}
        {D.drafts.slice(2, 3).map((p) => <window.DraftRow key={p.id} pr={p} dark={dark} last/>)}
      </RowSpecGroup>
    </div>
  );
}

function RowSpecGroup({ label, tk, children }) {
  return (
    <div style={{ marginBottom: 18 }}>
      <div style={{ fontSize: 10.5, fontWeight: 600, color: tk.text2, textTransform: "uppercase", letterSpacing: 0.5, marginBottom: 8, paddingLeft: 2 }}>{label}</div>
      <div style={{
        background: tk.material, borderRadius: 12, overflow: "hidden",
        backdropFilter: "blur(40px) saturate(180%)", WebkitBackdropFilter: "blur(40px) saturate(180%)",
        border: tk.dark ? "0.5px solid rgba(255,255,255,0.12)" : "0.5px solid rgba(0,0,0,0.08)",
      }}>{children}</div>
    </div>
  );
}

// ── Density board ────────────────────────────────────────────
function DensityBoard({ dark }) {
  const tk = window.T(dark);
  const pr = window.HUB_DATA.incoming[2];
  const cols = [{ d: 1, label: "Compact" }, { d: 2, label: "Default" }, { d: 3, label: "Spacious" }];
  return (
    <div style={{
      position: "absolute", inset: 0, padding: 24, boxSizing: "border-box",
      background: dark
        ? "radial-gradient(120% 100% at 30% 0%, #3a2d5e 0%, #1a1430 70%)"
        : "radial-gradient(120% 100% at 30% 0%, #fbe3cf 0%, #e7dcf5 70%)",
      fontFamily: window.HUB_FONT, display: "flex", flexDirection: "column",
    }}>
      <div style={{ fontFamily: window.HUB_FONT_D, fontSize: 18, fontWeight: 600, color: tk.text, letterSpacing: -0.3, marginBottom: 4 }}>
        Row density — {dark ? "Dark" : "Light"}
      </div>
      <div style={{ fontSize: 12, color: tk.text2, marginBottom: 18 }}>Compact drops the secondary line. Spacious enlarges the avatar and adds breathing room.</div>
      <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
        {cols.map((c) => (
          <div key={c.d}>
            <div style={{ fontSize: 10.5, fontWeight: 600, color: tk.text2, textTransform: "uppercase", letterSpacing: 0.5, marginBottom: 8, paddingLeft: 2 }}>{c.label}</div>
            <div style={{
              background: tk.material, borderRadius: 12, overflow: "hidden",
              backdropFilter: "blur(40px) saturate(180%)", WebkitBackdropFilter: "blur(40px) saturate(180%)",
              border: tk.dark ? "0.5px solid rgba(255,255,255,0.12)" : "0.5px solid rgba(0,0,0,0.08)",
            }}>
              <window.ReviewRow pr={window.HUB_DATA.incoming[0]} density={c.d} dark={dark}/>
              <window.ReviewRow pr={pr} density={c.d} dark={dark} last/>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Menubar icon states board ────────────────────────────────
function MenubarStatesBoard() {
  const rows = [
    { state: "normal", label: "Normal", note: "no pending attention" },
    { state: "attention", label: "Attention", note: "badge dot · review needs you" },
    { state: "refreshing", label: "Refreshing", note: "subtle spin during fetch" },
  ];
  return (
    <BoardCard title="Menubar icon" subtitle="arrow.triangle.pull · three states, shown at 2× on light and dark menu bars.">
      <div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
        {rows.map((r) => (
          <div key={r.state} style={{ display: "flex", alignItems: "center", gap: 16 }}>
            <div style={{ width: 150, flexShrink: 0 }}>
              <div style={{ fontSize: 12.5, fontWeight: 600, color: BOARD_INK }}>{r.label}</div>
              <div style={{ fontSize: 10.5, color: BOARD_SUB, marginTop: 2 }}>{r.note}</div>
            </div>
            <MenubarChip menubarDark={false} state={r.state}/>
            <MenubarChip menubarDark={true} state={r.state}/>
          </div>
        ))}
      </div>
    </BoardCard>
  );
}

function MenubarChip({ menubarDark, state }) {
  return (
    <div style={{
      flex: 1, height: 46, borderRadius: 9, display: "flex", alignItems: "center", justifyContent: "flex-end",
      padding: "0 18px", overflow: "hidden",
      background: menubarDark
        ? "linear-gradient(90deg, #3a2a5e, #1f1838)"
        : "linear-gradient(90deg, #ffd0a8, #f0b8d4)",
    }}>
      <div style={{ display: "flex", alignItems: "center", gap: 16, transform: "scale(1)" }}>
        <window.MenubarIcon state={state} menubarDark={menubarDark} scale={1.55}/>
      </div>
    </div>
  );
}

Object.assign(window, {
  BoardCard, ColorTokensBoard, TypeScaleBoard, ComponentsBoard,
  RowSpecBoard, DensityBoard, MenubarStatesBoard,
});
