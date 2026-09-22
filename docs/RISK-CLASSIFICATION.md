# AI Agent Risk Classification — FitBuddy

> Ergebnisse des Risiko-Rechners (Teaching Version), bewertet am 05.08.2026,
> nachgeführt auf den Stand nach US-15 (Polar als dritte Quelle, Multi-Provider-LLM).
> Zwei Einstufungen: das **Produkt** (FitBuddy App) und der **Entwicklungsprozess** (Claude Code).
> Dieses Dokument ist die dokumentierte Risikonotiz für das PoC (v0).
> Präsentationsfassung: [`risk-classification-presentation.html`](risk-classification-presentation.html)

## 1. Produkt — FitBuddy App

### Risk Tier: CRITICAL

**Gate:** Explizites Sign-off + Human-in-the-Loop

| Achse | Stufe | Einstufung |
|---|---|---|
| Surface | 2 | Uses knowledge sources |
| Data | 4 | Payment, prices & special category |
| Autonomy | 2 | Generates text only |
| Exposure | 4 | Multiple or uncontrolled boundaries |

### Herleitung des Tiers

* Basis-Level 3 (höchste Achse = 3).
* Kombination gefeuert: sensible Daten × verlassen unsere Jurisdiktion (+1) → Level 4.
* **Red Line ausgelöst:** Besondere Kategorien von Daten (Gesundheitsdaten) werden an ein Modell ausserhalb der Kontrolle der Organisation gesendet → **Critical** (übersteuert die Arithmetik).

### Kontext FitBuddy

