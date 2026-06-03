# FitBuddy — Architektur

> *Getrennt geführt: Ziele, Personas, Risiken → [README.md](README.md) · User Stories, NFRs → [REQUIREMENTS.md](REQUIREMENTS.md) · Architekturentscheide (Detail) → [ADRs/](ADRs/)*

---

## Inhalt

- [Kontextabgrenzung](#kontextabgrenzung)
  - [Akteure & externe Systeme](#akteure--externe-systeme)
  - [Bewusste Leerstellen](#bewusste-leerstellen)
- [Lösungsstrategie](#lösungsstrategie)
- [Bausteinsicht](#bausteinsicht)
  - [Schichtenarchitektur](#schichtenarchitektur-layered-monolith--mvvm)
  - [Container](#container)
  - [Komponenten — C3](#komponenten--c3-folgt-in-modul-5--coding-phase)
  - [Connector-Interface](#connector-interface)
  - [Normalisiertes Datenmodell](#normalisiertes-datenmodell)
- [Laufzeitsicht](#laufzeitsicht)
  - [Kritischer Datenfluss — «Analysieren» (US-3)](#kritischer-datenfluss--analysieren--us-3)
  - [Caching-Strategie](#caching-strategie)
- [Querschnittliche Konzepte](#querschnittliche-konzepte)
  - [AI-Integration](#ai-integration)
  - [ExerciseTemplateCache](#exercisetemplatecache)
- [Architekturentscheide](#architekturentscheide)
- [Offene Fragen](#offene-fragen)
  - [Widersprüche & Unklarheiten](#widersprüche--unklarheiten)
  - [Offene Architektur-Fragen](#offene-architektur-fragen)

---

## Kontextabgrenzung

```
  ┌──────────────────────┐     reicht App ein          ┌─────────────────────────────┐
  │  FitBuddy Team       │── (Review, Privacy- ──────→ │  Apple App Store Connect /  │
  │  [Person · Betreiber]│    Manifest)                │  TestFlight                 │
  │  betreibt App; AVV/  │                             │  [Externes System]          │
  │  DPA mit Anthropic   │                             │  Gatekeeper + Distribution  │
  └──────────────────────┘                             └───────────────┬─────────────┘
                                                                       │ verteilt App
                                                                       ▼
  KEY-BESCHAFFUNG           NUTZER                    SYSTEM                    LAUFZEIT-SYSTEME

  ┌────────────────┐                                                    ┌─────────────────────────────┐
  │ Hevy-App /     │◀─┐                                                 │  Hevy API (REST)            │
  │ Website        │  │ holt Hevy-Key                                   │  [Externes System]          │
  │ [Ext. System]  │  │                                                 │  Krafttrainingsdaten        │
  └────────────────┘  │  ┌───────────────────┐                          └─────────────────────────────┘
  ┌────────────────┐  │  │  User             │                                    ▲  GET /workouts
  │ Anthropic      │  │  │  [Person]         │                                    │  (Bearer-Key, HTTPS)
  │ Console        │◀─┴──│  Endnutzer der    │    ┌───────────────────────┐───────┘
  │ [Ext. System]  │     │  App              │ ──→│                       │
  │ → Claude-Key   │     └───────────────────┘    │   FitBuddy            │  ┌──────────────────────────────────────┐
  └────────────────┘  nutzt App, gibt Keys ein,   │   [Software-System]   │── Prompt ─→│ Anthropic Claude API (USA) │
                      fordert AI-Analyse an        │   Native iOS-App,     │  ←─ Empf.  │ [Externes System]          │
                                                   │   kein Backend        │            │ ⚠ Drittland USA (nDSG)     │
                                                   │                       │            └──────────────────────────────────────┘
                                                   │                       │  ┌─────────────────────────────────────┐
                                                   │                       │- - - - →│ Strava / Polar API      v1.1 │
                                                   └───────────┬───────────┘  Ausdauer│ Cardio-Daten (geplant)      │
                                                               │             └─────────────────────────────────────┘
                              ON-DEVICE / PLATTFORM            │
  ┌──────────────────────┐   ┌───────────────────────┐   ┌────┴─────────────────────┐
  │  iOS Keychain /      │   │  Apple HealthKit      │   │  iCloud-Backup           │
  │  Secure Enclave      │   │  [Plattform] (?)      │   │  [Externes System]       │
  │  [Plattform-Service] │   │  Schlaf / HRV / RHR   │   │  ✗ KEIN Datenfluss —     │
  │  API-Keys + Consent  │   │  → OFFENE ENTSCHEIDUNG│   │  isExcludedFromBackup    │
  └──────────────────────┘   └───────────────────────┘   └──────────────────────────┘
```

**Legende:** durchgezogen = PoC · `- - -` = v1.1 (geplant) · `(?)` = offene Entscheidung · `✗` = bewusst geblockter Datenfluss

### Akteure & externe Systeme

| Element | Typ | Scope | Zweck |
|---|---|---|---|
| User | Person | — | Endnutzer (Training-Tracking + AI-Analyse) |
| FitBuddy Team | Person (Betreiber) | — | Entwickelt/betreibt App, schliesst AVV/DPA ab |
| **FitBuddy** | Software-System | **PoC** | Native iOS-App, Datenaggregation + On-demand-AI |
| Hevy API | Externes System | PoC | Primäre Datenquelle (Kraft) |
| Anthropic Claude API | Externes System | PoC | LLM-Progressionsempfehlung (USA, Drittland) |
| Apple App Store Connect / TestFlight | Externes System | PoC | Distribution + Review-Gate + Privacy Report |
| iOS Keychain | Plattform-Service | PoC | Sichere Key-/Consent-Speicherung |
| Apple HealthKit | Plattform-Service | **offen** | Schlaf/HRV/RHR — Scope ungeklärt |
| iCloud-Backup | Externes System | **ausgeschlossen** | `isExcludedFromBackup` — kein Datenfluss |
| Strava API | Externes System | v1.1 | Ausdauerdaten via OAuth — Backend-Problematik offen (→ W-6) |
| Polar Accesslink | Externes System | v1.1 | Alternative zu Strava; PKCE-fähig, kein Backend nötig (→ [polar-integration.md](polar-integration.md)) |

### Bewusste Leerstellen

Im PoC absichtlich nicht vorhanden: Auth-Provider/User-Accounts (Auth = Bearer-Keys im Keychain → kein Cross-Device, keine Account-Recovery), E-Mail/Push (US-11 = Won't), Monetarisierung, Analytics-Dienst.

---

## Lösungsstrategie

FitBuddy ist eine **on-device iOS-App ohne Server-Tier**: alle Daten bleiben auf dem Gerät, alle API-Calls laufen direkt vom iPhone, und der einzige externe Zustand sind die API-Keys zweier Drittanbieter (Hevy, Anthropic).

| Schicht | Technologie | Begründung |
|---|---|---|
| Plattform | iOS (native Swift / SwiftUI) | API-Key lokal im Keychain; null Drittanbieter-Abhängigkeiten |
| AI | Claude API (Anthropic) | On-demand, kein eigenes ML-Training |
| Primäre Datenquelle | Hevy REST API | PoC-Quelle; Pro-User haben API-Key |
| Lokaler Speicher | iOS Keychain + SwiftData (SQLite) | Privacy-First: keine User-Daten auf eigenen Servern |
| Datenquelle v1.1 | Strava OAuth / Polar Accesslink | Ausdauerdaten; architektonisch vorbereitet via `FitnessConnector` |

**Kein Backend im PoC.** Der Claude API-Key wird direkt im Keychain gespeichert — vereinfacht den PoC erheblich, muss vor v1.0-Launch überprüft werden (→ ADR-004). Die Apple-native Technologiewahl (SwiftUI, SwiftData, URLSession, Swift Concurrency, Swift Charts) eliminiert Drittanbieter-Build-Abhängigkeiten und senkt die Einarbeitungshürde für ein gemischtes Team.

---

## Bausteinsicht

### Schichtenarchitektur (Layered Monolith + MVVM)

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

**Schichtregeln:**
- API-Keys berühren ausschliesslich den Data Layer — nie ViewModel oder View.
- Dashboard und InferenceService lesen ausschliesslich aus dem normalisierten `Activity`-Modell (ADR-006).
- Alle SwiftData-Schreibzugriffe laufen über `ModelActor`, nie direkt auf dem `@MainActor`.

### Container

```
                         ┌──────────────┐
                         │     User      │
                         │   [Person]    │
                         └──────┬───────┘
                                │ nutzt (Touch / SwiftUI, on-device)
                                ▼
  ╔══════════════════ FitBuddy — iPhone (iOS 17+) ════════════════════════╗
  ║                                                                       ║
  ║   ┌───────────────────────────────────────────────────┐               ║
  ║   │  iOS App                                          │               ║
  ║   │  [Swift · SwiftUI · MVVM · Swift Concurrency ·    │               ║
  ║   │   URLSession · Swift Charts]                      │               ║
  ║   └──┬──────────────────┬───────────────────────┬─────┘               ║
  ║      │ ModelContext     │ Security API          │ HTTPS               ║
  ║      │ (in-process)     │ (in-process)          │ (TLS)               ║
  ║      ▼                  ▼                       │                     ║
  ║  ┌──────────────┐  ┌────────────────────┐       │                     ║
  ║  │ SwiftData    │  │ iOS Keychain       │       │                     ║
  ║  │ Store        │  │ [Keychain Services]│       │                     ║
  ║  │ [SQLite]     │  │ API-Keys + Consent │       │                     ║
  ║  │ Activity-    │  │ (verschlüsselt)    │       │                     ║
  ║  │ Cache (90 T) │  └────────────────────┘       │                     ║
  ║  └──────────────┘                               │                     ║
  ╚═════════════════════════════════════════════════┼═════════════════════╝
                                                    │
            ┌──────────────────────┬────────────────┴─────┐
            ▼                      ▼                      ▼
   ┌─────────────────┐   ┌──────────────────────┐   ┌────────────────────┐
   │ Hevy API (REST) │   │ Anthropic Claude API │   │ Strava / Polar     │
   │ [Ext. System]   │   │ [Ext. System · USA]  │   │ [Ext. System] v1.1 │
   │ GET /workouts   │   │ Messages API         │   │ (geplant, - - -)   │
   └─────────────────┘   └──────────────────────┘   └────────────────────┘

  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  v1.0 / v1.1 (NICHT im PoC):
  ┌───────────────────────────────────────────────────────────────────┐
  │ Backend / Proxy  [AWS Lambda + API Gateway, eu-central-1]         │
  │ Für: Bedrock-Region (ADR-5) und ggf. Strava-OAuth-Token-Exchange  │
  └───────────────────────────────────────────────────────────────────┘
```

| Container | Technologie | Kritischstes Risiko |
|---|---|---|
| **iOS App** | Swift · SwiftUI · MVVM · Swift Concurrency | Actor-Isolation-Fehler crashen erst zur Laufzeit |
| **SwiftData Store** | SwiftData (`@Model`) · SQLite · on-device | Stille Store-Löschung bei fehlender `VersionedSchema` |
| **iOS Keychain** | Keychain Services · `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Kein Recovery-Pfad bei verlorenem Key |
| *(v1.0/v1.1)* **Backend/Proxy** | AWS Lambda + API Gateway · eu-central-1 | Übergang PoC → v1.0 ist ein Umbau, kein Plugin |

*Bewusst nicht vorhanden: Web-App, API-Server, Server-Datenbank, verteilter Cache, Message Queue (ADR-004).*

### Komponenten — C3 *(folgt in Modul 5 / Coding Phase)*

C3 zeigt die konkreten Swift-Klassen und ihre Abhängigkeiten *innerhalb* des iOS-App-Containers. Wird hier ergänzt, sobald die Implementierung beginnt — die Schichtenarchitektur oben ist bis dahin die massgebliche Struktur.

### Connector-Interface

Alle Datenquellen implementieren dasselbe Interface. Hevy ist der erste Connector — nicht der einzige.

```swift
protocol FitnessConnector {
    func connect(credentials: ConnectorCredentials) async throws
    func validate() async throws -> Bool            // Hevy: GET /v1/user/info
    func fetchActivities(since: Date) async throws -> [Activity]
    func disconnect()
}

/// Polymorphe Credentials — Hevy braucht einen API-Key,
/// OAuth-Quellen (Strava, Polar) brauchen Tokens mit Ablaufdatum.
enum ConnectorCredentials {
    case apiKey(String)
    case oauthTokens(accessToken: String, refreshToken: String, expiresAt: Date)
}
```

**Keychain-Keys (je eigener Eintrag, nie gemischt):**
- `fitbuddy.hevy.apikey`
- `fitbuddy.claude.apikey`
- `fitbuddy.strava.access_token` / `fitbuddy.strava.refresh_token` / `fitbuddy.strava.token_expiry`

### Normalisiertes Datenmodell

Alle Datenquellen werden auf ein gemeinsames `Activity`-Modell normalisiert. Vor US-2 und US-3 etablieren, damit später kein Refactor nötig ist.

```swift
struct Activity {
    let id: String
    let source: DataSource        // .hevy, .strava, .polar
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
    let distanceMeters: Double?
    let durationSeconds: Int?
}

enum SetType { case warmup, normal, failure, dropset }
```

---

## Laufzeitsicht

### Kritischer Datenfluss — «Analysieren» (US-3)

```
[1] Keychain Read      → Claude API-Key lesen (<1ms, synchron)
[2] SwiftData Query    → Workouts 90 Tage laden (async, ModelActor)
[3] Prompt-Build       → Daten serialisieren (kein Token-Limit definiert ⚠)
[4] HTTPS POST         → api.anthropic.com (5–30s, kein Streaming, kein Retry ⚠)
[5] Response parsen    → AI-Empfehlung extrahieren
[6] SwiftData Write    → Cooldown-Timestamp speichern (Race Condition ⚠)
[7] @MainActor Update  → SwiftUI re-rendert Ergebnis
```

| Lücke | Konsequenz |
|---|---|
| Kein Token-Limit (Schritt 3) | `400 context_length_exceeded` bei 90 Tagen × vollem Trainingsvolumen |
| Cooldown-Write nach API-Call (Schritt 6 nach 4) | Crash-Window → doppelte Analyse-Kosten möglich |
| Kein Backgrounding-Handling (Schritt 4) | iOS beendet URLSession-Task nach ~30s — Analyse verloren, kein User-Feedback |

### Caching-Strategie

| Szenario | Verhalten |
|---|---|
| Erster Start / connect() | Vollständiger Load via `GET /v1/workouts` (alle Seiten paginiert, max 10/Page) + Template-Cache befüllen |
| Folge-Syncs | Delta-Sync via `GET /v1/workouts/events?since=<lastSyncTimestamp>` — nur `"updated"` und `"deleted"` Events |
| Event-Typ `"deleted"` | Workout lokal aus Cache entfernen |
| API nicht erreichbar | Gecachte Daten anzeigen mit Hinweis auf letzten Sync (US-2 AC2) |
| Pull-to-Refresh (US-10) | Delta-Sync erzwingen; bei Fehler Cache behalten |
| HTTP 401 | Key aus Keychain löschen, Onboarding-Flow starten (US-1 AC3) |

> **Pagination:** Hevy erlaubt max. 10 Workouts pro Page. Für 90 Tage (~65 Workouts bei 5×/Woche) sind ~7 API-Calls nötig. `HevyConnector` kapselt die Pagination-Loop intern — `fetchActivities(since:)` gibt immer eine vollständige Liste zurück.

---

## Querschnittliche Konzepte

### AI-Integration

| Bereich | AI? | Begründung |
|---|---|---|
| Progressions-Empfehlung | Ja (LLM) | Interpretation von Trainingsdaten erfordert Kontext-Verständnis |
| Datenabruf (Hevy API) | Nein | Klassische App-Logik |
| Aggregation & Visualisierung | Nein | Deterministisch, kein AI-Mehrwert |
| Key-Speicherung | Nein | iOS Keychain ist die richtige Lösung |
| Cross-Source-Analyse (v1.1) | Ja (LLM) | Kraft + Ausdauer kombiniert, Recovery-Berechnung |

**Prompt-Engineering (US-3)** — Eingabe: Strukturierte Trainingsdaten der letzten 4 Wochen (Volumen, Frequenz, Übungshistorie, Set-Typen, RPE-Werte).

System-Prompt definiert: Verbotene Termini (Fachjargon), Ausgabeformat («1 Satz Lage · 1 konkrete Aktion · 1 optionaler Hinweis»), medizinischen Disclaimer, English-only output.

> **RPE-Nutzung:** `ExerciseSet.rpe` (6–10) gibt Claude Aufschluss über subjektive Anstrengung — ermöglicht Empfehlungen wie *"Your RPE has been consistently at 9+ for squats — consider a deload week."*

### ExerciseTemplateCache

Muskelgruppen-Daten stehen in Hevy nicht im Workout, sondern im Exercise Template (`GET /v1/exercise_templates`). Der Cache ist Voraussetzung für das Muskelgruppen-Dashboard (US-2).

```swift
/// Wird beim ersten connect() befüllt (pageSize: 100, alle Seiten laden).
/// Persistent in SwiftData, kein erneuter Fetch bei jedem App-Start.
class ExerciseTemplateCache {
    func muscleGroup(for templateId: String) -> MuscleGroup?
    func refresh() async throws
}
```

---

## Architekturentscheide

| ADR | Titel | Status |
|---|---|---|
| [ADR-001](ADRs/ADR-001-local-database.md) | Lokale Datenbank — SwiftData als Persistenz-Technologie | Proposed |
| [ADR-002](ADRs/ADR-002-native-ios-swiftui.md) | Native iOS (SwiftUI) als Plattform | Proposed |
| [ADR-003](ADRs/ADR-003-keychain-this-device-only.md) | API-Keys im iOS Keychain mit `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Proposed |
| [ADR-004](ADRs/ADR-004-no-backend-proxy-poc.md) | Kein Backend-Proxy im PoC — Direkter API-Call vom iOS-Client | Proposed |
| [ADR-005](ADRs/ADR-005-claude-api-usa-with-dpa.md) | Claude API (USA) via Anthropic Commercial Terms im PoC, EU-Hosting vor v1.0 | Proposed |
| [ADR-006](ADRs/ADR-006-fitness-connector-protocol.md) | `FitnessConnector`-Protocol als Abstraktion ab Sprint 1 | Proposed |

---

## Offene Fragen

### Widersprüche & Unklarheiten

*Vor Sprint 1 auflösen.*

| # | Widerspruch / Unklarheit | Betroffene Dokumente | Handlungsbedarf |
|---|---|---|---|
| W-2 | **«4 Wochen» im Prompt vs. «90 Tage» im Cache.** Prompt-Engineering definiert LLM-Eingabe als «letzten 4 Wochen», SwiftData-Store hält 90 Tage. Was erhält Claude — 28 Tage oder 90 Tage? | `ARCHITECTURE.md`, `ADR-001` | Prompt-Fenster explizit als Konstante definieren, vom Cache-Horizont trennen. |
| W-3 | **Certificate Pinning: als aktiv formuliert, laut ADR noch nicht implementiert.** ADR-004 markiert es als «Pflicht in Sprint 2». | `ADR-004` | Formulierung korrigieren: «geplant, Sprint 2». |
| W-4 | **6h-Cooldown-Speicherort undefiniert.** ADR-004 nennt «6h via UserDefaults». ADR-001 reserviert UserDefaults nur für den Sync-Zeitstempel. Kein Dokument definiert den konkreten Key. | `ADR-004`, `ADR-001` | UserDefaults-Key-Konvention (`fitbuddy.analysis.lastCooldownTimestamp`) in ADR-001 oder ADR-004 ergänzen. |
| W-5 | **HealthKit: Entscheid gefordert, aber nirgends getroffen.** Das `Activity`-Modell ist deshalb noch nicht finalisierbar. | `ADR-006` | Entscheid blockiert Protocol-Design und Datenmodell. Empfehlung: OUT für PoC. |
| W-6 | **Strava OAuth-Secret ohne Backend strukturell unlösbar.** Secret in App einbetten ist nicht akzeptabel. Polar Accesslink (PKCE, kein Secret) ist eine Backend-freie Alternative — Entscheid steht aus. | `ADR-004`, `ADR-006`, [polar-integration.md](polar-integration.md) | Vor v1.1-Implementierung: Strava (Backend nötig) oder Polar (kein Backend) als zweite Quelle festlegen — eigener ADR. |

### Offene Architektur-Fragen

| Frage | Priorität |
|---|---|
| Apple Health: Schlaf, HRV, Ruheherzrate — IN oder OUT? Wenn IN: passiver HealthKit-Zugriff, kein Connector nötig, aber `Activity`-Modell und Privacy Manifest ändern sich | Hoch — blockiert Sprint 1 |
| AUP-Klärung: Erlaubt Anthropic Direct-from-Mobile für TestFlight? Bei Ablehnung: Cloudflare AI Gateway als Plan-B (~0.5 Tage Aufwand) — muss vor Sprint 3 feststehen | Hoch — in Sprint 1 klären |
| Fehlerzustand 401: harter Logout vs. weicher Banner | Mittel — Empfehlung: harter Logout im PoC |
| `ExerciseTemplateCache`: SwiftData oder In-Memory-Dictionary mit UserDefaults-Persistenz? | Mittel — vor US-2 entscheiden |
| Strava vs. Polar als v1.1-Quelle: Entscheid und ADR | Mittel — vor v1.1-Sprint |
| Hevy Events-Endpoint ist als "early development" markiert — Fallback-Strategie bei Breaking Change | Niedrig — beobachten |
