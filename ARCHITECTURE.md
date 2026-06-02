# FitBuddy — Architektur

## Systemübersicht

```
┌─────────────────────────────────────────────────────┐
│                  iOS App (Native)                   │
│                                                     │
│  ┌──────────────┐    ┌──────────────┐               │
│  │  Onboarding  │    │  Dashboard   │               │
│  │  (US-4)      │    │  (US-2)      │               │
│  └──────┬───────┘    └──────┬───────┘               │
│         │                  │                        │
│  ┌──────▼──────────────────▼───────┐               │
│  │         Connector Layer          │               │
│  │  (Interface: connect / validate  │               │
│  │   fetchActivities / disconnect)  │               │
│  └──────┬───────────────┬──────────┘               │
│         │               │                           │
│  ┌──────▼──────┐  ┌─────▼───────┐                  │
│  │    Hevy     │  │   Strava    │  ← v1.1           │
│  │  Connector  │  │  Connector  │                   │
│  └──────┬──────┘  └─────────────┘                  │
│         │                                           │
│  ┌──────▼──────────────────────────┐               │
│  │   ExerciseTemplateCache (lokal) │               │
│  │   primary_muscle_group etc.     │               │
│  └──────┬──────────────────────────┘               │
│         │                                           │
│  ┌──────▼──────────────────────────┐               │
│  │       Normalized Activity       │               │
│  │       Data Model (lokal)        │               │
│  └──────┬──────────────────────────┘               │
│         │                                           │
│  ┌──────▼──────────────────────────┐               │
│  │     AI Analysis Engine (US-3)   │               │
│  │     On-demand, user-triggered   │               │
│  └──────┬──────────────────────────┘               │
│         │                                           │
│  ┌──────▼──────────────────────────┐               │
│  │      iOS Keychain               │               │
│  │  fitbuddy.hevy.apikey           │               │
│  │  fitbuddy.claude.apikey         │               │
│  │  fitbuddy.strava.access_token   │               │
│  │  fitbuddy.strava.refresh_token  │               │
│  │  fitbuddy.strava.token_expiry   │               │
│  └─────────────────────────────────┘               │
└────────────────────────┬────────────────────────────┘
                         │ direkte API-Calls (kein Proxy)
         ┌───────────────┼───────────────┐
         ▼               ▼               ▼
    Hevy API        Claude API      Strava API
                                    (v1.1)
```

## Technologie-Stack

| Schicht | Technologie | Begründung |
|---|---|---|
| Plattform | iOS (native Swift / SwiftUI) | API-Key lokal im Keychain; kein Web-Proxy nötig für Hevy-Calls |
| AI | Claude API (Anthropic) | On-demand, kein eigenes ML-Training |
| Primäre Datenquelle | Hevy REST API | PoC-Quelle; Pro-User haben API-Key |
| Lokaler Speicher | iOS Keychain + lokaler Cache | Privacy-First: keine User-Daten auf eigenen Servern |
| Datenquelle v1.1 | Strava OAuth API | Ausdauerdaten; architektonisch vorbereitet |

**Kein Backend / kein Server:** API-Keys bleiben lokal im iOS Keychain. Alle API-Calls (Hevy, Claude) laufen direkt vom Gerät. Kein serverseitiger Proxy im PoC.

> **Hevy API-Key:** Nur für Hevy **Pro**-User verfügbar. Key wird unter `https://hevy.com/settings?developer` generiert und im Header `api-key: <uuid>` mitgesendet.
>
> **Strava OAuth:** Strava verwendet OAuth 2.0 (Authorization Code Flow). Access Tokens laufen ab und müssen via Refresh Token erneuert werden — daher drei getrennte Keychain-Einträge statt einem.

> **Architekturentscheid:** Obwohl ein Backend-Proxy für AI-Calls grundsätzlich Best Practice wäre, wird im PoC der Claude API-Key direkt im Keychain gespeichert. Begründung: Zielgruppe sind technikaffine Hevy-Pro-User, die bereits gewohnt sind, API-Keys zu verwalten. Vereinfacht den PoC erheblich. Revisit vor v1.0-Launch.

## Connector-Interface

Alle Datenquellen implementieren dasselbe Interface. Hevy ist der erste Connector — nicht der einzige.

