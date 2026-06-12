# FitBuddy — Sprintplanung & Roadmap

*PoC (v0) · CAS ADAI 2026 · BFH Biel*
*Stand: 10.06.2026 · Sprintlänge: 2 Wochen*

---

## Roadmap

| Sprint | Zeitraum | Ziel | US | Status |
|--------|----------|------|----|--------|
| **Sprint 1** | 10.06. – 23.06.2026 | Foundation & Onboarding | US-1, US-4 | 🟡 Aktuell |
| **Sprint 2** | 24.06. – 07.07.2026 | Dashboard (90 Tage Daten) | US-2 | ⬜ Geplant |
| **Sprint 3** | 08.07. – 21.07.2026 | AI-Analyse auf Knopfdruck | US-3 | ⬜ Geplant |
| **Sprint 4** | 22.07. – 04.08.2026 | Should-Features | US-5 (partial), US-6, US-7 | ⬜ Geplant |
| **Sprint 5** | 05.08. – 18.08.2026 | Could-Features & TestFlight | US-8, US-9, US-10 | ⬜ Geplant |
| **TestFlight** | ab 19.08.2026 | Externe Tester (CAS-Teilnehmer) | — | ⬜ Geplant |

**Won't Have (PoC):** US-11 (Push-Notifications), US-12 (Write-back nach Hevy) — bewusst ausgeschlossen, frühestens v1.

---

## Sprint 1 — Foundation & Onboarding

**Zeitraum:** 10.06.2026 – 23.06.2026
**Ziel:** Lauffähige App mit funktionierendem 3-Schritt-Onboarding: Hevy-Key validiert, Claude-Key optional, Consent gespeichert — plus architektonisches Fundament für alle Folge-Sprints.

### Sprint-1-Ziele (Definition of Done)

Eine frische App-Installation durchläuft den kompletten Onboarding-Flow:
1. Consent-Screen lesen und bestätigen (Datum + Version in Keychain gespeichert)
2. Hevy API-Key eingeben → sofort validiert via `GET /workouts` → HTTP 200 führt zum nächsten Schritt
3. Claude API-Key eingeben **oder** überspringen
4. App landet auf dem (noch leeren) Dashboard
5. Beim nächsten Kaltstart: kein Onboarding mehr, direkt zum Dashboard (Keychain-Key gültig)
6. Bei HTTP 401: Key gelöscht, zurück zum Onboarding mit Fehlermeldung

### Voraussetzungen (vor Sprint-Start auflösen)

| # | Offene Frage | Entscheid nötig bis | Quelle |
|---|---|---|---|
| W-5 | **Apple HealthKit IN oder OUT?** Blockiert Finalisierung des `Activity`-Modells und `FitnessConnector`-Protocols. Empfehlung: OUT für PoC. | Sprint-Start | ARCHITECTURE.md |
| — | **Xcode-Projekt anlegen** (Targets, Bundle-ID, Signing, Folder-Struktur `Views/` `ViewModels/` `Services/` `Models/`) | Tag 1 | CLAUDE.md |

### Issues in Sprint 1

