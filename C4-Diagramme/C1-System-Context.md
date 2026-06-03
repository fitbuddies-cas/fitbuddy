# FitBuddy — C4 Level 1: System Context

*System-Kontext-Diagramm nach dem C4-Modell. Zeigt FitBuddy als zentrales System, alle interagierenden Akteure und die externen Systeme an der Systemgrenze.*

---

## Diagramm

```
  ┌──────────────────────┐     reicht App ein          ┌─────────────────────────────┐
  │  FitBuddy Team       │── (Review, Privacy- ──────→ │  Apple App Store Connect /  │
  │  [Person · Betreiber]│    Manifest)                │  TestFlight                 │
  │  betreibt App; AVV/  │                             │  [Externes System]          │
  │  DPA mit Anthropic   │                             │  Gatekeeper + Distribution  │
  └──────────────────────┘                             └───────────────┬─────────────┘
                                                                       │ verteilt App +
                                                                       │ App Privacy Report
                                                                       ▼  (App landet beim User)

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
  │ → Claude-Key   │     └───────────────────┘    │   FitBuddy            │  ┌─────────────────────────────────────┐
  └────────────────┘  nutzt App, gibt Keys ein,   │   [Software-System]   │── Prompt ─→│ Anthropic Claude API (USA)│
                      fordert AI-Analyse an       │   Native iOS-App,     │  ←─ Empf.  │ [Externes System]         │
                                                  │   kein Backend        │  │ ⚠ Drittland USA (nDSG)              │
                                                  │                       │  └─────────────────────────────────────┘
                                                  │                       │  ┌────────────────────────────────────┐
                                                  │                       │- - - - - →│ Strava API (OAuth)   v1.1 │
                                                  │                       │ Ausdauer  │ Cardio-Daten (geplant)    │
                                                  └───────────┬───────────┘  └────────────────────────────────────┘
                                                              │
                 ON-DEVICE / PLATTFORM                        │
  ┌──────────────────────┐   ┌───────────────────────┐   ┌────┴─────────────────────┐
  │  iOS Keychain /      │   │  Apple HealthKit      │   │  iCloud-Backup           │
  │  Secure Enclave      │   │  [Plattform] (?)      │   │  [Externes System]       │
  │  [Plattform-Service] │   │  Schlaf / HRV / RHR   │   │  ✗ KEIN Datenfluss —     │
  │  API-Keys + Consent  │   │  → OFFENE ENTSCHEIDUNG│   │  isExcludedFromBackup    │
  └──────────────────────┘   └───────────────────────┘   └──────────────────────────┘
            ▲                          ▲                            ▲
            │ speichert / liest        │ liest passiv (NUR falls IN)│ ✗ Store darf NICHT
            │ Keys + Consent-Version   │                            │   ins Backup gelangen
            └──────────────────────────┴────────────────────────────┘
                                     FitBuddy
```

**Legende:** durchgezogen = PoC (jetzt) · gestrichelt `- -` = v1.1 (geplant) · `(?)` = offene Entscheidung · `✗` = bewusst geblockter Datenfluss

---

## 1. Beziehungen

| Von → Nach | Beschriftung |
|---|---|
| FitBuddy Team → Apple App Store Connect | Reicht App ein (App Review, Privacy-Manifest `PrivacyInfo.xcprivacy`) |
| Apple → User | Verteilt App via TestFlight; zeigt Netzwerk-Calls im App Privacy Report |
| FitBuddy Team → Claude API | Schliesst AVV/DPA mit Anthropic ab (Rechtsgrundlage Drittlandübermittlung) |
| User → Hevy-App / Website | Holt den Hevy-API-Key (manueller Schritt vor dem Onboarding) |
| User → Anthropic Console | Holt den Claude-API-Key — **eigener Anthropic-Account + Billing** |
| User → FitBuddy | Durchläuft Onboarding, gibt Keys ein, sieht 90-Tage-Dashboard, fordert AI-Analyse an, verwaltet Quellen |
| FitBuddy → Hevy API | Liest Trainings (`GET /workouts`), Bearer-Key im Header, HTTPS |
| FitBuddy → Claude API | Sendet strukturierten Trainings-Prompt, erhält Empfehlung — HTTPS, **Drittland USA** |
| FitBuddy ⇢ Strava API | (v1.1) OAuth-Flow, liest Ausdaueraktivitäten |
| FitBuddy → iOS Keychain | Speichert/liest API-Keys + Consent-Version, lokal auf dem Gerät |
| FitBuddy ⇠ HealthKit | (offen) Liest passiv Schlaf/HRV/RHR — nur falls Apple Health IN-Scope |
| FitBuddy ✗ iCloud-Backup | Kein Datenfluss: Store wird per `isExcludedFromBackup` ausgeschlossen |


