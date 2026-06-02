# FitBuddy — C4 Level 2: Container Diagram

*Container-Sicht nach dem C4-Modell. Baut auf der System-Kontext-Sicht (`C4-System-Context.md`) auf und ist getrieben von den Top-3-Quality-Attributes: **QA-1 Security/Privacy · QA-2 Reliability · QA-3 Maintainability**.*

---

## Kernaussage zuerst

FitBuddy hat **keine Server-Tier**. Durch ADR-004 (kein Backend im PoC) gibt es **keine Web-App, keinen API-Server, keine Server-DB und keinen verteilten Cache**. Die einzige Deployment-Einheit ist die iOS-App auf dem iPhone. „Container" sind hier deshalb die App selbst plus ihre beiden lokalen Datenspeicher (SwiftData-Store, Keychain). Externe APIs (Hevy, Claude, Strava) sind keine Container, sondern fremde Systeme an der Grenze.

---

## Diagramm

```
                         ┌──────────────┐
                         │     User      │
                         │   [Person]    │
                         └──────┬───────┘
                                │ nutzt (Touch / SwiftUI, on-device)
                                ▼
  ╔══════════════════ FitBuddy — iPhone (iOS 17+) ════════════════════════╗
  ║                                                                        ║
  ║   ┌───────────────────────────────────────────────────┐               ║
  ║   │  iOS App                                            │               ║
  ║   │  [Container: Swift · SwiftUI · MVVM ·               │               ║
  ║   │   Swift Concurrency · URLSession · Swift Charts]    │               ║
  ║   │                                                     │               ║
  ║   │  Komponenten (→ C3): Präsentation · Connector-      │               ║
  ║   │  Layer · Inference-Service · Persistence-Manager    │               ║
  ║   └──┬──────────────────┬───────────────────────┬───────┘               ║
  ║      │ ModelContext     │ Security API           │ HTTPS               ║
  ║      │ (in-process)     │ (in-process)           │ (TLS, cert-pinned)  ║
  ║      ▼                  ▼                        │                     ║
  ║  ┌──────────────┐  ┌────────────────────┐        │                     ║
  ║  │ SwiftData     │  │ iOS Keychain        │        │                     ║
  ║  │ Store         │  │ [Container:         │        │                     ║
  ║  │ [Container:   │  │  Keychain Services] │        │                     ║
  ║  │  SQLite]      │  │  API-Keys + Consent │        │                     ║
  ║  │  Activity-    │  │  (verschlüsselt)    │        │                     ║
  ║  │  Cache (90 T) │  └────────────────────┘        │                     ║
  ║  └──────────────┘                                 │                     ║
  ╚═══════════════════════════════════════════════════┼═════════════════════╝
                                                       │
            ┌──────────────────────┬───────────────────┴─────┐
            ▼                      ▼                          ▼
   ┌─────────────────┐   ┌──────────────────────┐   ┌────────────────────┐
   │ Hevy API (REST) │   │ Anthropic Claude API │   │ Strava API (OAuth) │
   │ [Ext. System]   │   │ [Ext. System · USA]  │   │ [Ext. System] v1.1 │
   │ GET /workouts   │   │ Messages API         │   │ (geplant, - - -)   │
   └─────────────────┘   └──────────────────────┘   └────────────────────┘

  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
  v1.0 / v1.1 (NICHT im PoC):
  ┌────────────────────────────────────────────────────────────────────────┐
  │ Backend / Proxy  [Container: AWS Lambda + API Gateway, eu-central-1]     │
  │ Kapselt Bedrock-Region (ADR-5) und Strava-OAuth-Token-Exchange (Secret)  │
  └────────────────────────────────────────────────────────────────────────┘
```

**Legende:** durchgezogen = PoC · `- - -` = geplant/ausserhalb PoC

---

## 1. Container — was wir brauchen

