# FitBuddy

> "Ein AI-gestützter Trainingsassistent für Kraft- und Ausdauersportler, der Hevy-Kraftdaten und Strava-Cardio-Daten zusammenführt und daraus personalisierte Übersichten und Progressions-Empfehlungen generiert."

FitBuddy is a native iOS app that aggregates training data from fitness apps into a single dashboard and delivers on-demand AI-powered progression recommendations.

**Status:** Proof of Concept — CAS Application Development with AI (ADAI) 2026, BFH Biel

---

## Features (PoC)

- **Secure API-Key storage** — Hevy and Claude API keys stored exclusively in iOS Keychain
- **30-day training dashboard** — session overview, total volume, muscle load distribution
- **AI analysis on demand** — one tap to get a concrete, plain-language progression recommendation via Claude API
- **3-step onboarding** — designed for non-technical users (no documentation needed)

## Data Sources

| Source | Status |
|---|---|
| Hevy (strength) | PoC |
| Strava (cardio) | Planned v1.1 |
| Apple Health | Under evaluation |

## Documentation

| File | Content |
|---|---|
| [PROJECT.md](PROJECT.md) | Project scope, personas, risks, sprint plan |
| [REQUIREMENTS.md](REQUIREMENTS.md) | All 12 user stories with acceptance criteria (MoSCoW v5) |
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design, tech stack, ADRs, data model |

## Architecture

Native iOS (SwiftUI) — all API keys stay on-device in the iOS Keychain. No backend. Direct calls to Hevy and Claude APIs.

```
iOS App → Connector Layer → Hevy API
                         → Claude API (AI analysis)
                         → Strava API (v1.1)
```

## MoSCoW — Must Have (MVP)

| ID | User Story |
|---|---|
| US-1 | API-Key sicher speichern |
| US-2 | 30 Tage Trainingsdaten im Dashboard |
| US-3 | AI-Analyse auf Knopfdruck |
| US-4 | Onboarding in 3 Schritten |

## Team

CAS ADAI 2026 · BFH Biel · Dozent: Ilja Rasin
