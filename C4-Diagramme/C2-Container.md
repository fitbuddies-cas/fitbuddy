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
