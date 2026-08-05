# AI Agent Risk Classification — FitBuddy

> Ergebnis des Risiko-Rechners (Teaching Version), bewertet am 05.08.2026.
> Dieses Dokument ist die dokumentierte Risikonotiz für das PoC (v0).

## Risk Tier: CRITICAL

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
* **Exposure 4:** Daten verlassen das Gerät zu zwei externen Empfängern (Hevy, Anthropic/USA).

## Erforderliche Kontrollen & Pflichten

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
| Least-Privilege-Zugriff auf Tools und Daten | Hevy-Key nur lesend genutzt; Keys nur im Keychain (`ThisDeviceOnly`), nur in Services |
| Zahlungsdaten erreichen das Modell nie (PCI) | Nicht anwendbar — FitBuddy verarbeitet keine Zahlungsdaten |
| DPIA / FRIA abgeschlossen | Für v0 durch diese Notiz abgedeckt (siehe oben); vollständige DSFA vor kommerziellem Launch (v1) |
| Mensch bestätigt die Aktion | AI-Analyse nur auf Knopfdruck (US-3); Empfehlungen werden nie automatisch umgesetzt |

### Verantwortlichkeiten

* Dokumentiert und weiter — kein separates Approval
* Security-Review vor dem Merge
* Benannter Owner
* Pass/Fail-Test vor Go-Live
* Kill-Switch verifiziert
* Explizites Security-Sign-off vor Go-Live
* Dokumentiert, geloggt, zuordenbar

## Einordnung

Das Tier **Critical** folgt direkt aus der Red Line «Gesundheitsdaten an ein externes Modell» — es ist die inhärente Eigenschaft des Produkts (AI-Analyse von Trainingsdaten), nicht ein vermeidbarer Implementierungsfehler. Die Rechtsgrundlage dafür ist im BYO-Key-Modell der eigene Anthropic-DPA des Users (inkl. SCCs + Swiss Addendum); Transparenz und Einwilligung sind über den Consent-Screen abgedeckt (US-4 AC4). Details: `docs/REQUIREMENTS.md` (Kap. 5, Security & Privacy) und `docs/adr/ADR-005-claude-api-usa-with-dpa.md`.