```swift
protocol FitnessConnector {
    func connect(credentials: ConnectorCredentials) async throws
    func validate() async throws -> Bool            // Hevy: GET /v1/user/info
    func fetchActivities(since: Date) async throws -> [Activity]
    func disconnect()
}

/// Polymorphe Credentials — Hevy braucht einen API-Key,
/// Strava braucht OAuth-Tokens mit Ablaufdatum.
enum ConnectorCredentials {
    case apiKey(String)
    case oauthTokens(accessToken: String, refreshToken: String, expiresAt: Date)
}
```

**Keychain-Keys (je eigener Eintrag, nie gemischt):**
- `fitbuddy.hevy.apikey`
- `fitbuddy.claude.apikey`
- `fitbuddy.strava.access_token`
- `fitbuddy.strava.refresh_token`
- `fitbuddy.strava.token_expiry`  ← ISO-8601-String

## Normalisiertes Datenmodell

Alle Datenquellen werden auf ein gemeinsames `Activity`-Modell normalisiert. Vor US-2 und US-3 etablieren, damit später kein Refactor nötig ist.

```swift
struct Activity {
    let id: String
    let source: DataSource        // .hevy, .strava
    let type: ActivityType        // .strength, .cardio
    let startedAt: Date
    let durationMinutes: Int
    let exercises: [Exercise]?    // Krafttraining
    let distanceKm: Double?       // Ausdauer
}

struct Exercise {
    let name: String
    let exerciseTemplateId: String  // Hevy-ID → Lookup im ExerciseTemplateCache
    let primaryMuscleGroup: MuscleGroup
    let secondaryMuscleGroups: [MuscleGroup]
    let sets: [ExerciseSet]
}

struct ExerciseSet {
    let weightKg: Double?
    let reps: Int?
    let setType: SetType            // .warmup, .normal, .failure, .dropset
    let rpe: Double?                // 6–10; wertvoll für AI-Analyse (US-3)
    let distanceMeters: Double?     // für Cardio-Sets (Rudern etc.)
    let durationSeconds: Int?
}

enum SetType { case warmup, normal, failure, dropset }
```

### ExerciseTemplateCache

Muskelgruppen-Daten stehen in Hevy **nicht im Workout**, sondern im Exercise Template (`GET /v1/exercise_templates`). Der Cache ist Voraussetzung für das Muskelgruppen-Dashboard (US-2).

```swift
/// Wird beim ersten connect() befüllt (pageSize: 100, alle Seiten laden).
/// Persistent in SwiftData/CoreData, kein erneuter Fetch bei jedem App-Start.
class ExerciseTemplateCache {
    func muscleGroup(for templateId: String) -> MuscleGroup?
    func refresh() async throws   // manuell oder beim Onboarding
}
```

## AI-Integration

### Wo AI eingesetzt wird

| Bereich | AI? | Begründung |
|---|---|---|
| Progressions-Empfehlung | Ja (LLM) | Interpretation von Trainingsdaten erfordert Kontext-Verständnis |
| Datenabruf (Hevy API) | Nein | Klassische App-Logik |
| Aggregation & Visualisierung | Nein | Deterministisch, kein AI-Mehrwert |
| Key-Speicherung | Nein | iOS Keychain ist die richtige Lösung |
| Cross-Source-Analyse (v1.1) | Ja (LLM) | Kraft + Ausdauer kombiniert, Recovery-Berechnung |

### Prompt-Engineering (US-3)

**Eingabe an LLM:** Strukturierte Trainingsdaten der letzten 4 Wochen (Volumen, Frequenz, Übungshistorie, Set-Typen, RPE-Werte).

> **RPE-Kontextnutzung:** `ExerciseSet.rpe` (6–10) gibt Claude Aufschluss über subjektive Anstrengung — ermöglicht Empfehlungen wie "Your RPE has been consistently at 9+ for squats — consider a deload week."

**System-Prompt definiert:**
- Verbotene Termini (Fachjargon, der Nicht-Sportler verwirrt)
- Ausgabeformat: «1 Satz Lage · 1 konkrete Aktion · 1 optionaler Hinweis»
- Disclaimer für medizinische Empfehlungen
- Nur Daten des eingeloggten Users — keine Benchmarks fremder Nutzer
- English-only output

**Beispiel-Output-Format:**
```
Your training load has been consistent over the past 3 weeks.
Increase your squat weight by 2.5 kg next session.
Consider a rest day — you've trained 6 of the last 7 days.
```

