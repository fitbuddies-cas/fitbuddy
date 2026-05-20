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
│  │  fitbuddy.strava.token          │               │
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

> **Architekturentscheid:** Obwohl ein Backend-Proxy für AI-Calls grundsätzlich Best Practice wäre, wird im PoC der Claude API-Key direkt im Keychain gespeichert. Begründung: Zielgruppe sind technikaffine Hevy-Pro-User, die bereits gewohnt sind, API-Keys zu verwalten. Vereinfacht den PoC erheblich. Revisit vor v1.0-Launch.

## Connector-Interface

Alle Datenquellen implementieren dasselbe Interface. Hevy ist der erste Connector — nicht der einzige.

```swift
protocol FitnessConnector {
    func connect(credentials: ConnectorCredentials) async throws
    func validate() async throws -> Bool
    func fetchActivities(since: Date) async throws -> [Activity]
    func disconnect()
}
```

**Keychain-Keys (je eigener Eintrag, nie gemischt):**
- `fitbuddy.hevy.apikey`
- `fitbuddy.claude.apikey`
- `fitbuddy.strava.token`

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
    let muscleGroup: String
    let sets: [ExerciseSet]
}

struct ExerciseSet {
    let weightKg: Double
    let reps: Int
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

**Eingabe an LLM:** Strukturierte Trainingsdaten der letzten 4 Wochen (Volumen, Frequenz, Übungshistorie).

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
| API erreichbar | Frische Daten laden, Cache aktualisieren, Sync-Zeitstempel setzen |
| API nicht erreichbar | Gecachte Daten anzeigen mit Hinweis auf letzten Sync (US-2 AC2) |
| Pull-to-Refresh (US-10) | Neuer API-Call erzwingen, bei Fehler Cache behalten |
| HTTP 401 | Key aus Keychain löschen, Onboarding-Flow starten (US-1 AC3) |

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
