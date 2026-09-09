# DesignSystem

SwiftUI port of the FitBuddy design system from `design/` (tokens + atoms in
`design/fb-atoms.jsx`). Screens consume this layer instead of stock SwiftUI
styling so onboarding (#20–24) and the dashboard (#27) stay visually consistent.

## Tokens

| Source | What it provides |
|---|---|
| `DesignSystem.xcassets` | The 17 color values (single source of truth, editable in Xcode). Xcode auto-generates type-safe accessors, so views use `Color.fbBackground`, `.fbInk`, `.fbAccent`, `.fbWarn`, … — no string lookups. |
| `Font+FB.swift` | Type tokens (`.fbStatValue`, `.fbTitle`, `.fbLabel`) + `.fbTabularNumbers()` for figures |
| `FBRadius.swift` | Corner radii: `.control` (14), `.card` (18), `.grouped` (26) |

Colors use a **hybrid** setup: raw values live in the asset catalog, and Xcode's
asset-symbol generation (iOS 17+, well below the 26.0 deployment target)
exposes them as type-safe `Color.fb…` constants. To add or change a color, edit
the color set in `DesignSystem.xcassets`; the `Color.fb…` accessor follows
automatically from the asset name (`FBAccent` → `Color.fbAccent`).

Each color set defines **light + dark appearances**, so the app follows the
system appearance with no call-site changes. The light palette is the warm
off-white canvas (`#F2F1ED`) with white cards; the dark palette uses warm
charcoal surfaces (`#1A1815`) with accents lightened for contrast. Both palettes
are mirrored in the design source (`design/fb-atoms.jsx`: `FB` / `FB_DARK`). The
two accent tokens are `oklch` in the design source; both fall inside the sRGB
gamut, so the catalog stores their exact sRGB values — no Display-P3 needed.

## Atoms

| Component | Use |
|---|---|
| `FBButtonStyle` | `Button("…") { }.buttonStyle(.fb(.primary))` — kinds: `primary`, `accent`, `secondary`, `ghost`, `danger` |
| `FBCard` | White rounded container with hairline border |
| `FBInfoRow` | Title + paragraph with optional leading SF Symbol (consent disclosures, privacy sections) |
| `FBStat` | Labelled stat with large tabular value, optional unit + delta |
| `FBBar` | Labelled progress bar with trailing value (muscle distribution) |
| `FBSpinner` | Indeterminate loading ring |
| `FBToast` | Transient message over the content, dismisses itself (failed pull-to-refresh) |

`FBToast` has no counterpart in `design/fb-atoms.jsx` yet — it came out of
US-10 (#43), after the screen designs were drawn. Port it back when the
prototype next gets touched.

## How screens consume it

Set the screen background to `Color.fbBackground`, group related content in
`FBCard`, use `FBInfoRow`/`FBStat`/`FBBar` for content, and style call-to-action
buttons with `.buttonStyle(.fb(…))`. See `Features/Onboarding/Views/ConsentView.swift`
and `Core/Privacy/PrivacyPolicyView.swift` for a worked example.