### Spätere Phase (v1.1)

Sobald Strava eingebunden: Cross-Source-Analyse (Kraft + Ausdauer kombiniert). AI kann dann Recovery-Bedarf nach langen Läufen einrechnen.

## Caching-Strategie

| Szenario | Verhalten |
|---|---|
| Erster Start / connect() | Vollständiger Load via `GET /v1/workouts` (alle Seiten paginiert, max 10/Page) + Template-Cache befüllen |
| Folge-Syncs | Delta-Sync via `GET /v1/workouts/events?since=<lastSyncTimestamp>` — liefert nur `"updated"` und `"deleted"` Events |
| Event-Typ `"deleted"` | Workout lokal aus Cache entfernen |
| API nicht erreichbar | Gecachte Daten anzeigen mit Hinweis auf letzten Sync (US-2 AC2) |
| Pull-to-Refresh (US-10) | Delta-Sync erzwingen; bei Fehler Cache behalten |
| HTTP 401 | Key aus Keychain löschen, Onboarding-Flow starten (US-1 AC3) |
| Strava Token abgelaufen | Automatischer Token-Refresh vor API-Call (via `fitbuddy.strava.refresh_token`) |

> **Pagination:** Hevy erlaubt max. 10 Workouts pro Page. Für 90 Tage (~65 Workouts bei 5×/Woche) sind ~7 API-Calls nötig. Der `HevyConnector` kapselt die Pagination-Loop intern — `fetchActivities(since:)` gibt immer eine vollständige Liste zurück.

## Architektur-Entscheide (ADRs)

