# FitBuddy — Diagramme

> *Alle Diagramme als Mermaid, direkt auf GitHub renderbar. Ergänzt [ARCHITECTURE.md](ARCHITECTURE.md) um die Ablaufsicht — Bausteine, Datenmodell und Entscheide stehen dort, die User Stories in [REQUIREMENTS.md](REQUIREMENTS.md).*

Schwerpunkt dieses Dokuments ist der **AI-Analyse-Teil** (Kapitel 5): vom Tap auf «Analyse starten» über Prompt-Build, Fallback-Kette und Karten-Validierung bis zur gespeicherten Empfehlung.

---

## Inhalt

- [1. Kontextdiagramm](#1-kontextdiagramm)
- [2. Use-Cases](#2-use-cases)
- [3. Ablauf — Onboarding](#3-ablauf--onboarding)
- [4. Ablauf — Sync der Trainingsdaten](#4-ablauf--sync-der-trainingsdaten)
- [5. AI-Analyse](#5-ai-analyse)
  - [5.1 Überblick](#51-überblick--was-beim-tap-auf-analysieren-passiert)
  - [5.2 Sequenzdiagramm](#52-sequenzdiagramm--ein-vollständiger-analyse-lauf)
  - [5.3 Prompt-Build](#53-prompt-build--fenster-profil-und-token-budget)
  - [5.4 Fallback-Kette](#54-fallback-kette-über-die-llm-provider)
  - [5.5 Karten-Validierung](#55-karten-validierung--jede-zahl-ist-die-der-app)
  - [5.6 Zustände des Analyse-Screens](#56-zustände-des-analyse-screens)
- [6. Wo die Diagramme im Code stehen](#6-wo-die-diagramme-im-code-stehen)

---

## 1. Kontextdiagramm

FitBuddy läuft vollständig auf dem iPhone. Es gibt kein Backend: Die App spricht direkt mit drei Trainingsquellen und bis zu drei LLM-Providern, jeweils mit den Keys des Nutzers (BYO-Key, [ADR-004](adr/ADR-004-no-backend-proxy-poc.md), [ADR-007](adr/ADR-007-multi-provider-llm-byo-key.md), [ADR-010](adr/ADR-010-strava-oauth-byo-app.md), [ADR-011](adr/ADR-011-polar-als-dritte-quelle.md)).

```mermaid
flowchart TB
    classDef person fill:#08427b,color:#fff,stroke:#052e56
    classDef system fill:#1168bd,color:#fff,stroke:#0b4884
    classDef ext fill:#6b6b6b,color:#fff,stroke:#454545
    classDef platform fill:#438dd5,color:#fff,stroke:#2e6295

    USER["User<br/>[Endnutzer]"]:::person

    subgraph KEYS["Key-Beschaffung — einmalig, im Account des Users"]
        direction LR
        HEVYACC["Hevy Pro<br/>API-Key"]:::ext
        OAUTHACC["Strava / Polar<br/>eigene API-App"]:::ext
        LLMACC["Anthropic / Google /<br/>Mistral Console"]:::ext
    end

    FITBUDDY["FitBuddy<br/>[Native iOS-App · kein Backend]<br/>Dashboard · AI-Analyse · Verlauf"]:::system

    subgraph SOURCES["Trainingsquellen"]
        direction LR
        HEVY["Hevy API<br/>Kraft"]:::ext
        STRAVA["Strava API<br/>Ausdauer · OAuth2"]:::ext
        POLAR["Polar AccessLink<br/>Ausdauer · OAuth2"]:::ext
    end

    subgraph LLM["LLM-Provider — Prioritätsreihenfolge des Users"]
        direction LR
        CLAUDE["Anthropic Claude<br/>USA"]:::ext
        GEMINI["Google Gemini<br/>USA"]:::ext
        MISTRAL["Mistral AI<br/>EU"]:::ext
    end

    subgraph ONDEVICE["On-Device"]
        direction LR
        KEYCHAIN[("iOS Keychain<br/>API-Keys · Tokens · Consent")]:::platform
        SWIFTDATA[("SwiftData Store<br/>Trainings-Cache 90 Tage<br/>Analyse-Historie max. 20")]:::platform
    end

    USER -->|"holt Keys"| HEVYACC
    USER -->|"legt App an"| OAUTHACC
    USER -->|"holt Keys"| LLMACC
    USER -->|"nutzt App"| FITBUDDY

    FITBUDDY -->|"GET /workouts · HTTPS"| HEVY
    FITBUDDY -->|"GET /athlete/activities · HTTPS"| STRAVA
    FITBUDDY -->|"GET /exercises · HTTPS"| POLAR
    FITBUDDY -->|"Prompt + JSON-Schema · HTTPS"| CLAUDE
    FITBUDDY -.->|"Fallback"| GEMINI
    FITBUDDY -.->|"Fallback"| MISTRAL
    FITBUDDY <-->|"liest / schreibt"| KEYCHAIN
    FITBUDDY <-->|"liest / schreibt"| SWIFTDATA
```

**Bewusst nicht vorhanden:** Server, User-Accounts, Push-Dienst, Analytics, iCloud-Backup der App-Daten.

---

## 2. Use-Cases

Mermaid kennt kein UML-Use-Case-Diagramm; die Darstellung bildet Akteur, Anwendungsfälle und externe Systeme als Graph ab. In Klammern die zugehörige User Story aus [REQUIREMENTS.md](REQUIREMENTS.md).

```mermaid
flowchart LR
    classDef actor fill:#08427b,color:#fff,stroke:#052e56
    classDef uc fill:#e8f1fb,color:#0b4884,stroke:#1168bd
    classDef ext fill:#6b6b6b,color:#fff,stroke:#454545

    USER(["User"]):::actor

    subgraph SYS["FitBuddy"]
        direction TB
        UC1(["Keys hinterlegen und<br/>Consent geben · US-1 / US-4"]):::uc
        UC2(["Quelle verbinden<br/>Strava / Polar · US-5"]):::uc
        UC3(["Dashboard ansehen<br/>US-2 / US-8"]):::uc
        UC4(["Daten neu laden<br/>US-10"]):::uc
        UC5(["Übungen suchen und filtern<br/>US-7"]):::uc
        UC6(["Progressionskurve ansehen<br/>US-9"]):::uc
        UC7(["AI-Analyse starten<br/>US-3 / US-14 / US-15"]):::uc
        UC8(["Analyse-Profil wählen<br/>Strength / Endurance / Overall · US-15"]):::uc
        UC9(["Datenbasis der Empfehlung prüfen<br/>US-6"]):::uc
        UC10(["Verlauf ansehen und löschen<br/>US-3 AC10 / AC11"]):::uc
        UC11(["Trainingsprofil pflegen<br/>US-13"]):::uc
        UC12(["Alle Daten löschen<br/>NFR Datenschutz"]):::uc
    end

    HEVY["Hevy API"]:::ext
    ENDURANCE["Strava / Polar"]:::ext
    LLMP["LLM-Provider"]:::ext

    USER --- UC1
    USER --- UC2
    USER --- UC3
    USER --- UC4
    USER --- UC5
    USER --- UC6
    USER --- UC7
    USER --- UC10
    USER --- UC11
    USER --- UC12

    UC7 -.->|"include"| UC8
    UC7 -.->|"include"| UC9
    UC3 -.->|"extend"| UC4

    UC1 --> HEVY
    UC2 --> ENDURANCE
    UC3 --> HEVY
    UC3 --> ENDURANCE
    UC7 --> LLMP
```

Nicht enthalten, weil bewusst ausgeschlossen (Kapitel 4 in REQUIREMENTS.md): Push-Wochenübersicht (US-11) und Rückschreiben nach Hevy (US-12).

---

## 3. Ablauf — Onboarding

Vier Schritte, zwei davon überspringbar. Ohne Consent gibt es keinen Zugang zur App (US-4 AC4).

```mermaid
flowchart TD
    START(["App-Start"]) --> CHECK{"Consent im Keychain<br/>und Hevy-Key gültig?"}
    CHECK -->|ja| MAIN(["Dashboard"])
    CHECK -->|nein| S1["Schritt 1 · Consent<br/>Gesundheitsdaten, Drittland, kein Medizinprodukt"]

    S1 --> C1{"bestätigt?"}
    C1 -->|nein| S1
    C1 -->|ja| SAVE1["Consent-Datum und -Version<br/>in den Keychain"]

    SAVE1 --> S2["Schritt 2 · Hevy API-Key"]
    S2 --> VAL{"GET /workouts<br/>HTTP 200?"}
    VAL -->|nein| ERR["Fehlermeldung mit Link<br/>zur Hevy-Key-Seite · Key wird verworfen"] --> S2
    VAL -->|ja| SAVE2["Key in den Keychain"]

    SAVE2 --> S3["Schritt 3 · LLM-Keys<br/>Claude / Gemini / Mistral in Prioritätsreihenfolge"]
    S3 -->|"Skip"| S4
    S3 -->|"Speichern"| SAVE3["Keys in den Keychain<br/>Reihenfolge in LLMPriorityStore — nie Key-Material"] --> S4

    S4["Schritt 4 · Trainingsprofil<br/>Ziel und Krafttrainings-Erfahrung"]
    S4 -->|"Skip for now"| DONE
    S4 -->|"Speichern"| SAVE4["TrainingProfileStore"] --> DONE

    DONE["Onboarding abgeschlossen"] --> MAIN

    MAIN -.->|"HTTP 401 bei einem Hevy-Call"| RESET["Key löschen · Session zurücksetzen<br/>US-1 AC3"] --> S2
```

Strava und Polar werden **nicht** im Onboarding verbunden, sondern in den Settings — Schritt 4 weiss deshalb nicht, ob eine Kraft- oder eine Ausdauersportlerin davorsitzt (US-13).

---

## 4. Ablauf — Sync der Trainingsdaten

`WorkoutSyncService` holt das 90-Tage-Fenster von jeder verbundenen Quelle parallel und schreibt die Ergebnisse nacheinander in den Store — eine Quelle, die scheitert, nimmt die anderen nicht mit.

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant VM as WorkoutListViewModel
    participant Sync as WorkoutSyncService
    participant Reg as ConnectorRegistry
    participant KC as KeychainService
    participant API as Hevy / Strava / Polar
    participant Store as WorkoutStore · ModelActor

    User->>VM: Dashboard öffnen oder Pull-to-Refresh
    VM->>Sync: syncRecentWorkouts()
    Sync->>KC: Keys und Tokens lesen
    KC-->>Sync: Credentials je Quelle

    par Quellen parallel
        Sync->>Reg: connector(for: .hevy) + fetchActivities(since:)
        Reg->>API: GET /workouts (paginiert)
        API-->>Reg: Workouts
    and
        Sync->>Reg: connector(for: .strava) + fetchActivities(since:)
        Reg->>API: Token-Refresh bei Bedarf, dann GET /athlete/activities
        API-->>Reg: Activities
    and
        Sync->>Reg: connector(for: .polar) + fetchActivities(since:)
        Reg->>API: GET /exercises
        API-->>Reg: Exercises
    end

    Reg-->>Sync: normalisierte Activity-Listen (ADR-006, ADR-012)

    loop je Quelle, sequenziell
        Sync->>Store: Fenster ersetzen
    end

    alt Hevy antwortet 401
        Sync->>KC: Hevy-Key löschen
        Sync-->>VM: Session-Reset — zurück ins Onboarding (US-1 AC3)
    else einzelne Quelle scheitert
        Sync-->>VM: SyncResult mit failures — Cache bleibt sichtbar (US-2 AC2, US-8)
    else alles gelungen
        Sync-->>VM: SyncResult + neuer Sync-Zeitstempel
    end

    VM-->>User: Sessions, Volumen, Muskelverteilung
```

Die Analyse löst **nie** einen Sync aus: Sie liest ausschliesslich den lokalen Cache, damit ein Tap auf «Analysieren» nicht an Konnektivität scheitert, die das Dashboard schon behandelt.

---

## 5. AI-Analyse

### 5.1 Überblick — was beim Tap auf «Analysieren» passiert

```mermaid
flowchart TD
    classDef app fill:#e8f1fb,color:#0b4884,stroke:#1168bd
    classDef ext fill:#6b6b6b,color:#fff,stroke:#454545
    classDef fail fill:#f8e3e3,color:#8b1f1f,stroke:#c0504d

    TAP(["User tippt «Analyse starten»"]) --> LOCK["State = running<br/>Button gesperrt, Spinner"]:::app
    LOCK --> READ["Cache lesen — 13 Wochen plus Vergleichsfenster"]:::app
    READ --> WIN{"Fenster mit Sessions?<br/>4 → 8 → 13 Wochen"}
    WIN -->|"nichts gefunden"| NODATA["Fehler: no training data<br/>kein Provider-Call"]:::fail
    WIN -->|"gefunden"| PROF["Profil auflösen<br/>Strength / Endurance / Overall load"]:::app
    PROF --> AGG["Aggregate rechnen<br/>Wochenvolumen, Muskelgruppen, Recovery, Interferenz"]:::app
    AGG --> CTX["Kontextzeile veröffentlichen<br/>Sessions pro Quelle und Domäne, Thin-Data-Warnung"]:::app
    CTX --> BUILD["Prompt bauen<br/>System-Prompt + Domänen-Sektionen, Token-Budget"]:::app
    BUILD --> CALL["Provider in Prioritätsreihenfolge rufen"]:::app
    CALL --> EXT["LLM antwortet als JSON-Report"]:::ext
    EXT --> PARSE{"Schema-konform?"}
    PARSE -->|nein| PROSE["Prosa-Darstellung<br/>US-14 AC5"]:::app
    PARSE -->|ja| VALID["Karten gegen die Aggregate prüfen<br/>AnalysisReportValidator"]:::app
    VALID --> PERSIST["Ergebnis speichern<br/>AnalysisResultStore, max. 20"]:::app
    PROSE --> PERSIST
    PERSIST --> SHOW(["Headline · Kontextzeile · Kurzfazit<br/>0–4 Karten · Full analysis · Disclaimer"])
    CALL -->|"alle Provider scheitern"| ERRV["Fehler-Screen mit Grund<br/>und Liste der versuchten Provider"]:::fail
```

### 5.2 Sequenzdiagramm — ein vollständiger Analyse-Lauf

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant View as AnalysisView
    participant VM as AnalysisViewModel · MainActor
    participant Cache as WorkoutStore / ExerciseCache
    participant TP as TrainingProfileStore
    participant Builder as AnalysisPromptBuilder
    participant Inf as InferenceService · actor
    participant KC as KeychainService · actor
    participant LLM as LLM-Provider
    participant Val as AnalysisReportValidator
    participant Hist as AnalysisResultStore

    User->>View: Analyse-Tab öffnen
    View->>VM: prepareProfileSelection()
    VM->>Cache: workoutSummaries(since:)
    Cache-->>VM: Sessions des Fensters
    VM-->>View: AnalysisProfileOptions — Picker nur bei zwei Domänen
    User->>View: Profil wählen (Default «Overall load»)
    View->>VM: select(profile) → AnalysisProfileStore

    User->>View: «Analyse starten»
    View->>VM: start()
    Note over VM: State = running, Slot synchron belegt<br/>Doppeltipp kann keine zweite Analyse kaufen

    VM->>Cache: workoutSummaries(since: widest.previousStart)
    Cache-->>VM: Sessions, beide Domänen
    VM->>VM: AnalysisWindow.resolve — 4 / 8 / 13 Wochen
    VM->>VM: profile.resolved(for: window)

    alt Profil deckt Kraft ab
        VM->>Cache: exerciseSummaries + exerciseProgression
        Cache-->>VM: Übungen mit letztem Arbeitsgewicht und 1RM-Trend
    end
    VM->>Cache: workoutDetail der letzten 7 Tage (Ø RPE)
    VM->>TP: profile
    TP-->>VM: Ziel und Erfahrung (oder nichts)

    VM->>VM: AnalysisContext veröffentlichen (US-6)
    VM->>Builder: make(summaries, exercises, window, profile, analysisProfile)
    Builder-->>VM: AnalysisPrompt (system, user, detail)

    VM->>Inf: streamAnalysis(systemPrompt, userPrompt)
    Inf->>KC: Key je Provider lesen
    KC-->>Inf: Keys in Prioritätsreihenfolge

    loop je Provider, bis einer antwortet
        Inf-->>VM: .attempting(provider)
        VM-->>View: Provider-Badge, bisher Empfangenes verwerfen
        Inf->>LLM: POST Prompt + JSON-Schema (SSE-Stream)
        alt Provider antwortet vollständig
            LLM-->>Inf: Chunks → gesammelte Antwort
            Inf-->>VM: .report(AnalysisReport) oder .text(Prosa)
        else Fehler, leere Antwort oder abgebrochener Stream
            LLM--xInf: 401 / 429 / 5xx / Transportfehler
            Note over Inf: nächster Provider, Fehler gemerkt
        end
    end

    VM->>Val: validate(report, against: evidence aus denselben Reads)
    Val-->>VM: ValidatedAnalysisReport — Karten mit App-Zahlen
    VM->>Hist: save(outcome, context, profil)
    Hist-->>VM: gespeichert, älteste über 20 entfernt
    VM-->>View: State = result
    View-->>User: Headline, Kontextzeile, Kurzfazit, Karten, Disclaimer
```

Nach 30 Sekunden ohne Antwort erscheint der Cancel-Button (US-3 AC1); der Request läuft weiter, bis der User ihn abbricht. Einen Cooldown zwischen zwei Läufen gibt es nicht — die harte Kostengrenze ist das Spending Limit im Provider-Account des Users.

### 5.3 Prompt-Build — Fenster, Profil und Token-Budget

Drei Entscheidungen hintereinander: **wie weit** zurück gelesen wird, **worüber** geurteilt wird und **wie viel** davon in den Prompt passt.

```mermaid
flowchart TD
    classDef step fill:#e8f1fb,color:#0b4884,stroke:#1168bd
    classDef fail fill:#f8e3e3,color:#8b1f1f,stroke:#c0504d

    A["Cache lesen: 13 Wochen + Vergleichsfenster"]:::step --> B{"4 Wochen<br/>mit Sessions?"}
    B -->|ja| W4["Fenster = 4 Wochen"]:::step
    B -->|nein| C{"8 Wochen?"}
    C -->|ja| W8["Fenster = 8 Wochen"]:::step
    C -->|nein| D{"13 Wochen?"}
    D -->|ja| W13["Fenster = 13 Wochen"]:::step
    D -->|nein| NONE["AnalysisFailure.noTrainingData"]:::fail

    W4 --> P
    W8 --> P
    W13 --> P

    P{"Welche Domänen liegen<br/>im Fenster? ActivityKind, ADR-012"}:::step
    P -->|"nur Kraft"| PS["Profil implizit «Strength»"]:::step
    P -->|"nur Ausdauer"| PE["Profil implizit «Endurance»"]:::step
    P -->|"beide"| PB["Auswahl des Users<br/>Default «Overall load»"]:::step

    PS --> SEC
    PE --> SEC
    PB --> SEC

    SEC["Sektionen je Profil zusammenstellen<br/>Strength · Endurance · Load · Profile"]:::step --> LAD

    LAD{"estimatedTokens ≤ 8 000?<br/>ein Sechzehntel des kleinsten Kontextfensters"}:::step
    LAD -->|"ja"| SEND["Prompt senden"]:::step
    LAD -->|"nein"| R2["Stufe 2: Sessionliste auf 20"]:::step
    R2 --> LAD2{"passt?"}
    LAD2 -->|ja| SEND
    LAD2 -->|nein| R3["Stufe 3: zusätzlich Übungen auf 6"]:::step
    R3 --> LAD3{"passt?"}
    LAD3 -->|ja| SEND
    LAD3 -->|nein| R4["Stufe 4: zusätzlich Wochenzeilen auf 4<br/>geht so oder so raus"]:::step
    R4 --> SEND
```

Jede Kürzung steht im Prompt selbst («N older sessions in this window omitted»), und die gewählte Stufe reist als `AnalysisPromptDetail` mit zur Validierung — keine Karte wird gegen eine Übung geprüft, die im Prompt nicht mehr stand.

**Was der Prompt enthält — und was nicht:**

| Enthalten | Nicht enthalten |
|---|---|
| Sessions, Wochenvolumen, Frequenz des Users | Benchmarks oder Normwerte fremder Nutzer (US-3 AC3) |
| Übungen mit letztem Arbeitsgewicht, Reps, RPE, 1RM-Trend | Herzfrequenz als Zielwert — weder im Schema noch im Prompt |
| Ausdauer als Wochenaggregat: km, h, Puls, Tempo, Trend | Rohdaten ausserhalb des aufgelösten Fensters |
| Wochenstruktur: Kraft- und Cardio-Tage, harte Tage in Folge | Klarnamen, Kontaktdaten, Keys |
| Trainingsprofil: Ziel und Erfahrung, falls gesetzt | — |

### 5.4 Fallback-Kette über die LLM-Provider

```mermaid
stateDiagram-v2
    [*] --> Kandidaten
    Kandidaten: Keys aus dem Keychain<br/>in der Reihenfolge des LLMPriorityStore
    Kandidaten --> KeinKey: kein Provider hat einen Key
    KeinKey: AnalysisFailure.missingAPIKey
    KeinKey --> [*]

    Kandidaten --> Provider1
    Provider1: .attempting(provider) senden<br/>Stream lesen und vollständig sammeln
    Provider1 --> Fertig: Antwort ist Report oder Prosa
    Provider1 --> Provider2: 401 / 429 / 5xx / Transportfehler / leere Antwort

    Provider2: nächster Provider<br/>bisher Empfangenes verwerfen
    Provider2 --> Fertig: Antwort ist Report oder Prosa
    Provider2 --> Provider3: Fehler

    Provider3: letzter Provider
    Provider3 --> Fertig: Antwort ist Report oder Prosa
    Provider3 --> Fehler: Fehler

    Fehler: Fehler des letzten Providers wird gezeigt —<br/>er beschreibt den Zustand, in dem der User steht
    Fertig: AnalysisOutcome + Provider-Badge
    Fertig --> [*]
    Fehler --> [*]

    Provider1 --> Abbruch: User bricht ab
    Provider2 --> Abbruch: User bricht ab
    Provider3 --> Abbruch: User bricht ab
    Abbruch: Kein Provider-Fehler —<br/>kein Weiterreichen, State = idle
    Abbruch --> [*]
```

Ein Abbruch durch den User ist ausdrücklich **kein** Providerfehler: Er beendet den Lauf, statt den nächsten Provider zu bezahlen.

### 5.5 Karten-Validierung — jede Zahl ist die der App

Das Schema garantiert die *Form* einer Karte, nicht ihre *Wahrheit*. Deshalb prüft `AnalysisReportValidator` jede Karte gegen dieselben Reads, aus denen der Prompt gebaut wurde.

```mermaid
flowchart TD
    classDef ok fill:#e6f2e6,color:#1f5f1f,stroke:#4c9a4c
    classDef down fill:#fdf3e0,color:#8a5a00,stroke:#d9a441
    classDef drop fill:#f8e3e3,color:#8b1f1f,stroke:#c0504d

    IN["Karte aus der Modellantwort"] --> KIND{"Art?"}

    KIND -->|progression| P1{"Übung stand im Prompt<br/>und fromKg = letztes Arbeitsgewicht?"}
    P1 -->|nein| NOTE
    P1 -->|ja| P2{"Schritt plausibel?<br/>max. 10 % bzw. 2.5 kg an der Hantel"}
    P2 -->|nein| NOTE
    P2 -->|ja| KEEP

    KIND -->|metric| M1{"Einheit passt zur analysierten Domäne?<br/>keine kg unter «Endurance», keine km unter «Strength»"}
    M1 -->|nein| NOTE
    M1 -->|ja| M2{"from = Zahl der App<br/>und to innerhalb 20 %?"}
    M2 -->|nein| NOTE
    M2 -->|ja| KEEP

    KIND -->|imbalance| I1{"Beide Muskelgruppen mit<br/>den Sätzen der App genannt?"}
    I1 -->|nein| NOTE
    I1 -->|ja| KEEP

    KIND -->|"recovery / interference"| R1{"Kennzahlen der App<br/>ersetzen die des Modells"}
    R1 --> KEEP

    KIND -->|note| KEEP

    KEEP["Karte behalten<br/>Zahlen der App, Begründung des Modells"]:::ok --> CAP
    NOTE["Downgrade zur Notiz<br/>Begründung bleibt lesbar"]:::down --> CAP
    NOTE -.->|"keine Begründung vorhanden"| DROP["Karte entfällt"]:::drop

    CAP["max. 4 Karten"] --> REC{"≥ 6 Trainingstage<br/>in den letzten 7 Tagen?"}
    REC -->|ja| FORCE["Recovery-Karte erzwingen<br/>Verdikt = recover, Headline ersetzt<br/>US-3 AC6 · US-14 AC4 · US-15 AC3"]
    REC -->|nein| VERD{"Verdikt «progress»,<br/>aber keine Karte stützt einen Schritt nach vorn?"}
    VERD -->|ja| HOLD["Verdikt = hold"]
    VERD -->|nein| OUT
    FORCE --> OUT
    HOLD --> OUT
    OUT(["ValidatedAnalysisReport"])
```

Die Recovery-Zählung ist **profilblind**: Vier Kraft-Sessions und drei Läufe sind sieben Trainingstage, nicht vier.

### 5.6 Zustände des Analyse-Screens

```mermaid
stateDiagram-v2
    [*] --> idle
    idle: Nur der Analyse-Button — oder die zuletzt gespeicherte Empfehlung
    idle --> running: «Analyse starten»
    running: Spinner · Provider-Badge · nach 30 s Cancel-Button
    running --> result: Antwort vollständig und gespeichert
    running --> error: Kein Key, Keychain gesperrt, kein Trainingsfenster,<br/>Cache-Fehler oder alle Provider gescheitert
    running --> idle: User bricht ab
    result: Headline · Kontextzeile · Kurzfazit · 0–4 Karten · Full analysis · Disclaimer
    result --> running: «New analysis»
    error --> idle: Fehler schliessen — letzte gespeicherte Empfehlung kehrt zurück
    error --> running: Erneut versuchen
    result --> [*]
```

Ein einziger Wert trägt den ganzen Screen: «läuft und ist fehlgeschlagen» ist nicht darstellbar, und jeder Pfad aus `running` endet in `result`, `error` oder `idle` — deshalb kann der Button nicht hängen bleiben.

---

## 6. Wo die Diagramme im Code stehen

| Diagramm | Massgebliche Typen |
|---|---|
| Kontext (1) | `FitBuddyApp`, `DataSourceStack`, `ConnectorRegistry`, `KeychainService` |
| Onboarding (3) | `OnboardingStep`, `OnboardingViewModel`, `ConsentViewModel`, `HevyKeyEntryViewModel`, `LLMKeysViewModel`, `TrainingProfileViewModel` |
| Sync (4) | `WorkoutSyncService`, `ConnectorRegistry`, `HevyConnector`, `StravaConnector`, `PolarConnector`, `WorkoutStore` |
| Analyse-Überblick und Sequenz (5.1 / 5.2) | `AnalysisViewModel`, `AnalysisRunReads`, `AnalysisState`, `AnalysisOutcome`, `AnalysisResultStore` |
| Prompt-Build (5.3) | `AnalysisWindow`, `AnalysisProfile`, `AnalysisPromptBuilder`, `AnalysisPromptBudget`, `AnalysisPromptDetail`, `StrengthPromptSection`, `EndurancePromptSection`, `LoadPromptSection` |
| Fallback-Kette (5.4) | `InferenceService`, `LLMProvider`, `LLMPriorityStore`, `AnthropicClient`, `GeminiClient`, `MistralClient`, `AnalysisEvent`, `AnalysisFailure` |
| Karten-Validierung (5.5) | `AnalysisReportValidator`, `AnalysisReportEvidence`, `AnalysisReportCard`, `RecoveryMetrics`, `InterferenceMetrics`, `MetricUnit` |
| Zustände (5.6) | `AnalysisState`, `AnalysisView`, `AnalysisResultView` |
