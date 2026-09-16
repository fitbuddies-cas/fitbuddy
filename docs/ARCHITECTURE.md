# FitBuddy — Architektur

> *Getrennt geführt: Ziele, Personas, Risiken → [README.md](../README.md) · User Stories, NFRs → [REQUIREMENTS.md](REQUIREMENTS.md) · Architekturentscheide (Detail) → [adr/](adr/)*

---

## Inhalt

- [Kontextabgrenzung](#kontextabgrenzung)
  - [Akteure & externe Systeme](#akteure--externe-systeme)
  - [Bewusste Leerstellen](#bewusste-leerstellen)
- [Lösungsstrategie](#lösungsstrategie)
- [Bausteinsicht](#bausteinsicht)
  - [L1 — Gesamtsystem (Container)](#l1--gesamtsystem-container)
  - [L2 — iOS App (Schichtenarchitektur)](#l2--ios-app-schichtenarchitektur)
  - [L3 — Komponenten](#l3--komponenten-folgt-in-modul-5--coding-phase)
  - [Connector-Interface](#connector-interface)
  - [Normalisiertes Datenmodell](#normalisiertes-datenmodell)
- [Laufzeitsicht](#laufzeitsicht)
  - [Kritischer Datenfluss — «Analysieren» (US-3)](#kritischer-datenfluss--analysieren--us-3)
  - [Caching-Strategie](#caching-strategie)
- [Querschnittliche Konzepte](#querschnittliche-konzepte)
  - [AI-Einsatzstrategie](#ai-einsatzstrategie)
  - [Swift Concurrency-Konvention](#swift-concurrency-konvention)
- [Architekturentscheide](#architekturentscheide)
- [Risiken & Technische Schulden](#risiken--technische-schulden)
- [Offene Fragen](#offene-fragen)
  - [Widersprüche & Unklarheiten](#widersprüche--unklarheiten)
  - [Offene Architektur-Fragen](#offene-architektur-fragen)

---

## Kontextabgrenzung

```mermaid
flowchart TB
    classDef person fill:#08427b,color:#fff,stroke:#052e56
    classDef system fill:#1168bd,color:#fff,stroke:#0b4884
    classDef ext fill:#6b6b6b,color:#fff,stroke:#454545
    classDef platform fill:#438dd5,color:#fff,stroke:#2e6295
    classDef excluded fill:#e0e0e0,color:#888,stroke:#bbb,stroke-dasharray:4 4

    subgraph KEY["Key-Beschaffung (einmalig, vor Onboarding)"]
        HEVYAPP["Hevy-App / Website"]:::ext
        CONSOLE["Anthropic Console"]:::ext
    end

    USER["User\n[Endnutzer]"]:::person
    FITBUDDY["FitBuddy\n[Native iOS-App · kein Backend]"]:::system

    subgraph APIS["Externe APIs"]
        direction LR
        HEVYAPI["Hevy API\n"]:::ext
        CLAUDEAPI["Anthropic Claude API\nAI-Empfehlungen"]:::ext
    end

    subgraph ONDEVICE["On-Device / Plattform"]
        direction LR
        KEYCHAIN[("iOS Keychain\nAPI-Keys + Consent")]:::platform
        ICLOUD["iCloud-Backup\n✗ ausgeschlossen"]:::excluded
    end

    USER -->|"holt Hevy-Key"| HEVYAPP
    USER -->|"holt Claude-Key"| CONSOLE
    USER -->|"nutzt App"| FITBUDDY
    FITBUDDY -->|"GET /workouts · HTTPS"| HEVYAPI
    FITBUDDY -->|"Prompt → Empfehlung · HTTPS"| CLAUDEAPI
    FITBUDDY <-->|"liest / schreibt"| KEYCHAIN
```

### Akteure & externe Systeme

| Element | Typ | Scope | Zweck |
|---|---|---|---|
| User | Person | — | Endnutzer (Training-Tracking + AI-Analyse) |
| FitBuddy Team | Person (Betreiber) | — | Entwickelt/betreibt App; kein eigener DPA mit Anthropic nötig (BYO-Key-Modell) |
| **FitBuddy** | Software-System | **PoC** | Native iOS-App, Datenaggregation + On-demand-AI |
| Hevy API | Externes System | PoC | Primäre Datenquelle (Kraft) |
| Anthropic Claude API | Externes System | PoC | LLM-Progressionsempfehlung (USA, Drittland) |
| Apple App Store Connect / TestFlight | Externes System | PoC | Distribution + Review-Gate + Privacy Report |
| iOS Keychain | Plattform-Service | PoC | Sichere Key-/Consent-Speicherung |
| Apple HealthKit | Plattform-Service | **offen** | Schlaf/HRV/RHR — Scope ungeklärt |
| iCloud-Backup | Externes System | **ausgeschlossen** | `isExcludedFromBackup` — kein Datenfluss |

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

**Kein Backend im PoC.** Der Claude API-Key wird direkt im Keychain gespeichert — vereinfacht den PoC erheblich, muss vor v1.0-Launch überprüft werden (→ ADR-004). Die Apple-native Technologiewahl (SwiftUI, SwiftData, URLSession, Swift Concurrency, Swift Charts) eliminiert Drittanbieter-Build-Abhängigkeiten und senkt die Einarbeitungshürde für ein gemischtes Team.

---

## Bausteinsicht

### C2 Container Diagram

FitBuddy besteht aus drei on-device-Bausteinen (iOS App, SwiftData Store, iOS Keychain) und kommuniziert direkt mit zwei externen APIs — kein Backend.

```mermaid
flowchart TB
    classDef person fill:#08427b,color:#fff,stroke:#052e56
    classDef system fill:#1168bd,color:#fff,stroke:#0b4884
    classDef ext fill:#6b6b6b,color:#fff,stroke:#454545
    classDef storage fill:#438dd5,color:#fff,stroke:#2e6295

    USER["User\n[Person]"]:::person

    subgraph IPHONE["FitBuddy — iPhone (iOS 26+)"]
        APP["iOS App\nSwift · SwiftUI · MVVM · Swift Concurrency\nURLSession · Swift Charts"]:::system
        SWIFTDATA[("SwiftData Store\n[SQLite · on-device]\nActivity-Cache 90 Tage")]:::storage
        KEYCHAIN[("iOS Keychain\n[Keychain Services]\nAPI-Keys + Consent")]:::storage
    end

    subgraph APIS["Externe APIs"]
        direction LR
        HEVY["Hevy API\n[REST]\nGET /workouts"]:::ext
        CLAUDE["Anthropic Claude API\nMessages API"]:::ext
    end

    USER -->|"nutzt (Touch / SwiftUI)"| APP
    APP <-->|"ModelContext · in-process"| SWIFTDATA
    APP <-->|"Security API · in-process"| KEYCHAIN
    APP -->|"GET /workouts · HTTPS"| HEVY
    APP -->|"Prompt → Empfehlung · HTTPS"| CLAUDE
```

| Container | Technologie | Kritischstes Risiko |
|---|---|---|
| **iOS App** | Swift · SwiftUI · MVVM · Swift Concurrency | Actor-Isolation-Fehler crashen erst zur Laufzeit |
| **SwiftData Store** | SwiftData (`@Model`) · SQLite · on-device | Stille Store-Löschung bei fehlender `VersionedSchema` |
| **iOS Keychain** | Keychain Services · `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Kein Recovery-Pfad bei verlorenem Key |

*Bewusst nicht vorhanden: Web-App, API-Server, Server-Datenbank, verteilter Cache, Message Queue (ADR-004).*

### L2 — iOS App (Schichtenarchitektur)

Zoom in den iOS-App-Container: vier strikt getrennte Schichten, die von oben nach unten Verantwortung delegieren.

```mermaid
flowchart TB
    classDef layer fill:#1168bd,color:#fff,stroke:#0b4884

    PRES["Presentation Layer\nSwiftUI Views · @State · @Binding\nDashboard (US-2) · Onboarding (US-4) · AI-Result-View (US-3)"]:::layer
    VM["ViewModel Layer · @MainActor\n@Observable ViewModels\nDashboardViewModel · AnalysisViewModel · OnboardingViewModel"]:::layer
    SVC["Service / Domain Layer\nInferenceService · Prompt-Build · 60s-Rate-Limit\nConnectorLayer · FitnessConnector-Protocol · Delta-Sync · Error-Routing"]:::layer
    DATA["Data Layer\nHevyConnector · URLSession · Pagination\nKeychainService · SecItemAdd / CopyMatching\nSwiftData Store · ModelActor · Activity / Exercise / ExerciseSet\nExerciseTemplateCache · SwiftData"]:::layer

    PRES --> VM --> SVC --> DATA
```

**Schichtregeln:**
- API-Keys berühren ausschliesslich den Data Layer — nie ViewModel oder View.
- Dashboard und InferenceService lesen ausschliesslich aus dem normalisierten `Activity`-Modell (ADR-006).
- Alle SwiftData-Schreibzugriffe laufen über `ModelActor`, nie direkt auf dem `@MainActor`.

---

## Laufzeitsicht

### Kritischer Datenfluss — «Analysieren» (US-3)

```
[1] Prioritätsreihenfolge lesen → LLMPriorityStore (UserDefaults, kein Key-Material)
[2] Keychain Read      → Key je konfiguriertem Provider lesen (async — KeychainService ist actor)
[3] SwiftData Query    → Workouts der letzten 4 + 4 Wochen laden (async, ModelActor)
[4] Prompt-Build       → Daten serialisieren (max_tokens serverseitig gedeckelt)
[5] HTTPS POST (SSE)   → Provider 1 (api.anthropic.com / generativelanguage.googleapis.com /
                          api.mistral.ai), Streaming; jeder Fehler → Provider 2, dann 3 (#79)
[6] Rate-Limit-Write   → UserDefaults, genau einmal pro Durchlauf, sobald ein Provider annimmt
[7] @MainActor Update  → SwiftUI rendert Text inkrementell + Provider-Badge
```

| Lücke | Konsequenz |
|---|---|
| Kein Token-Limit (Schritt 3) | `400 context_length_exceeded` bei 90 Tagen × vollem Trainingsvolumen |
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

### AI-Einsatzstrategie

Systemweite Regel: Claude wird nur dort eingesetzt, wo deterministischer Code keine ausreichende Lösung bietet.

| Bereich | AI? | Begründung |
|---|---|---|
| Progressions-Empfehlung | Ja (LLM) | Interpretation von Trainingsdaten erfordert Kontext-Verständnis |
| Datenabruf (Hevy API) | Nein | Klassische App-Logik |
| Aggregation & Visualisierung | Nein | Deterministisch, kein AI-Mehrwert |
| Key-Speicherung | Nein | iOS Keychain ist die richtige Lösung |

**Prompt-Engineering (US-3)** — Eingabe: Strukturierte Trainingsdaten der letzten 4 Wochen (Volumen, Frequenz, Übungshistorie, Set-Typen, RPE-Werte).

System-Prompt definiert: Verbotene Termini (Fachjargon), Ausgabeformat («1 Satz Lage · 1 konkrete Aktion · 1 optionaler Hinweis»), medizinischen Disclaimer, English-only output.

> **RPE-Nutzung:** `ExerciseSet.rpe` (6–10) gibt Claude Aufschluss über subjektive Anstrengung — ermöglicht Empfehlungen wie *"Your RPE has been consistently at 9+ for squats — consider a deload week."*

### Swift Concurrency-Konvention

Alle asynchronen Zugriffe folgen drei fixen Ausführungskontexten — gilt schichtübergreifend für alle Komponenten:

| Kontext | Verwendung | Grund |
|---|---|---|
| `@MainActor` | ViewModels · alle UI-State-Updates | SwiftUI erfordert Main Thread für Rendering |
| `ModelActor` | Alle SwiftData-Schreibzugriffe | Verhindert Datenkorrumption bei konkurrierenden Writes |
| `async` (background) | URLSession-Calls · Keychain-Zugriffe | Blockiert nicht den Main Thread |

**Regeln (gelten für alle Schichten):**
- SwiftData-Writes nie direkt auf `@MainActor` — immer über `ModelActor`
- ViewModel-Properties nie aus einem background Task ohne `await MainActor.run { }` setzen
- `HevyConnector` und `InferenceService` sind `async`-only — nie synchron aufgerufen

*`ExerciseTemplateCache` (Implementierungsdetail Data Layer) → folgt in L3 Bausteinsicht.*

---

## Architekturentscheide

| ADR | Titel | Status |
|---|---|---|
| [ADR-001](adr/ADR-001-local-database.md) | Lokale Datenbank — SwiftData als Persistenz-Technologie | Accepted |
| [ADR-002](adr/ADR-002-native-ios-swiftui.md) | Native iOS (SwiftUI) als Plattform | Accepted |
| [ADR-003](adr/ADR-003-keychain-this-device-only.md) | API-Keys im iOS Keychain mit `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Accepted |
| [ADR-004](adr/ADR-004-no-backend-proxy-poc.md) | Kein Backend-Proxy im PoC — Direkter API-Call vom iOS-Client | Accepted |
| [ADR-005](adr/ADR-005-claude-api-usa-with-dpa.md) | Claude API (USA) via Anthropic Commercial Terms im PoC, EU-Hosting vor v1.0 | Accepted |
| [ADR-006](adr/ADR-006-fitness-connector-protocol.md) | `FitnessConnector`-Protocol als Abstraktion ab Sprint 1 | Accepted |
| [ADR-007](adr/ADR-007-multi-provider-llm-byo-key.md) | Multi-Provider-LLM (Claude / Gemini / Mistral) im BYO-Key-Modell | Proposed |
| [ADR-008](adr/ADR-008-ios26-deployment-target.md) | Mindest-Deployment-Target iOS 26 | Accepted |
| [ADR-009](adr/ADR-009-self-hosted-ci-runner.md) | CI auf selbst gehostetem macOS-Runner | Accepted |
| [ADR-010](adr/ADR-010-strava-oauth-byo-app.md) | Strava-OAuth2 im BYO-App-Modell — Client-Credentials des Nutzers statt Backend | Accepted |
| [ADR-011](adr/ADR-011-polar-als-zweite-quelle.md) | Polar AccessLink als dritte Datenquelle, `Activity` additiv um `metrics` erweitert | Accepted |

---

## Risiken & Technische Schulden

### Architektonische Risiken

| # | Risiko | Impact | Mitigation |
|---|---|---|---|
| AR-1 | **Hevy API ohne SLA-Garantien** — Hevy hat Stabilität explizit nicht zugesichert (*"no guarantees — we might abandon this entirely"*). Hevy ToS auf kommerzielle API-Nutzung noch nicht geprüft. | Hoch | `FitnessConnector`-Protocol (ADR-006) — zweite Quelle ohne Umbau integrierbar |
| AR-2 | **Hevy Events-Endpoint als "early development" markiert** — Breaking Changes ohne Vorankündigung möglich | Mittel | Fallback auf vollständigen Re-Fetch bei HTTP-Fehler im `HevyConnector` einbauen |

*AR-1 entspricht R1 in [README.md](../README.md).*

### Technische Schulden

Bekannte Lücken im PoC-Design — vor Sprint 3 (AI-Integration) adressieren.

> TD-2 («Cooldown-Write nach API-Call») ist mit #117 hinfällig: Der 6h-Cooldown ist durch eine
> 60-s-Doppeltipp-Sperre ersetzt, ein Crash-Window kostet damit höchstens eine Wartesekunde und
> keine doppelte Analyse. Das Kostenlimit ist das Spending Limit im Account des Users (ADR-004).

| # | Lücke | Konsequenz | Handlungsbedarf |
|---|---|---|---|
| TD-1 | **Kein Token-Limit im Prompt-Build** | `400 context_length_exceeded` bei 90 Tagen × vollem Trainingsvolumen | Prompt-Fenster als Konstante definieren (→ W-2); Daten vor API-Call kürzen |
| TD-3 | **Kein Backgrounding-Handling beim Analyse-Call** | iOS beendet URLSession-Task nach ~30s — Analyse verloren, kein Benutzer-Feedback | `URLSession` mit `background`-Konfiguration oder explizites Timeout + Benutzer-Feedback |
| TD-4 | **Cert-Pinning für keinen Host umgesetzt** (QA-1, ADR-004) — mit #79 kommen `generativelanguage.googleapis.com` und `api.mistral.ai` zu `api.anthropic.com` und `api.hevyapp.com` dazu, mit ADR-010 zusätzlich `www.strava.com` | MITM im offenen WLAN kann API-Keys und Gesundheitsdaten abgreifen | `URLSessionDelegate` mit Public-Key-Pinning für alle fünf Hosts |
| TD-5 | **Polar-Client-Secret im Binary** (Nachtrag zu ADR-011) — Polars Token-Endpoint verlangt entgegen der ursprünglichen ADR-Annahme immer ein `clientSecret`; ohne Backend gibt es keinen sicheren Ort dafür. Nur für die CAS-Demo tragbar, nie über TestFlight verteilen. | Secret aus jedem verteilten Build extrahierbar | v1: Backend-Proxy oder BYO-App-Screen analog Strava (#139) |

---

## Offene Fragen

### Widersprüche & Unklarheiten

*Vor Sprint 1 auflösen.*

> W-4 («6h-Cooldown-Speicherort undefiniert») ist mit #117 aufgelöst: Die Sperre ist auf 60 s
> verkürzt und liegt als `fitbuddy.analysis.lastCallTimestamp` in `UserDefaults`
> (`AnalysisRateLimitStore`) — ein einzelner Skalar, wie der Sync-Zeitstempel (ADR-001).

> W-6 («Strava OAuth-Secret ohne Backend strukturell unlösbar») ist mit
> [ADR-010](adr/ADR-010-strava-oauth-byo-app.md) aufgelöst: Das Secret gehört nicht dem Team,
> sondern dem Nutzer. Er legt unter `strava.com/settings/api` seine eigene API-Application an
> und hinterlegt Client ID und Client Secret im Keychain — kein Secret im Binary, kein Backend,
> ADR-004 bleibt unverändert. Damit sind Strava **und** Polar ([ADR-011](adr/ADR-011-polar-als-zweite-quelle.md),
> PKCE-Public-Client, ebenfalls kein Backend nötig) beide als reale, zu Hevy gleichwertige
> Quellen umsetzbar — keine schliesst die andere aus.

| # | Widerspruch / Unklarheit | Betroffene Dokumente | Handlungsbedarf |
|---|---|---|---|
| W-3 | **Certificate Pinning: als aktiv formuliert, laut ADR noch nicht implementiert.** ADR-004 markiert es als «Pflicht in Sprint 2». | `ADR-004` | Formulierung korrigieren: «geplant, Sprint 2». |
| W-5 | **HealthKit: Entscheid gefordert, aber nirgends getroffen.** Das `Activity`-Modell ist deshalb noch nicht finalisierbar. | `ADR-006` | Entscheid blockiert Protocol-Design und Datenmodell. Empfehlung: OUT für PoC. |
| W-6 | **Dritte/zweite Quelle je ADR-010 und ADR-011: sowohl Strava als auch Polar sind umgesetzt**, nicht nur eine davon. `StravaConnector` (BYO-App-OAuth) und `PolarConnector` (PKCE-Public-Client) sind beide implementiert und getestet, beide konform zu ADR-004. Offen für v1: OAuth-Consent-UI und Onboarding-Einbindung für Polar, SwiftData-Persistenz der Cardio-Sessions, Migration v3 → v4. | `ADR-004`, `ADR-006`, `ADR-010`, `ADR-011` | v1: Polar-OAuth-Screen + Persistenz. Polar-Recovery/Sleep bleibt ausgeschlossen (session-, nicht workout-förmig — wie `W-5`). |

### Offene Architektur-Fragen

| Frage | Priorität |
|---|---|
| Apple Health: Schlaf, HRV, Ruheherzrate — IN oder OUT? Wenn IN: passiver HealthKit-Zugriff, kein Connector nötig, aber `Activity`-Modell und Privacy Manifest ändern sich | Hoch — blockiert Sprint 1 |
| AUP-Status geprüft: Kein AUP-Verbot für BYO-Key / Direct-from-Mobile. Anthropics Best Practice («eigener Key pro User») ist durch den BYO-Ansatz erfüllt. Intern in ADR-004 dokumentiert — kein Support-Gate. | Erledigt (Sprint 1) |
| Fehlerzustand 401: harter Logout vs. weicher Banner | Mittel — Empfehlung: harter Logout im PoC |
| `ExerciseTemplateCache`: SwiftData oder In-Memory-Dictionary mit UserDefaults-Persistenz? | Mittel — vor US-2 entscheiden |
