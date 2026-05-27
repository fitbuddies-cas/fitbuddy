# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Status

**FitBuddy** is a CAS ADAI 2026 (BFH Biel) Proof of Concept — currently a **planning/documentation repository only**. There is no iOS Swift code yet. The app to be built is a native iOS (SwiftUI) training assistant aggregating Hevy API data and delivering on-demand AI recommendations via Claude API.

## Repository Contents

| File | Purpose |
|---|---|
| `README.md` | Project overview and feature summary |
| `PROJECT.md` | Scope, personas (Marcus / Jana), risks, 4-week sprint plan |
| `REQUIREMENTS.md` | 12 user stories with acceptance criteria (MoSCoW v5) |
| `ARCHITECTURE.md` | System design, Swift data model, Connector interface, ADRs |
| `presentation.html` | HTML slide deck (keyboard-navigable, open in browser) |
`Kursdokumente/` is git-ignored (course materials).

## Key Architecture Decisions (from ARCHITECTURE.md)

- **No backend/proxy in PoC:** Claude API key lives in iOS Keychain; direct device-to-API calls only. Revisit before v1.0 → migrate to AWS Bedrock `eu-central-1` (Frankfurt) for nDSG compliance.
- **Native SwiftUI only** (not React Native/Flutter): required for `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` Keychain semantics.
- **`FitnessConnector` protocol** defined before any connector: Hevy is the first implementation; Strava comes in v1.1 without refactor.
- **English-only** is a Definition of Done criterion, not a feature — all UI strings, error messages, and the system prompt must be in English.

## Normalized Data Model (Swift)

```swift
protocol FitnessConnector {
    func connect(credentials: ConnectorCredentials) async throws
    func validate() async throws -> Bool
    func fetchActivities(since: Date) async throws -> [Activity]
    func disconnect()
}

struct Activity {
    let id: String
    let source: DataSource        // .hevy, .strava
    let type: ActivityType        // .strength, .cardio
    let startedAt: Date
    let durationMinutes: Int
    let exercises: [Exercise]?
    let distanceKm: Double?
}
```

Keychain keys: `fitbuddy.hevy.apikey`, `fitbuddy.claude.apikey`, `fitbuddy.strava.token`.

## MVP Must-Haves (Sprint 1–4)

| ID | Story | Sprint |
|---|---|---|
| US-1 | Hevy + Claude API keys in iOS Keychain | 1 |
| US-2 | 90-day training dashboard (volume, muscle load, offline cache) | 2 |
| US-3 | On-demand AI analysis via Claude API (9 ACs) | 3 |
| US-4 | 3-step onboarding incl. nDSG consent screen | 4 |

US-4 AC4 requires an explicit consent screen: training data (health data per nDSG Art. 5 lit. c) transferred to Anthropic Inc. (USA) — no Swiss adequacy decision; lawful basis is the AVV/DPA signed by the FitBuddy team with Anthropic.

## Won't-Have in PoC

- Push notifications (US-11)
- Writing AI suggestions back to Hevy (US-12) — requires Hevy PRO, UX unresolved
- i18n framework
- App Store distribution (TestFlight/sideload only)

## Open Decisions (resolve before architecture sprint)

- Apple Health (sleep, HRV, resting HR) — IN or OUT of scope?
- HTTP 401 handling: hard logout (recommended) or soft banner?
- Split US-3 and US-5 into child stories before sprint planning