| # | Titel | US | Aufwand | Abhängigkeit |
|---|---|---|---|---|
| [#33](https://github.com/fitbuddies-cas/fitbuddy/issues/33) | FitnessConnector-Protocol + normalisiertes Activity-Datenmodell | US-5 (Architektur) | ~2h | Erst W-5 klären |
| [#19](https://github.com/fitbuddies-cas/fitbuddy/issues/19) | KeychainService implementieren | US-1 | ~4h | — |
| [#23](https://github.com/fitbuddies-cas/fitbuddy/issues/23) | OnboardingViewModel + 3-Schritt-Navigation | US-4 | ~4h | #19 |
| [#20](https://github.com/fitbuddies-cas/fitbuddy/issues/20) | Consent-Screen UI + Persistence | US-4 | ~3h | #19, #23 |
| [#21](https://github.com/fitbuddies-cas/fitbuddy/issues/21) | Hevy API-Key Entry Screen + Validierung | US-4 | ~4h | #19, #23 |
| [#22](https://github.com/fitbuddies-cas/fitbuddy/issues/22) | Claude API-Key Entry Screen + Skip-Option | US-4 | ~3h | #19, #23 |
| [#24](https://github.com/fitbuddies-cas/fitbuddy/issues/24) | Onboarding Edge Cases + Error States | US-4 | ~3h | #20, #21, #22 |

**Geschätzter Gesamtaufwand:** ~23h (exkl. Xcode-Setup)

### Implementierungsreihenfolge

```
Xcode-Setup
    └── #33 FitnessConnector-Protocol    (Architektur-Fundament)
    └── #19 KeychainService              (Fundament für alle Key-Operationen)
            └── #23 OnboardingViewModel  (State-Machine für den Flow)
                    ├── #20 ConsentScreen
                    ├── #21 HevyKeyScreen
                    └── #22 ClaudeKeyScreen
                            └── #24 Edge Cases & Error States
```

### Technische Entscheide in Sprint 1

| Entscheid | Festlegung | ADR |
|---|---|---|
| Lokale Datenbank | SwiftData (`@Model`) | ADR-001 |
| Plattform | iOS 17+, native SwiftUI | ADR-002 |
| Keychain-Attribut | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | ADR-003 |
| Kein Backend | Direkter API-Call vom Gerät | ADR-004 |
| FitnessConnector | Protocol vor erster Connector-Implementierung | ADR-006 |
| Cooldown-Key | `fitbuddy.analysis.lastCooldownTimestamp` in UserDefaults (→ W-4) | ADR-001/004 |

### Risiken Sprint 1

| Risiko | Wahrscheinlichkeit | Mitigation |
|---|---|---|
| HealthKit-Entscheid verzögert `FitnessConnector`-Design (W-5) | Mittel | Entscheid Tag 1 erzwingen — Empfehlung OUT → Protocol ohne HealthKit-Felder |
| Hevy-Validierungslogik schlägt fehl wegen API-Instabilität (AR-1) | Niedrig | Retry mit Exponential Backoff; Fehlermeldung klar formulieren |
| SwiftData-Schema nach erstem Sprint-Commit schwer änderbar | Mittel | `VersionedSchema` von Anfang an einrichten (ADR-001) |

---

## Sprint 2 — Dashboard (Vorschau)

**Ziel:** User sieht nach Login seine letzten 90 Tage Hevy-Trainings im Dashboard: Volumen, Ø Trainingstage/Woche, Muskelbelastungs-Diagramm. Offline-Betrieb mit gecachten Daten funktioniert.

**Issues:** #25 HevyConnector-Fetch, #26 WorkoutListViewModel, #27 DashboardView, #28 Offline-Handling, #34 HevyConnector-Refactoring auf FitnessConnector.

---

## Sprint 3 — AI-Analyse (Vorschau)

**Ziel:** «Analysieren»-Button liefert eine konkrete Trainingsempfehlung via Claude API. Streaming, 30s-Timeout, 6h-Cooldown, Helpful/Not-helpful-Feedback lokal gespeichert.

**Issues:** #29 InferenceService, #30 Prompt-Builder, #31 AnalysisViewModel, #32 AnalysisView.

**Technische Schulden die vorher adressiert werden müssen:** TD-1 (Token-Limit), TD-2 (Cooldown vor API-Call), TD-3 (Backgrounding-Handling) → siehe ARCHITECTURE.md.

---

## Sprint 4 — Should-Features (Vorschau)

**Ziel:** Architekturelle Erweiterbarkeit sicherstellen (StravaConnector-Stub), Analyse-Kontext anzeigen, Übungssuche & Filter.

**Issues:** #35 StravaConnector-Stub, #36 AnalysisContextView, #37–39 Übungssuche/Filter.

---

## Sprint 5 — Could-Features & Polish (Vorschau)

**Ziel:** Datenquelle-Status, Progressionskurven mit Plateau-Detection, Pull-to-Refresh. TestFlight-Build vorbereiten (Privacy Manifest, App-Icon, Splash-Screen, Datenschutzerklärung-Screen).

**Issues:** #40–43.

---

*Dieses Dokument ist die massgebliche Planungsgrundlage. Änderungen an User Stories oder Acceptance Criteria immer synchron in REQUIREMENTS.md und den GitHub-Issues pflegen (→ CLAUDE.md Sync-Regel).*
