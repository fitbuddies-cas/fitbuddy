# DesignSystem

SwiftUI port of the FitBuddy design system from `design/` (tokens + atoms in
`design/fb-atoms.jsx`). Screens consume this layer instead of stock SwiftUI
styling so onboarding (#20–24) and the dashboard (#27) stay visually consistent.

## Tokens

| File | What it provides |
|---|---|
| `Color+FB.swift` | Color tokens as `Color.fb…` (e.g. `.fbBackground`, `.fbInk`, `.fbAccent`, `.fbWarn`) + a `Color(hex:)` initializer |
| `Font+FB.swift` | Type tokens (`.fbStatValue`, `.fbTitle`, `.fbLabel`) + `.fbTabularNumbers()` for figures |
| `FBRadius.swift` | Corner radii: `.control` (14), `.card` (18), `.grouped` (26) |

v0 uses a **fixed light palette** (warm off-white canvas `#F2F1ED`, white cards)
so the app renders identically in light and dark — the prototype is light-only.
The two accent tokens are `oklch` in the design source; here they are the sRGB
equivalents (`fbAccent` ≈ `#399D57`, `fbWarn` ≈ `#DA720D`).

## Atoms

| Component | Use |
|---|---|
| `FBButtonStyle` | `Button("…") { }.buttonStyle(.fb(.primary))` — kinds: `primary`, `accent`, `secondary`, `ghost`, `danger` |
| `FBCard` | White rounded container with hairline border |
| `FBInfoRow` | Title + paragraph with optional leading SF Symbol (consent disclosures, privacy sections) |
| `FBStat` | Labelled stat with large tabular value, optional unit + delta |
| `FBBar` | Labelled progress bar with trailing value (muscle distribution) |
| `FBSpinner` | Indeterminate loading ring |

## How screens consume it

Set the screen background to `Color.fbBackground`, group related content in
`FBCard`, use `FBInfoRow`/`FBStat`/`FBBar` for content, and style call-to-action
buttons with `.buttonStyle(.fb(…))`. See `Features/Onboarding/Views/ConsentView.swift`
and `PrivacyPolicyView.swift` for a worked example.
