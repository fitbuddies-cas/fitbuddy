# ADR-5: Claude API (USA) via Anthropic Commercial Terms im PoC, EU-Hosting vor v1.0

**Status:** Proposed
**Datum:** 2026-05-27
**Treiber-QA:** Security / Privacy (QA-1), Maintainability (QA-3)

## Kontext

Trainingsdaten gelten nach revDSG Art. 5 lit. c voraussichtlich als Gesundheitsdaten und unterliegen damit der höchsten Schutzkategorie. **Hinweis:** Die rechtliche Einordnung ist nicht trivial — Gewichts- und Wiederholungsdaten sind ambivalent; Herzfrequenz, Schlafdaten und explizite Körperwerte sind eindeutig. Für den PoC nehmen wir die strengste Interpretation an (alle Trainingsdaten = Gesundheitsdaten); diese Einordnung sollte vor v1.0 durch einen Datenschutzrechtler oder einen EDÖB-Leitfaden verifiziert werden.

Die Claude API von Anthropic ist in den USA gehostet; die Schweiz hat für die USA keinen allgemeinen Angemessenheitsbeschluss, sodass jede Übermittlung dorthin eine zusätzliche Schutzgrundlage benötigt. Als EU-nahe Alternativen stehen zur Verfügung:

- **AWS Bedrock `eu-central-1` (Frankfurt):** Claude-Modelle verfügbar; erfordert AWS-Setup, IAM, Signature V4 am Client.
- **Google Vertex AI `europe-west6` (Zürich):** Claude-Modelle verfügbar seit 2025; kein AWS-spezifischer Overhead, Google Cloud Authentifizierung.
- **Azure Switzerland North:** Führt aktuell nur OpenAI-Modelle — kein Claude.

Im 3-Monats-PoC ist keine vollständige EU-Hosting-Integration leistbar. Gleichzeitig ist ein kommerzieller v1.0-Launch ohne EU-Hosting nDSG-rechtlich nicht tragbar.

**Anthropic DPA-Recherche (Stand 27.05.2026):** Der Anthropic Data Processing Addendum (DPA, effektiv 24.02.2025) ist via Section C der Anthropic Commercial Terms of Service by reference inkorporiert, sobald ein Nutzer einen Paid-API-Account auf `console.anthropic.com` erstellt. Schedule 3 enthält EU-Standardvertragsklauseln (SCCs Module 2 und 3) sowie ein explizites Swiss Addendum (FADP/revDSG). Im BYO-Key-Modell ist **jeder Enduser selbst Anthropic-«Customer»**: Mit Erstellung des eigenen Anthropic-Accounts akzeptiert der User die Commercial Terms inkl. DPA — **kein Team-seitiger DPA mit Anthropic nötig**. **Vertragspartner** des Users ist für in der Schweiz ansässige Customers **Anthropic Ireland, Limited** (irisches Recht); die technische Datenverarbeitung erfolgt in den USA durch Anthropic PBC.

**Anthropic DPF-Status:** Anthropic ist **nicht** im Swiss-US Data Privacy Framework zertifiziert (Stand 27.05.2026). Der DPF steht damit als Übermittlungsgrundlage nicht zur Verfügung — die SCCs + Swiss Addendum bleiben die einzige und ausreichende Grundlage.

---

## Entscheidung

Im PoC ruft FitBuddy die Claude API über den eigenen Anthropic-Account des Endusers auf (BYO-Key-Modell). Die Rechtsgrundlage für die Drittlandübermittlung stützt sich auf:
1. Den Anthropic DPA **des Users** (inkl. SCCs Module 2/3 + Swiss Addendum), automatisch gültig mit Erstellung des eigenen Anthropic-Accounts — **nicht** auf einen vom Team abgeschlossenen DPA.
2. Eine explizite, versionierte informierte Einwilligung des Endusers im Onboarding (US-4 AC4/AC5).

**Vor v1.0** migrieren wir verpflichtend auf AWS Bedrock `eu-central-1` (Frankfurt) oder alternativ Google Vertex AI `europe-west6` (Zürich). Diese Migration ist kein optionales Refactor, sondern Voraussetzung für jeden kommerziellen Launch. Der Claude-API-Call wird ab Sprint 3 hinter einer `InferenceService`-Klasse gekapselt.

**Datenschutz-Risikoeinschätzung für den PoC:** Für den geschlossenen PoC (einwilligungsfähige Erwachsene, TestFlight, kein öffentlicher Zugang) reicht eine einseitige, dokumentierte Risikoeinschätzung aus — eine formale DSFA nach Art. 22 revDSG ist v1.0-Material und Pflicht vor einem kommerziellen Launch.

---

## Konsequenzen

### + Positiv

- Drittland-Rechtsgrundlage steht ohne Verhandlungsaufwand: Mit Erstellung des eigenen Anthropic-Accounts akzeptiert der User die Commercial Terms inkl. DPA (SCCs + Swiss Addendum) — kein Team-seitiger DPA-Verhandlungsaufwand nötig.
- PoC bleibt im 3-Monats-Scope umsetzbar — kein AWS/GCP-Setup, kein Proxy, keine Cloud-Signatur-Implementierung am Client.
- `InferenceService`-Abstraktion macht die EU-Hosting-Migration zu einem isolierten Refactor — Prompt-Builder und UI bleiben unverändert.
- Anthropic trainiert nicht auf Commercial-API-Daten — vertraglich zugesichert (Commercial Terms Section B). Safety-Classifier zur Abuse Detection verarbeiten Prompts separat (kein Training, aber eine Form der Verarbeitung — im Consent-Text abzubilden).