* **Data 4** greift wegen der *besonderen Kategorie*: Trainingsdaten sind Gesundheitsdaten nach nDSG Art. 5 lit. c. Zahlungsdaten verarbeitet FitBuddy nicht.
* **Autonomy 2:** Claude generiert ausschliesslich Text (Trainingsempfehlung). Kein Tool-Use, kein Write-back nach Hevy (US-12 = Won't). Die Umsetzung jeder Empfehlung liegt beim User — das ist zugleich der geforderte Human-in-the-Loop.
* **Exposure 4:** Daten verlassen das Gerät zu bis zu sechs externen Empfängern, je nachdem, was der User verbindet. Als **Quellen** der Trainingsdaten: Hevy, Strava (USA, ADR-010) und Polar Electro Oy (Finnland/EU, ADR-011). Als **Empfänger der Analyse-Daten**: der gewählte LLM-Anbieter — Anthropic (USA), Google (USA) oder Mistral AI (EU), in der vom User gesetzten Prioritätsreihenfolge (ADR-007). Quellen und LLM-Anbieter sehen einander nie: Strava und Polar erhalten ausschliesslich die Autorisierung und die Lese-Anfragen der nutzereigenen API-Application, nie Hevy-Daten und nie die Analyse.

## 2. Entwicklungsprozess — Claude Code

### Risk Tier: CRITICAL

**Gate:** Explizites Sign-off + Human-in-the-Loop

| Achse | Stufe | Einstufung |
|---|---|---|
| Surface | 4 | Verändernde Tools |
| Data | 3 | Vertraulich / Secrets |
| Autonomy | 4 | Plans and executes |
| Exposure | 4 | Multiple or uncontrolled boundaries |

### Herleitung des Tiers

* Basis-Level 4 (höchste Achse = 4): autonomer Agent × zustandsverändernde Tools × Daten verlassen unsere Jurisdiktion → **Critical**.

### Kontext Entwicklungsprozess

* **Surface 4:** Claude Code editiert Dateien, führt Shell-Befehle aus, erstellt Branches und PRs — Werkzeuge, die Zustand verändern.
* **Data 3:** Quellcode und interne Doku sind vertraulich; auf der Entwicklermaschine liegen potenziell API-Keys/Secrets.
* **Autonomy 4:** Der Agent plant eigene Schritt-Sequenzen und führt sie aus (verkettete Tools bis zum Ziel).
* **Exposure 4:** Kontext geht an Anthropic (USA), Code zu GitHub, Tools erreichen weitere Dienste.

### Massnahmen Entwicklungsprozess

**Umgesetzt:**

* Kein Direkt-Commit auf `main`/`develop`: Pre-Commit-Hook blockt (PR #51); alles läuft über PRs mit min. 1 Review.
* Human Review jedes AI-generierten Diffs vor dem Merge; Claude-Pre-Review (`/code-review`) bei grösseren PRs.
* Leitplanken in `CLAUDE.md`: Konventionen, geprüfte Architektur-Entscheide und Scope-Regeln steuern den Agenten.
* Tests als Pass/Fail-Gate: Unit-Test-Pflicht für ViewModels/Services; Build + Tests vor jedem Commit.
* Gestufte Releases: `develop` → `main` nur 1× wöchentlich als gebündelter, reviewter PR.

**Offen:**

* Secrets konsequent aus dem Agent-Kontext halten: echte API-Keys nie in Dateien im Repo-Baum; `.gitignore`-Abdeckung prüfen.
* Permission-Regeln schärfen: destruktive Befehle (push, delete) nur mit expliziter Bestätigung — kein Blanko-Auto-Approve.
* Named Owner + Sign-off: pro Release eine benannte Person, die das Go-Live explizit freigibt.

## 3. Erforderliche Kontrollen & Pflichten (beide Kontexte)

### Always on — nie abschaltbar

* Prompt-Injection- und Jailbreak-Erkennung
* Harmful-Content-Filter
* Schutz der System-Instructions und Tool-Namen
* AI-Offenlegung gegenüber dem User

### Abschalten von Sicherheitschecks

Red-Line-Checks können überhaupt nicht gelockert werden. Alles andere braucht explizites Sign-off.
Auf diesem Level ist eine Ausnahme eine Entscheidung mit Namen dran — keine Konfigurationsänderung.

### Compliance-Pflichten

| Pflicht | Umsetzung in FitBuddy (v0) |
|---|---|
| AI-Offenlegung gegenüber dem User (EU AI Act, Art. 50) | Consent-Screen im Onboarding (US-4 AC4) |
| Interaktion dokumentiert | Analyse-Zusammenfassung mit Quellen & Zeitraum (US-6 AC1) |
| Personendaten im Prompt dokumentiert (DSGVO/nDSG) | Datenschutzerklärung-Screen: bearbeitete Daten, Zweck, Empfänger |
| Sicherheitsrelevante Ereignisse geloggt | 401-Handling mit aktiver Benachrichtigung (US-1 AC3, US-8 AC2) |
| Datenschutz-Folgenabschätzung geprüft (DPIA nötig?) | Geprüft: volle DSFA ist v1-Material; für v0 genügt diese Risikonotiz + Consent (Entscheid siehe CLAUDE.md, Verhältnismässigkeit bei BFH-Datenschutzstelle) |
| Least-Privilege-Zugriff auf Tools und Daten | Hevy-Key nur lesend genutzt; Strava nur mit dem Scope `activity:read_all`, Polar nur mit `accesslink.read_all` (beide ohne Schreib-Scope, ADR-010/011); Keys, Client-Credentials und Tokens nur im Keychain (`ThisDeviceOnly`), nur in Services |
| Zahlungsdaten erreichen das Modell nie (PCI) | Nicht anwendbar — FitBuddy verarbeitet keine Zahlungsdaten |
| DPIA / FRIA abgeschlossen | Für v0 durch diese Notiz abgedeckt (siehe oben); vollständige DSFA vor kommerziellem Launch (v1) |
| Mensch bestätigt die Aktion | App: AI-Analyse nur auf Knopfdruck (US-3), Empfehlungen werden nie automatisch umgesetzt. Prozess: kein Merge ohne Human Review |

### Verantwortlichkeiten

* Dokumentiert und weiter — kein separates Approval
* Security-Review vor dem Merge
* Benannter Owner
* Pass/Fail-Test vor Go-Live
* Kill-Switch verifiziert
* Explizites Security-Sign-off vor Go-Live
* Dokumentiert, geloggt, zuordenbar

## 4. Einordnung

Das Tier **Critical** ist in beiden Fällen kein Blocker, sondern die ehrliche Beschreibung der Ausgangslage:

* **Produkt:** Die Red Line «Gesundheitsdaten an ein externes Modell» ist die inhärente Eigenschaft des Produkts (AI-Analyse von Trainingsdaten), nicht ein vermeidbarer Implementierungsfehler. Die Rechtsgrundlage ist im BYO-Key-Modell der API-Vertrag des eigenen Accounts beim jeweiligen Anbieter — bei Anthropic der DPA inkl. SCCs + Swiss Addendum, bei Google und Mistral die entsprechenden API-Bedingungen (ADR-007); Transparenz und Einwilligung sind über den Consent-Screen abgedeckt (US-4 AC4).
* **Entwicklungsprozess:** Das Tier folgt aus der Natur eines Coding-Agenten. Die Antwort ist nicht «abschalten», sondern Human-in-the-Loop an jeder Stelle, an der etwas Wirkung entfaltet: der User entscheidet über jede Trainingsempfehlung, das Team über jeden Merge.

Details: `docs/REQUIREMENTS.md` (Kap. 5, Security & Privacy) und `docs/adr/ADR-005-claude-api-usa-with-dpa.md`.
