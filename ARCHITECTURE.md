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

### ADR-1: Kein Backend-Proxy im PoC
- **Entscheidung:** Direkter API-Call vom iOS-Client zu Claude API
- **Alternativen:** Serverless Function (Vercel/Supabase Edge) als Proxy
- **Begründung:** Zielgruppe verwaltet bereits API-Keys (Hevy Pro). PoC-Komplexität minimieren.
- **Risiko:** Claude API-Key liegt im Keychain — bei Gerätekompromittierung exponiert.
- **Revisit:** Vor v1.0-Launch obligatorisch.

### ADR-2: Native iOS statt WebView/React Native
- **Entscheidung:** Native SwiftUI
- **Alternativen:** React Native, Flutter, WebView
- **Begründung:** iOS Keychain-Integration (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) ist in native einfacher und sicherer. Kein WebView, der API-Keys exponieren könnte.

### ADR-3: Connector-Interface von Beginn an
- **Entscheidung:** Generisches `FitnessConnector`-Protocol vor erstem Hevy-Connector implementieren
- **Begründung:** Strava als zweite Quelle ist strategische Absicherung (R1 in PROJECT.md). Später ohne Refactor einbindbar.
- **Konkretisierung:** `ConnectorCredentials` ist ein Enum mit `.apiKey` (Hevy) und `.oauthTokens` (Strava) — damit bleibt das Interface stabil, obwohl die Auth-Mechanismen grundverschieden sind.

### ADR-6: Delta-Sync via Hevy Workout Events
- **Entscheidung:** Nach dem initialen vollständigen Load (`GET /v1/workouts`) werden Folge-Syncs ausschliesslich über `GET /v1/workouts/events?since=<timestamp>` durchgeführt.
- **Begründung:** Hevy erlaubt max. 10 Workouts pro Page — ein vollständiger Reload wäre bei jedem App-Start kostspielig. Der Events-Endpoint liefert nur Änderungen (created/updated/deleted) seit dem letzten Sync.
- **Letzter-Sync-Zeitstempel:** Wird lokal in `UserDefaults` (kein sensitiver Wert) gespeichert.
- **Risiko:** Events-Endpoint ist als "early development" markiert — Breaking Changes möglich.

### ADR-7: Strava Token Refresh im Connector kapseln
- **Entscheidung:** Der `StravaConnector` prüft vor jedem API-Call ob `expiresAt < now + 60s` und führt bei Bedarf automatisch einen Token-Refresh durch (POST `https://www.strava.com/api/v3/oauth/token`).
- **Begründung:** Strava Access Tokens laufen ab. Die iOS-App hat keinen Hintergrund-Service — der Refresh muss inline im Connector passieren, transparent für den Aufrufer.
- **Keychain:** Drei getrennte Einträge (`access_token`, `refresh_token`, `token_expiry`) statt einem, damit der Refresh-Token nie unnötig gelesen wird.
- **Scope:** Minimum-Scope `activity:read_all` für `fetchActivities(since:)`.

### ADR-4: English-only UI (Definition of Done)
- **Entscheidung:** Alle UI-Strings, Fehlermeldungen und der System-Prompt sind auf Englisch
- **Begründung:** Kein i18n-Framework im PoC. Wird als DoD-Kriterium geführt, nicht als Feature.

### ADR-5: AI-Inference-Region — PoC vs. v1.0
- **Kontext:** Trainingsdaten sind Gesundheitsdaten nach nDSG Art. 5 lit. c. Die Claude API (Anthropic) ist in den USA gehostet. Die Schweiz hat für die USA **keinen Angemessenheitsbeschluss** — eine Drittlandübermittlung erfordert eine zusätzliche Schutzgrundlage.
- **PoC-Entscheidung:** Direkter Call zum Claude API (USA). Schutzgrundlage: AVV/DPA mit Anthropic (vom FitBuddy-Team abgeschlossen) + explizite informierte Einwilligung im Onboarding (US-4 AC4). Zulässig für akademischen PoC / TestFlight-Distribution.
- **v1.0-Entscheidung (geplant):** Wechsel auf **AWS Bedrock + Claude in Region `eu-central-1` (Frankfurt)**. Die Schweiz hat für EU/EWR eine Angemessenheitsfeststellung getroffen — Daten verlassen damit die CH/EU-Rechtszone nicht. Das eliminiert die Drittlandübermittlung in die USA vollständig.
- **Architektur v1.0:**
  ```
  iOS App → AWS Bedrock API (Frankfurt, eu-central-1) → Claude-Modell
  ```
  Alternativ: schlanker Proxy (AWS Lambda / Azure Function) in der Schweiz oder Deutschland, der den Bedrock-Call kapselt und den iOS-Client vom AWS-SDK entkoppelt.
- **Alternativen geprüft:**
  - Azure Switzerland North (Zürich): Claude **nicht verfügbar** — nur OpenAI-Modelle.
  - Direkter Bedrock-Call vom iOS-Client: möglich (AWS Signature V4), erhöht aber Client-Komplexität erheblich.
  - Eigener Proxy-Server in CH: löst USA-Problem nicht, wenn Proxy seinerseits an Anthropic direkt weiterleitet.
- **Risiko PoC:** Vertretbar mit AVV + Consent. Muss vor kommerziellem Launch auf Bedrock EU migriert werden.

## Offene Architektur-Fragen

| Frage | Priorität |
|---|---|
| Apple Health: Schlaf, HRV, Ruheherzrate — IN oder OUT? Wenn IN: passiver HealthKit-Zugriff, kein Connector nötig | Hoch — vor Architektur-Story entscheiden |
| Fehlerzustand 401: harter Logout vs. weicher Banner | Mittel — Empfehlung: harter Logout im PoC |
| US-3 (AI-Analyse) Epic: in Child Stories aufteilen (Prompt-Design, UI, Error-Handling, Disclaimer) | Hoch — vor Sprint-Planung |
| Body Measurements (`GET /v1/body_measurements`) als optionaler AI-Kontext für US-3? Liefert Gewicht, Körperfett, Umfänge — ermöglicht Kraft-zu-Gewicht-Verhältnis-Empfehlungen | Mittel |
| `ExerciseTemplateCache`: SwiftData oder CoreData? Oder genügt ein In-Memory-Dictionary mit UserDefaults-Persistenz? | Mittel — vor US-2 entscheiden |
| Hevy Events-Endpoint ist als "early development" markiert — Fallback-Strategie bei Breaking Change definieren | Niedrig — beobachten |