| ADR | Titel | Status |
|---|---|---|
| [ADR-001](ADRs/ADR-001-local-database.md) | Lokale Datenbank — SwiftData als Persistenz-Technologie | Proposed |
| [ADR-002](ADRs/ADR-002-native-ios-swiftui.md) | Native iOS (SwiftUI) als Plattform | Proposed |
| [ADR-003](ADRs/ADR-003-keychain-this-device-only.md) | API-Keys im iOS Keychain mit `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Proposed |
| [ADR-004](ADRs/ADR-004-no-backend-proxy-poc.md) | Kein Backend-Proxy im PoC — Direkter API-Call vom iOS-Client | Proposed |
| [ADR-005](ADRs/ADR-005-claude-api-usa-with-dpa.md) | Claude API (USA) via Anthropic Commercial Terms im PoC, EU-Hosting vor v1.0 | Proposed |
| [ADR-006](ADRs/ADR-006-fitness-connector-protocol.md) | `FitnessConnector`-Protocol als Abstraktion ab Sprint 1 | Proposed |

## Offene Architektur-Fragen

| Frage | Priorität |
|---|---|
| Apple Health: Schlaf, HRV, Ruheherzrate — IN oder OUT? Wenn IN: passiver HealthKit-Zugriff, kein Connector nötig | Hoch — vor Architektur-Story entscheiden |
| Fehlerzustand 401: harter Logout vs. weicher Banner | Mittel — Empfehlung: harter Logout im PoC |
| US-3 (AI-Analyse) Epic: in Child Stories aufteilen (Prompt-Design, UI, Error-Handling, Disclaimer) | Hoch — vor Sprint-Planung |
| Body Measurements (`GET /v1/body_measurements`) als optionaler AI-Kontext für US-3? Liefert Gewicht, Körperfett, Umfänge — ermöglicht Kraft-zu-Gewicht-Verhältnis-Empfehlungen | Mittel |
| `ExerciseTemplateCache`: SwiftData oder CoreData? Oder genügt ein In-Memory-Dictionary mit UserDefaults-Persistenz? | Mittel — vor US-2 entscheiden |
| Hevy Events-Endpoint ist als "early development" markiert — Fallback-Strategie bei Breaking Change definieren | Niedrig — beobachten |

---

## Architecture Draft — Synthese Tag 1

*Erstellt aus C1-System-Context, C2-Container-Diagram, ADR-001 bis ADR-006 und Top-3-QAs. Stand: 2026-06-02.*

### Architektur in einem Satz

FitBuddy ist eine **on-device iOS-App ohne Server-Tier**: alle Daten bleiben auf dem Gerät, alle API-Calls laufen direkt vom iPhone, und der einzige externe Zustand sind die API-Keys zweier Drittanbieter (Hevy, Anthropic).

---

### Schichtenarchitektur (Layered Monolith + MVVM)

Das gewählte Architektur-Pattern ist ein **On-Device Layered Monolith** mit vier Schichten. Kein Pattern-Entscheid verändert die C2-Container — die Schichtung ist eine C3-Entscheidung innerhalb der iOS-App.

```
┌────────────────────────────────────────────┐
│  Presentation Layer                         │
│  SwiftUI Views · @State · @Binding          │
│  → Dashboard (US-2), Onboarding (US-4),     │
│    AI-Result-View (US-3)                    │
├────────────────────────────────────────────┤
│  ViewModel Layer  [@MainActor]              │
│  @Observable ViewModels                     │
│  → DashboardViewModel, AnalysisViewModel,   │
│    OnboardingViewModel                      │
├────────────────────────────────────────────┤
│  Service / Domain Layer                     │
│  → InferenceService (Claude-Call kapseln,   │
│    Prompt-Build, 6h-Cooldown)               │
│  → ConnectorLayer (FitnessConnector-        │
│    Protocol, Delta-Sync, Error-Routing)     │
├────────────────────────────────────────────┤
│  Data Layer                                 │
│  → HevyConnector (URLSession, Pagination)   │
│  → KeychainService (SecItemAdd/CopyMatching)│
│  → SwiftData Store (ModelActor,             │
│    Activity / Exercise / ExerciseSet)       │
│  → ExerciseTemplateCache (SwiftData)        │
└────────────────────────────────────────────┘
```

**Wichtigste Schichtregeln:**
- API-Keys berühren ausschliesslich den Data Layer — nie ViewModel oder View.
- Dashboard und InferenceService lesen ausschliesslich aus dem normalisierten `Activity`-Modell (ADR-006).
- Alle SwiftData-Schreibzugriffe laufen über `ModelActor`, nie direkt auf dem `@MainActor`.

---

### C2-Container im Überblick

| Container | Technologie | Kritischstes Risiko |
|---|---|---|
| **iOS App** | Swift · SwiftUI · MVVM · Swift Concurrency | Actor-Isolation-Fehler kompilieren, crashen zur Laufzeit |
| **SwiftData Store** | SwiftData (`@Model`) · SQLite · on-device | Stille Store-Löschung bei fehlender `VersionedSchema` |
| **iOS Keychain** | Keychain Services · `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Kein Recovery-Pfad bei verlorenem Key |
| **Backend/Proxy** *(v1.0/v1.1)* | AWS Lambda + API Gateway · eu-central-1 | Übergang PoC → v1.0 ist ein Umbau, kein Plugin |

*Externe Systeme (Hevy API, Claude API, Strava API) sind keine Container — sie liegen ausserhalb der Systemgrenze.*

---

### Kritischer Datenfluss — «Analysieren»-Button (US-3)

```
[1] Keychain Read      → Claude API-Key lesen (<1ms, synchron)
[2] SwiftData Query    → Workouts 90 Tage laden (async, ModelActor)
[3] Prompt-Build       → Daten serialisieren (kein Token-Limit definiert ⚠)
[4] HTTPS POST         → api.anthropic.com (5–30s, kein Streaming, kein Retry ⚠)
[5] Response parsen    → AI-Empfehlung extrahieren
[6] SwiftData Write    → Cooldown-Timestamp speichern (Race Condition ⚠)
[7] @MainActor Update  → SwiftUI re-rendert Ergebnis
```

**Drei undokumentierte Lücken in diesem Pfad:**
1. Kein Token-Limit für den Prompt → `400 context_length_exceeded` möglich
2. Cooldown-Write nach API-Call → Crash-Window = doppelte Analyse-Kosten möglich
3. Kein App-Backgrounding-Handling → iOS beendet URLSession-Task nach ~30s

---

## Widersprüche & Unklarheiten

*Spannungen, die beim Abgleich der Dokumente sichtbar wurden. Vor Sprint 1 auflösen.*

