// Hubber design tokens — the single source of truth.
// Every mock and every spec board reads from T(dark). macOS-faithful,
// mapped to the SwiftUI Color assets the engineers will create.

const FONT = '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif';
const FONT_D = '-apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", sans-serif';
const MONO = '"SF Mono", ui-monospace, "JetBrains Mono", Menlo, Consolas, monospace';

// Raw semantic palette with light/dark pairs. fg = text+icon, dot = signal
// dot, bg = tint fill, border = hairline.
const PALETTE = {
  // SLO buckets
  sloGreen: { light: { fg: "#248A3D", bg: "rgba(52,199,89,0.13)",  border: "rgba(52,199,89,0.30)" },
              dark:  { fg: "#30D158", bg: "rgba(48,209,88,0.16)",  border: "rgba(48,209,88,0.34)" } },
  sloAmber: { light: { fg: "#9A5B00", bg: "rgba(255,149,0,0.14)",  border: "rgba(255,149,0,0.32)" },
              dark:  { fg: "#FFA00A", bg: "rgba(255,159,10,0.16)", border: "rgba(255,159,10,0.34)" } },
  sloRed:   { light: { fg: "#D70015", bg: "rgba(255,59,48,0.12)",  border: "rgba(255,59,48,0.30)" },
              dark:  { fg: "#FF6961", bg: "rgba(255,69,58,0.18)",  border: "rgba(255,69,58,0.36)" } },
  // CI states
  ciPassing: { light: "#248A3D", dark: "#30D158" },
  ciFailing: { light: "#D70015", dark: "#FF453A" },
  ciRunning: { light: "#8E8E93", dark: "#98989D" }, // neutral — not an action signal
  ciPending: { light: "#8E8E93", dark: "#98989D" },
  // Reviewer state dots
  rvApproved: { light: "#34C759", dark: "#30D158" },
  rvChanges:  { light: "#FF3B30", dark: "#FF453A" },
  rvComment:  { light: "#007AFF", dark: "#0A84FF" },
  rvPending:  { light: "#C7C7CC", dark: "#5A5A5E" }, // hollow ring
  // System
  accent:  { light: "#007AFF", dark: "#0A84FF" },
  error:   { light: "#D70015", dark: "#FF453A" },
  // Action-signal row treatment (failing CI / unresolved threads)
  signalTint:   { light: "rgba(255,59,48,0.045)", dark: "rgba(255,69,58,0.07)" },
  signalAccent: { light: "#FF3B30", dark: "#FF453A" },
};

// Resolve full token set for a mode.
function T(dark) {
  const m = dark ? "dark" : "light";
  const pick = (k) => PALETTE[k][m];
  return {
    dark,
    font: FONT, fontD: FONT_D, mono: MONO,
    // Vibrancy material — the .popover layer (translucent, sits on blur)
    material: dark ? "rgba(38,38,40,0.62)" : "rgba(246,246,248,0.68)",
    materialSolid: dark ? "#262628" : "#f6f6f8", // for spec chips needing opacity
    // Text
    text:      dark ? "rgba(255,255,255,0.92)" : "rgba(0,0,0,0.85)",
    text2:     dark ? "rgba(235,235,245,0.58)" : "rgba(60,60,67,0.56)",
    text3:     dark ? "rgba(235,235,245,0.32)" : "rgba(60,60,67,0.32)",
    // Lines + fills
    sep:       dark ? "rgba(255,255,255,0.10)" : "rgba(0,0,0,0.08)",
    sepStrong: dark ? "rgba(255,255,255,0.14)" : "rgba(0,0,0,0.12)",
    fill:      dark ? "rgba(255,255,255,0.06)" : "rgba(0,0,0,0.035)",
    fillHover: dark ? "rgba(255,255,255,0.09)" : "rgba(0,0,0,0.05)",
    // Controls
    ctrlTrack:  dark ? "rgba(255,255,255,0.08)" : "rgba(0,0,0,0.055)",
    ctrlThumb:  dark ? "rgba(120,120,128,0.44)" : "#ffffff",
    ctrlShadow: dark ? "inset 0 0.5px 0 rgba(255,255,255,0.16)" : "0 1px 2px rgba(0,0,0,0.10), 0 0 0 0.5px rgba(0,0,0,0.04)",
    // Semantic
    accent: pick("accent"),
    error: pick("error"),
    slo: { green: pick("sloGreen"), amber: pick("sloAmber"), red: pick("sloRed") },
    ci: { passing: pick("ciPassing"), failing: pick("ciFailing"), running: pick("ciRunning"), pending: pick("ciPending") },
    rv: { approved: pick("rvApproved"), changes_requested: pick("rvChanges"), commented: pick("rvComment"), pending: pick("rvPending") },
    signalTint: pick("signalTint"),
    signalAccent: pick("signalAccent"),
  };
}

// Type scale — every SF Pro role used in the app.
const TYPE = {
  title:    { size: 13, weight: 500, font: FONT,  label: "PR title",      spec: "13 / Medium" },
  secondary:{ size: 11, weight: 400, font: FONT,  label: "Secondary line", spec: "11 / Regular" },
  sloPill:  { size: 11, weight: 590, font: FONT,  label: "SLO pill",       spec: "11 / Medium · monospaced digits", mono: true },
  ciDetail: { size: 11, weight: 400, font: FONT,  label: "CI detail",      spec: "11 / Regular" },
  log:      { size: 11, weight: 400, font: MONO,  label: "Log viewer",     spec: "11 / SF Mono" },
  section:  { size: 11, weight: 600, font: FONT,  label: "Section header",  spec: "11 / Medium · UPPERCASE · +0.4 tracking" },
  footer:   { size: 11, weight: 400, font: FONT,  label: "Footer",         spec: "11 / Regular" },
};

Object.assign(window, { T, TYPE, PALETTE, HUB_FONT: FONT, HUB_FONT_D: FONT_D, HUB_MONO: MONO });