### - Negativ

- **Daten verlassen die Schweiz und gehen in die USA.** Der DPA des Users deckt die Übermittlung vertraglich ab; die Informationspflicht gegenüber Endusern (Art. 19 revDSG) bleibt bei FitBuddy. Consent-Text in US-4 AC4 muss korrekt ausweisen: USA als Drittland (keine Angemessenheitsentscheidung der Schweiz); **Anthropic Ireland, Limited** als Vertragspartner des Users (irisches Recht); US-Verarbeitung durch Anthropic PBC; DPA des Users als Rechtsgrundlage.
- **KEIN gemeinsamer Team-Key für externe Tester (Architekturpflicht):** Würde das Team einen eigenen Anthropic-Key für Demos oder externe Tester bereitstellen, wird das Team zum «Customer» — der Team-DPA würde alle Claude-Calls abdecken müssen, das Team wäre Controller für Gesundheitsdaten Dritter. Alle DPA/DSFA/Controller-Pflichten kämen vollständig zurück. Strikt BYO-Key für alle Tester (→ [[ADR-4]]).
- **Safety Classifier verarbeitet Prompt-Inhalte:** Anthropic verwendet automatisierte Klassifizierer zur Abuse Detection, die Prompts (inklusive Trainingsdaten im Context) verarbeiten. Das ist kein Modell-Training, aber eine Form der Verarbeitung, die im Consent-Text oder in der DSFA adressiert werden sollte.
- **Controller-Pflichten liegen vollständig bei FitBuddy:** Verzeichnis der Bearbeitungstätigkeiten (Art. 12 revDSG), DSFA (Art. 22 revDSG), Datenschutzerklärung mit Drittlandhinweis. Diese Pflichten gelten ab der ersten echten Datenverarbeitung — auch im PoC.
- **Controller-Person-Risiko:** Wenn ein Teammitglied seinen Privataccount für den Anthropic Commercial-Account nutzt, trägt diese Person persönlich die Controller-Pflichten für Gesundheitsdaten Dritter. Der Account-Inhaber muss klar definiert sein (BFH, juristische Person des Teams oder Privatperson mit vollem Bewusstsein der Implikationen).
- **EU-Hosting-Migration kostet realistisch 2–3 Sprints:** AWS-Konto, IAM-Rollen, Bedrock-Modell-Quotas beantragen, Region-Latenz testen und Client-Integration neu abnehmen. Google Vertex AI `europe-west6` als Alternative evaluieren — möglicherweise geringerer Overhead für ein Team ohne AWS-Erfahrung. Der Aufwand ist verschoben, nicht eingespart.
- **Preisänderungs- und ToS-Risiko:** Bei Anthropic-Preisänderungen oder ToS-Updates ohne EU-Hosting haben wir keine Ausweichmöglichkeit. Bedrock/Vertex würde zusätzlichen Verhandlungsspielraum geben.

---

## Offene Punkte (priorisiert)

| Frage | Priorität | Fällig |
|---|---|---|
| Risikoeinschätzung für PoC dokumentieren (einseitig; formale Art.-22-DSFA ist v1.0-Pflicht) | Hoch | vor v1.0 |
| **Account-Inhaber eines allfälligen Team-Anthropic-Accounts festlegen** — bei Nutzung eines Team-Keys Controller-Pflichten beachten; im BYO-Key-Modell nicht relevant | Mittel | Sprint 1 |
| ~~AUP-Status dokumentieren~~ — in ADR-4 Kontext dokumentiert; BYO-Ansatz entspricht Anthropics Best Practice. **(geschlossen)** | — | — |
| **Consent-Text US-4 AC4: USA als Drittland, Anthropic Ireland Ltd als Vertragspartner, Safety-Classifier-Verarbeitung explizit nennen** | **Hoch** | **Sprint 3/4** |
| Verzeichnis der Bearbeitungstätigkeiten (Art. 12 revDSG) anlegen | Hoch | Sprint 2 |
| EU-Hosting-Option evaluieren: AWS Bedrock Frankfurt vs. Google Vertex AI Zürich — Aufwand vergleichen | Mittel | vor v1.0 |
| Rechtliche Einordnung «Trainingsdaten als Gesundheitsdaten» durch EDÖB-Leitfaden oder Rechtsgutachten verifizieren | Mittel | vor v1.0 |
| ~~Bestätigen, dass auf Commercial-API-Daten kein Modell-Training stattfindet~~ — vertraglich zugesichert (Commercial Terms Section B). Safety Classifier bleibt als separates Thema im Consent-Text abzubilden. **(geschlossen)** | — | — |

---

*Korrektur 2026-06-03: DPA-Träger von «Team» auf «User» umgestellt (BYO-Key-Modell: User ist Anthropic-Customer); Vertragspartner auf Anthropic Ireland, Limited / Anthropic PBC korrigiert; DSFA für geschlossenen PoC auf einseitige Risikoeinschätzung herabgestuft; Training-opt-out und AUP-Punkt als geschlossen markiert; «Kein Team-Key für externe Tester» als Architekturpflicht ergänzt. Quellen: Anthropic Commercial Terms + DPA, geprüft 2026-06-03.*