| # | Widerspruch / Unklarheit | Betroffene Dokumente | Handlungsbedarf |
|---|---|---|---|
| W-1 | **30 Tage vs. 90 Tage Cache.** `README.md` schreibt «30-day training dashboard». `ADR-001`, `C2-Container.md` und dieser Abschnitt sagen durchgängig «90 Tage». | `README.md`, `ADR-001`, `C2-Container.md` | Cache-Horizont als verbindliche Grösse festlegen und überall angleichen — vor Sprint 2. |
| W-2 | **«4 Wochen» im Prompt vs. «90 Tage» im Cache.** Der Prompt-Engineering-Abschnitt definiert die LLM-Eingabe als «letzten 4 Wochen», während der SwiftData-Store 90 Tage hält. Was erhält Claude tatsächlich — 28 Tage, 30 Tage oder 90 Tage? | `ARCHITECTURE.md` (Prompt-Abschnitt), `ADR-001`, `C2-Container.md` | Prompt-Fenster explizit definieren und vom Cache-Horizont trennen. Beide Werte im Prompt-Builder-Code als Konstanten führen. |
| W-3 | **Certificate Pinning: im Diagramm als aktiv dargestellt, laut ADR aber noch nicht implementiert.** `C2-Container.md` schreibt «Alle externen Verbindungen über TLS, mit Certificate Pinning (QA-1)» als Gegenwart. `ADR-004` markiert es als «Pflicht in Sprint 2». | `C2-Container.md`, `ADR-004` | Formulierung in `C2-Container.md` auf «geplant, Sprint 2» korrigieren, damit die Sicherheitsaussage nicht irreführend ist. |
| W-4 | **6h-Cooldown-Speicherort undefiniert.** `ADR-004` nennt «6h via UserDefaults». `ADR-001` reserviert UserDefaults nur für den Sync-Zeitstempel. Kein Dokument definiert den konkreten Key oder schützt vor Kollision zwischen beiden Werten. | `ADR-004`, `ADR-001` | UserDefaults-Key-Konvention (`fitbuddy.analysis.lastCooldownTimestamp`) in `ADR-001` oder `ADR-004` ergänzen. |
| W-5 | **HealthKit: Entscheid «vor Sprint 1» gefordert, aber nirgends getroffen.** `ADR-006` markiert den HealthKit-Scope als «Kritisch, vor Sprint 1». `C1-System-Context.md` zeigt ihn als «(?) offene Entscheidung». Kein ADR hat entschieden — das `Activity`-Modell ist deshalb noch nicht finalisierbar. | `ADR-006`, `C1-System-Context.md` | Muss auf Tag 2 entschieden werden — blockiert Protocol-Design und Datenmodell (→ Frage 1). |
| W-6 | **Strava OAuth-Secret ohne Backend strukturell unlösbar.** `C1-System-Context.md` benennt das Problem explizit. `ADR-004` plant als Plan-B Cloudflare AI Gateway (für AI-Calls), aber benennt keinen Plan für das OAuth-Secret. `ADR-006` stubbt Strava aus ohne diesen Konflikt zu lösen. | `C1-System-Context.md`, `ADR-004`, `ADR-006` | Vor der Strava-Implementierung (v1.1) muss ein Entscheid stehen: Secret in App einbetten (exponiert, nicht akzeptabel) oder Backend-Proxy akzeptieren — damit fällt das «kein Backend»-Versprechen für v1.1. |
| W-7 | **ADR-Querverweise im Caching-Abschnitt referenzieren nicht-existierende Nummern.** Der Caching-Abschnitt nennt «ADR-6: Delta-Sync» und «ADR-7: Strava Token Refresh» — diese Nummern existieren als Dateien nicht. Die korrekten Dateien sind `ADR-001` bis `ADR-006`. | `ARCHITECTURE.md` (Caching-Abschnitt), `ADRs/` | Querverweise auf `ADR-001` bis `ADR-006` korrigieren; Delta-Sync und Strava-Refresh als `ADR-007` und `ADR-008` auslagern. |

---

## Top-3 Fragen für Tag 2

*Unbeantwortet blockieren diese drei Fragen entweder Sprint 1 oder die Rechtskonformität des PoC.*

---

### Frage 1 — HealthKit: IN oder OUT?

**Warum jetzt?** ADR-006 fordert diesen Entscheid vor Sprint 1. Das `FitnessConnector`-Protocol und das `Activity`-Datenmodell können nicht finalisiert werden, bevor klar ist, ob HealthKit einen separaten `HealthDataProvider`-Vertrag braucht oder ganz ausgeschlossen bleibt. Jede Woche Verzug ist eine Woche Protocol-Drift.