| Container | Technologie | QA-Treiber | Begründung (1 Satz) |
|---|---|---|---|
| **iOS App** | Swift, SwiftUI, MVVM, Swift Concurrency, URLSession, Swift Charts | QA-3 | Eine native App deckt UI, Orchestrierung und Netzwerk ab — ohne Server-Tier der einfachste wartbare Aufbau für 3 Devs in 3 Monaten. |
| **SwiftData Store** (SQLite) | SwiftData (`@Model`) über SQLite, on-device | QA-2, QA-1 | Persistenter, relationaler Offline-Cache der 90-Tage-Trainingsdaten, der App-Kills überlebt und das Gerät nie verlässt (ADR-1). |
| **iOS Keychain** | Keychain Services / Security framework | QA-1 | Einziger Ort für API-Keys und Consent — hardware-gestützt verschlüsselt (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`). |
| *(v1.0/v1.1)* **Backend/Proxy** | AWS Lambda + API Gateway (`eu-central-1`) | QA-1, QA-3 | Erst nötig, wenn die Bedrock-Region (ADR-5) oder das Strava-OAuth-Secret einen serverseitigen Endpunkt erzwingen — bewusst nicht im PoC. |

## 2. Was wir bewusst NICHT brauchen

| Typischer Container | Warum nicht |
|---|---|
| Web-App / SPA | Kein Web-Frontend — native iOS only (ADR-2). |
| API-/Application-Server | Kein Backend im PoC (ADR-004); Calls laufen direkt vom Gerät. |
| Server-Datenbank (Postgres …) | Keine User-Daten auf fremden Servern — Kern des Privacy-Versprechens (QA-1). |
| Redis / verteilter Cache | Der „Cache" ist der lokale SwiftData-Store; bei Single-Device unnötig. |
| Message Queue / Worker | Keine Hintergrundjobs; AI ist on-demand (US-3), Push ist Won't (US-11). |

## 3. Kommunikation zwischen den Containern

| Von → Nach | Protokoll / Mechanismus | Zweck |
|---|---|---|
| User → iOS App | Touch / SwiftUI (on-device) | Bedienung |
| iOS App → SwiftData Store | `ModelContext` in-process (`ModelActor` für Background-Schreibzugriffe) | Activities lesen/schreiben, Offline-Cache |
| iOS App → iOS Keychain | Security API (`SecItemAdd`/`CopyMatching`) in-process | API-Keys + Consent sicher ablegen/lesen |
| iOS App → Hevy API | HTTPS/JSON REST, Bearer-Key im Header | `GET /workouts` — Trainingsdaten |
| iOS App → Claude API | HTTPS/JSON (Messages API), API-Key-Header | On-demand AI-Empfehlung (Drittland USA) |
| iOS App ⇢ Strava API | HTTPS / OAuth 2.0 | (v1.1) Ausdauerdaten |

Alle externen Verbindungen über TLS, mit **Certificate Pinning** (QA-1).


## Technologiewahl & das Team (3 Devs, 3 Monate, gemischter Background)

Die Auswahl ist bewusst **Apple-nativ und mainstream**, mit **null Drittanbieter-Abhängigkeiten**: SwiftUI, SwiftData, URLSession, Swift Concurrency und Swift Charts sind dokumentiert, von Apple gepflegt und ohne fremde Build-Toolchains nutzbar. Das senkt die Einarbeitungshürde für ein gemischtes Team (QA-3) und vermeidet, dass eine instabile Dependency im 3-Monats-Fenster zum Blocker wird. Der fehlende Server-Tier ist hier ein Vorteil: keine DevOps-, Auth- oder Deployment-Sub-Systeme, die das kleine Team zusätzlich tragen müsste.

---

*Stand: 2026-05-27 · Quellen: `C4-System-Context.md`, `ADRs/` (ADR-001, ADR-004), Quality Attributes (Security/Privacy · Reliability · Maintainability)*

---

## Kritische Analyse — 4 Fragen pro Container

| Container | 1. Warum diese Technologie, nicht die naheliegendste Alternative? | 2. Passt sie zu den Top-3 QAs? | 3. Kann das Team das wirklich bauen? | 4. Grösstes Risiko? |
|---|---|---|---|---|
| **iOS App** (Swift · SwiftUI · MVVM · Swift Concurrency · URLSession · Swift Charts) | Begründung im Dokument ("null Drittanbieter-Abhängigkeiten") ist korrekt, aber zu weich. Die eigentliche Antwort fehlt: SwiftData und Keychain sind native APIs, die mit React Native entweder nicht zugänglich oder fehleranfällig wären. | QA-1 ✓ (kein JS-Bridge-Layer), QA-2 ✓ (stabiler als Cross-Platform). QA-3 **bedingt**: SwiftUI + MVVM + Swift Concurrency + SwiftData + URLSession + Swift Charts gleichzeitig ist für ein Team mit gemischtem Background eine hohe kognitive Last. | Nicht alles. Certificate Pinning (NSURLSessionDelegate, Challenge-Handling) ist nicht trivial. `@MainActor` + `ModelActor` sind häufige Fehlerquellen — ohne iOS-Senior kostet das viel Zeit. | Swift Concurrency. Actor-Isolation-Fehler kompilieren in Xcode 16 ohne Fehler (nur Warnungen in Strict Concurrency), crashen aber zur Laufzeit oder erzeugen Datenkorruption im SwiftData-Store. |
| **SwiftData Store** (SQLite, on-device, 90-Tage-Cache) | Nicht begründet. SwiftData existiert seit WWDC 2023 — 2 Jahre alt. Core Data hat 20+ Jahre Battle-Testing und ist intern dieselbe Engine. Der Vorteil der `@Model`-Syntax rechtfertigt die Risiken für einen PoC nicht. | QA-1 ✓ (on-device). QA-2 **Nein**: SwiftData-Migrationen sind deutlich weniger ausgereift als Core Data. Bei einem 3-Monats-PoC wird sich das Datenmodell ändern — fehlgeschlagene Migrationen löschen den Store still. QA-3 ✓ für einfache Queries, ✗ für komplexe `#Predicate`-Ausdrücke. | Basis-CRUD ja. `ModelActor` für Background-Writes erfordert gutes Verständnis von Swift Concurrency und SwiftData-Threading — nicht anfängerfreundlich. | Stille Store-Löschung. Eine Datenmodell-Änderung ohne `VersionedSchema` löscht den gesamten 90-Tage-Cache ohne User-Feedback (QA-2-Versagen). |
| **iOS Keychain** (Keychain Services, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) | "Null Drittanbieter-Abhängigkeiten" zwingt zur rohen C-API (`SecItemAdd`, `SecItemCopyMatching`, `CFTypeRef`, `OSStatus`). Das ist die richtige Wahl für was, aber eine vermeidbare Schwierigkeit im wie — ein Swift-Wrapper wäre ~200 Zeilen, kein Framework-Risiko. | QA-1 ✓ (Secure Enclave-backed, richtiges Accessibility-Level). QA-2 **Risiko**: nach Deinstallation + Neuinstallation bleibt der Entry erhalten — aber nur wenn `kSecAttrService` und `kSecAttrAccount` identisch sind. Tippfehler = stiller zweiter Entry, alter Key "verloren". QA-3 ✗ (rohe API erschwert Lesbarkeit). | Einfaches Read/Write ja. `errSecDuplicateItem`-Handling (Update-statt-Add-Logik), Verhalten bei gesperrtem Gerät und Testing (Simulator ≠ Gerät) kosten unerwartet Zeit. | Kein Recovery-Pfad bei verlorenem oder korrumpiertem Key. Wenn die App den Claude-API-Key nicht mehr liest, ist der User blockiert — ohne erklärende Fehlermeldung. `REQUIREMENTS.md` erwähnt "Daten löschen", aber kein gezieltes Key-Recovery. |
| **Backend/Proxy** *(v1.0/v1.1)* (AWS Lambda + API Gateway · eu-central-1) | Nicht begründet. Für einen OAuth-Token-Exchange-Proxy wäre ein Cloudflare Worker billiger (kein Cold Start, $0 bis ~10K Requests/Tag, kein IAM-Wissen). Lambda + API Gateway ist die komplexeste Option für diesen Use Case. Warum eu-central-1 für einen Proxy der US-seitige Anthropic-API aufruft, steht nirgends. | QA-1 **Neuer Attack Vector**: der Endpoint muss selbst authentifiziert sein — sonst kann jeder den Proxy nutzen. API Gateway + Lambda Auth ist nicht trivial. QA-2 **Cold Starts** (500ms–2s) stehen im Widerspruch zu "Spinner sofort nach Tap". QA-3 ✗: AWS-Know-how (IAM, CDK/SAM, CloudWatch) — wer im Team hat das? | Wahrscheinlich nicht im 3-Monats-Fenster zusätzlich zum iOS-Projekt. IAM-Rollen, API-Gateway-Routes, Deployment-Pipeline, Monitoring — das ist ein eigenes Teilprojekt, kein Add-on. | Der Übergang PoC → v1.0 ist ein Umbau, kein Plugin. Auth-Flow, URL-Konfiguration und Error-Handling der iOS-App müssen angepasst werden. Dieser Gap ist aktuell als Fussnote behandelt, nicht als Risiko. |


---

## Kommunikationsanalyse — 3 Fragen pro Verbindung

| Verbindung | 1. Synchron oder Asynchron? | 2. Was passiert bei Ausfall? | 3. Bottleneck bei Last? |
|---|---|---|---|
| **User → iOS App** (Touch / SwiftUI) | Synchron auf dem Main Thread. SwiftUI-State-Change triggert Re-render. | App-Crash = User weg. Kein Fallback. | Kein Bottleneck — Single User, Single Device. |
| **iOS App → SwiftData Store** (ModelContext in-process) | Gemischt. Lesen: synchron auf `@MainActor`. Schreiben: sollte async via `ModelActor` laufen — in PoC-Code landet aber oft alles auf dem Main Thread. | Store-Korruption oder fehlgeschlagene Migration: App startet ohne Daten oder crasht. Kein Recovery dokumentiert. | `#Predicate`-Queries auf dem Main Thread blockieren den UI-Thread bei 90 Tagen × mehreren Workouts/Woche. Kein Pagination-Mechanismus vorgesehen. |
| **iOS App → iOS Keychain** (Security API in-process) | Synchron und blockierend — `SecItemCopyMatching` wartet auf den Keychain-Daemon. | Gerät gesperrt oder Keychain-Daemon-Fehler: API-Key nicht lesbar. Kein Graceful Fallback dokumentiert — App würde mit leerem Key einen 401 produzieren. | Kein Bottleneck. Keychain-Reads dauern <1ms. |
| **iOS App → Hevy API** (HTTPS/JSON REST) | Synchron im Request-Response-Sinne, ausgeführt auf einem async Task (blockiert nicht den Main Thread). | API down: kein frisches Daten-Refresh. Mit gefülltem SwiftData-Cache funktioniert die App im Offline-Modus. Bei leerem Cache (Erststart) sieht der User keine Daten — kein Empty-State dokumentiert. | Hevy gibt keine öffentlichen Rate-Limits an. Ein vollständiger 90-Tage-Sync über `GET /workouts` kann viele paginierte Requests erfordern — sequenziell und langsam. Kein paralleles Fetching dokumentiert. |
| **iOS App → Claude API** (HTTPS/JSON Messages API) | Synchron (Request-Response, 5–30s Wartezeit). Streaming (SSE) wäre möglich und würde erste Tokens nach ~1–2s liefern — ist aber nicht dokumentiert. | API down oder Rate Limit: Analyse scheitert, kein Fallback (kein lokales LLM). Unklar: läuft der 6h-Cooldown-Timer bei einem gescheiterten Call trotzdem? | **Grösster Bottleneck im System.** Latenz 5–30s. Prompt-Grösse nicht begrenzt: 90 Tage Trainingsdaten können das Token-Limit sprengen. Kein Truncation- oder Summarization-Mechanismus dokumentiert. |
| **iOS App ⇢ Strava API** (OAuth 2.0, v1.1) | Synchron (REST). OAuth-Token-Refresh ist ein zusätzlicher synchroner Schritt vor jedem Call. | Token abgelaufen und Refresh scheitert: User muss sich neu authorisieren. Ohne Backend-Proxy (ADR-004) muss das Client Secret im App-Bundle liegen — sicherheitskritisch. | Nicht im PoC. Kein Impact jetzt. |

---

## Kritischer Datenfluss — Nutzer tippt auf «Analysieren» (US-3)

```
User
 │  tippt «Analysieren»
 ▼
iOS App — ViewModel.requestAnalysis() [@MainActor]
 │
 ├─[1] Keychain Read ──────────────────────────────────── synchron, <1ms
 │      SecItemCopyMatching → Claude API-Key
 │      ⚠ Fehler hier: 401 bei leerem Key, keine erklärende UI
 │
 ├─[2] SwiftData Query ────────────────────────────────── sollte async sein
 │      Lade Workouts der letzten 90 Tage
 │      ⚠ Auf @MainActor = UI-Freeze bei grossen Datensätzen
 │
 ├─[3] Prompt-Build ───────────────────────────────────── in-process, CPU
 │      Serialisiere Workout-Daten → Text/JSON für Claude
 │      ⚠ Keine Token-Begrenzung: 90 Tage × 5 Sets × 3 Felder = potenziell
 │        >100k Tokens → API-Fehler oder hohe Kosten
 │
 ├─[4] HTTPS POST → Claude API ───────────────────────── 5–30s, externes Netz
 │      api.anthropic.com/v1/messages
 │      ⚠ Kein Streaming dokumentiert → UI zeigt Spinner bis Antwort komplett
 │      ⚠ Kein Retry bei Timeout; kein Handling bei Netzwechsel WiFi → LTE
 │      ⚠ App geht in Background während Call → Task wird gecancelt? Unklar
 │
 ├─[5] Response parsen ────────────────────────────────── in-process
 │      Extrahiere AI-Empfehlung aus JSON
 │
 ├─[6] SwiftData Write ────────────────────────────────── sollte async sein
 │      Speichere Empfehlung + Timestamp (für 6h-Cooldown)
 │      ⚠ Race Condition: App-Crash zwischen Schritt 4 und 6 →
 │        Cooldown-State verloren → User kann sofort neu analysieren →
 │        doppelte API-Kosten
 │
 └─[7] @MainActor State-Update ───────────────────────── synchron
        SwiftUI re-rendert Empfehlungs-View

Gesamtlatenz: 5–30s (dominiert durch Schritt 4)
Schwächste Stelle: Schritt 4 → 6 (externer Call + Write nicht atomar)
```

**Die drei undokumentierten Lücken im kritischen Pfad:**

| Lücke | Konsequenz |
|---|---|
| Kein Token-Limit für den Prompt (Schritt 3) | Claude-API gibt `400 context_length_exceeded` zurück — App zeigt generischen Fehler |
| Kein Cooldown-Write vor dem API-Call (Schritt 6 kommt nach Schritt 4) | Crash-Window ermöglicht doppelte Analyse-Kosten |
| Kein App-Backgrounding-Handling (Schritt 4) | iOS beendet URLSession-Task nach ~30s im Background — Analyse verloren, kein User-Feedback |

*Stand: 2026-06-02*