## 2. Akteure & Systeme im Überblick

| Element | Typ | Scope | Zweck |
|---|---|---|---|
| User | Person | — | Endnutzer der App (Training-Tracking + AI-Analyse) |
| FitBuddy Team | Person (Betreiber) | — | Entwickelt/betreibt App, schliesst AVV/DPA ab |
| **FitBuddy** | Software-System | **PoC** | Native iOS-App, Datenaggregation + On-demand-AI |
| Hevy API | Externes System | PoC | Primäre Datenquelle (Kraft) |
| Anthropic Claude API | Externes System | PoC | LLM-Progressionsempfehlung (USA) |
| Apple App Store Connect / TestFlight | Externes System | PoC | Distribution + Review-Gate + Privacy Report |
| Hevy-App / Website | Externes System | PoC | Ausgabestelle des Hevy-API-Keys |
| Anthropic Console | Externes System | PoC | Ausgabestelle des Claude-Keys + User-Billing |
| iOS Keychain | Plattform-Service | PoC | Sichere Key-/Consent-Speicherung |
| Apple HealthKit | Plattform-Service | **offen** | Schlaf/HRV/RHR — Scope ungeklärt |
| iCloud-Backup | Externes System | **ausgeschlossen** | Privacy-Boundary sichtbar gemacht |
| Strava API | Externes System | v1.1 | Zweite Datenquelle (Cardio) |


## 3. Bewusste Leerstellen (kein Versehen)

Typische SaaS-Kontext-Systeme, die FitBuddy im PoC **absichtlich nicht** hat — explizit dokumentiert, damit sie nicht als Lücke missverstanden werden:

- **Kein Auth-Provider / keine User-Accounts:** „Auth" = Bearer-API-Keys im Keychain. Folge: kein Cross-Device, keine Account-Recovery, kein serverseitiger Logout.
- **Kein E-Mail / transaktionaler Versand:** Kein Kanal, um den User ausserhalb der App zu erreichen (relevant z. B. bei Consent-Versionswechsel, US-4 AC5).
- **Kein Payment:** Keine Monetarisierung im PoC. Bei Kommerzialisierung → App-Store-IAP/Stripe + Weitergabe der LLM-Kosten.
- **Kein APNs/Push** (US-11 = Won't) und **kein Crash-/Analytics-Dienst** (explizit out of scope) — als „nicht vorhanden" markiert, um späteren Scope-Creep zu vermeiden.

## Offene Kontext-Fragen

Spannungen, die der Kontext sichtbar macht, aber (noch) nicht auflöst — vor der Architektur-Story zu klären:

1. **BYO-Claude-Key vs. AVV/DPA — wer ist Controller?** Der User holt seinen Claude-Key in der Anthropic Console mit **eigenem Account und eigener Kreditkarte** (US-4 AC2). Die Calls laufen damit unter seinem Vertrag mit Anthropic — der vom Team abgeschlossene AVV/DPA (ADR-5, REQUIREMENTS_PO §6) deckt sie womöglich gar nicht. Folgen: Controller/Processor-Mapping unklar, Consent-Text (US-4 AC4) ggf. juristisch falsch, **LLM-Kosten liegen beim User** (der 6h-Cooldown schützt dessen Budget, nicht das des Teams). → Rechtliche Klärung nötig: Wer ist Verantwortlicher? Team-Key statt BYO?

2. **Strava-OAuth (v1.1) vs. „Kein Backend".** Stravas Token-Exchange erfordert ein **Client-Secret**. Ohne Backend bleiben nur: Secret in der App einbetten (exponiert) oder doch einen Proxy betreiben. Das zentrale Architektur-Versprechen „kein Backend" (ADR-1) ist in v1.1 möglicherweise nicht haltbar. → Entscheid: Backend/Proxy für OAuth akzeptieren oder Strava-Strategie überdenken.

3. **Zero-Retention / Training-Opt-out bei Anthropic.** Das Diagramm markiert „Drittland USA", sagt aber nichts darüber, ob Anthropic die übertragenen Gesundheitsdaten **speichert oder fürs Training nutzt**. Zero-Retention ist nicht Default und nDSG-relevant. → Klären, welcher API-Tier/welche Vertragsklausel Zero-Retention garantiert, und im Consent-Text abbilden.

---

*Stand: 2026-05-27 · Quellen: `PROJECT.md`, `REQUIREMENTS.md`, `ADRs/ADR-001-local-database.md`*