**Was hängt daran:**
- `Activity`-Modell (optionale Felder für HRV, RHR, Schlafdauer?)
- Sprint-1-Scope: `HealthDataProvider`-Protocol designen oder explizit auf OUT setzen
- Privacy Manifest: HealthKit-Nutzung erfordert zusätzliche `NSHealthShareUsageDescription`-Einträge

**Entscheidungsgrundlage:** HealthKit-Daten (Schlaf, HRV) würden den AI-Prompt qualitativ verbessern (US-3). Gegen IN sprechen: HealthKit-Permission-Flow ist komplex, `HKQuery` passt nicht ins `FitnessConnector`-Protocol, und der PoC-Scope ist bereits eng. Empfehlung: **OUT für PoC**, optionaler `HealthDataProvider` für v1.1 vorsehen.

---

### Frage 2 — AUP-Klärung: Erlaubt Anthropic Direct-from-Mobile für TestFlight?

**Warum jetzt?** ADR-004 nennt dies als «hartes Gate vor Sprint 3». Anthropic empfiehlt explizit gegen API-Keys in Mobile-Clients. Eine Account-Sperrung ist möglich — unabhängig vom DPA, unabhängig vom Demo-Termin. Wenn die Klärung negativ ausfällt, muss Cloudflare AI Gateway als Plan-B aktiviert werden (~0.5 Tage Aufwand). Das muss vor Sprint-3-Start feststehen — und damit muss die Klärung in Sprint 1 gestartet werden.

**Was hängt daran:**
- Ob `InferenceService` direkt gegen `api.anthropic.com` oder gegen einen Proxy-Endpunkt baut
- Ob Certificate Pinning gegen `api.anthropic.com` oder gegen Cloudflare gepinnt wird
- Ob der Consent-Text (US-4 AC4) Cloudflare als Empfänger nennen muss

**Entscheidungsgrundlage:** Support-Anfrage an Anthropic mit Beschreibung des PoC-Szenarios (TestFlight, akademisch, keine öffentliche Distribution). Bei Ablehnung: Cloudflare AI Gateway sofort als Plan-B konfigurieren.

---

### Frage 3 — Skill-Audit: Kann das Team produktiv in SwiftUI + Swift Concurrency entwickeln?

**Warum jetzt?** ADR-002 nennt dies explizit als «Kritisch, Sprint 1, Woche 1» mit einem Go/No-Go-Entscheid und UIKit als Fallback. Die gesamte Technologiewahl (SwiftUI, SwiftData, `ModelActor`, async/await) steht unter diesem Vorbehalt. Ohne Audit wird in Sprint 2 realisiert, dass ein Umbau nötig ist — dann ist die Hälfte des PoC-Fensters verbraucht.

**Was hängt daran:**
- ADR-002 bleibt in Status «Proposed» bis der Audit abgeschlossen ist — alle nachgelagerten Architekturentscheide (SwiftData-Integration, `@Query`, `ModelActor`) erben diesen Vorbehalt
- Swift Concurrency (`async/await`, `@MainActor`, `ModelActor`) ist die grösste Lernkurve; ohne Erfahrung damit entstehen Actor-Isolation-Bugs, die erst zur Laufzeit sichtbar werden
- Privacy Manifest (`PrivacyInfo.xcprivacy`) und Xcode-Projekt-Setup erfordern macOS 14 Sonoma + Xcode 15 auf allen Dev-Maschinen — Hardware-Voraussetzung, die vor Sprint 1 geklärt sein muss

**Entscheidungsgrundlage:** Audit-Fragen: Wer hat bereits eine App mit SwiftUI + async/await gebaut? Kann jemand `ModelActor` erklären? Gibt es macOS 14 auf allen Geräten? Bei negativem Ergebnis: UIKit als Basis mit SwiftUI nur für einfache Views (Hybrid-Ansatz gemäss ADR-002). Empfehlung: **Scaffold-Workshop in Woche 1**, bevor der erste Feature-Branch geöffnet wird.

---

*Stand: 2026-06-02 · Quellen: `C1-System-Context.md`, `C2-Container.md`, `ADR-001` bis `ADR-006`, `REQUIREMENTS.md` (QA-1/2/3)*
