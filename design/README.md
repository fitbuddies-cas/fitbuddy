# FitBuddy · iOS Screens & Interactive Prototype

High-fidelity iOS screen designs for the three Must-Have user stories from `REQUIREMENTS_PO.md`:

- **US-1** · API-Key sicher speichern (5 screen states)
- **US-2** · 90 Tage Trainingsdaten im Dashboard (4 screen states)
- **US-3** · AI-Analyse auf Knopfdruck (6 screen states)
- **Interactive Prototype** — clickable full-flow walkthrough

## Run it locally

Open `index.html` directly in a modern browser. No build step, no install. All dependencies (React, Babel) are loaded via CDN.

## Continue this design in Claude

1. Open Claude → start a new design project → connect GitHub.
2. Import this folder (`design/`) — **the whole folder, not single files**. The HTML references its sibling `.jsx` files relatively.
3. Open `index.html` in the preview. Everything renders.
4. Edit screens directly, or ask Claude to add states/sections.

## File map

| File | Role |
|---|---|
| `index.html` | Entry. Loads scripts and sets up the DesignCanvas. |
| `fb-atoms.jsx` | FitBuddy design tokens (colors, type) + reusable primitives (`FBButton`, `FBCard`, `FBStat`, `FBBar`, `FBSpinner`). |
| `fb-screens.jsx` | All 13 screen components (`FBWelcomeScreen`, `FBKeyEntryScreen`, `FBDashboardScreen`, `FBWorkoutDetailScreen`, `FBAnalyzeLoadingScreen`, `FBAnalysisResultScreen`). |
| `ios-frame.jsx` | iOS 26 device frame (status bar, dynamic island, keyboard, home indicator). |
| `design-canvas.jsx` | Pan/zoom canvas wrapper. Sections + artboards. |

## Design system

- **Background:** warm off-white `#F2F1ED` canvas, white cards
- **Ink:** near-black `#0E0E0E` foreground, `#3C3C43` secondary
- **Accent (Progress):** `oklch(0.62 0.14 150)` — training green
- **Accent (Recovery / Warn):** `oklch(0.66 0.16 55)` — warm orange
- **Type:** SF Pro / system-ui, tabular nums on all numbers
- **Radii:** 14 (controls), 18 (cards), 26 (grouped lists)

## Editing rules

- Keep all files at the same flat level inside this folder — `index.html` loads scripts as `src="fb-atoms.jsx"`.
- Don't rename files without updating the `<script>` tags in `index.html`.
- Each screen component is pure (props in, JSX out). Add a new screen by writing a new function in `fb-screens.jsx`, exposing it on `window`, registering it in the `SCREENS` map in `index.html`.

## Acceptance criteria coverage

| AC | Where it shows |
|---|---|
| US-1 AC1 (Keychain + validate) | 1.2 → 1.4 with lock-icon storage note |
| US-1 AC3 (HTTP 401 → re-onboard) | 1.5 invalid-key screen |
| US-2 AC1 (volume, avg/week, muscle dist, sessions) | 2.1 full dashboard |
| US-2 AC2 (cached + sync timestamp) | 2.2 offline banner |
| US-2 AC3 (no data text) | 2.3 empty state |
| US-2 AC1 (Session-Drill-down: Übungen mit Sätzen) | 2.4 workout detail |
| US-3 AC1 (spinner; cancel after 30 s) | 3.2 → 3.3 |
| US-3 AC2/AC7 (concrete kg value) | 3.4 Bench 60 → 62.5 kg, Squat 80 → 82.5 kg |
| US-3 AC4 (≥2 muscle groups) | 3.4 covers Chest + Legs |
| US-3 AC6 (recovery if ≥6/7 days) | 3.5 recovery variant |
| US-3 AC8 (imbalance) | 3.4 Chest 3×/wk vs Legs 1×/wk card |
| US-3 Rate-Limit-Countdown | 3.6 (Helpful-/Not-helpful-Buttons aus 3.4 / 3.5 sind entfernt) |
| US-3 AC11 (History, Swipe-Delete) | noch kein Mock — Screen ist mit #117 dazugekommen |

---

*CAS ADAI 2026 · Modul 3 · iteration 1*
