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

**Anthropic DPA-Recherche (Stand 27.05.2026):** Der Anthropic Data Processing Addendum (DPA, effektiv 24.02.2025) ist via Section C der Anthropic Commercial Terms of Service by reference inkorporiert, sobald das Team einen Paid-API-Account auf `console.anthropic.com` nutzt. Schedule 3 des DPA enthält EU-Standardvertragsklauseln (SCCs Module 2 und 3) sowie ein explizites Swiss Addendum (FADP/revDSG). **Keine separate Verhandlung nötig** — Rechtsgrundlage steht durch Nutzung des Commercial-Tiers.

**Anthropic DPF-Status:** Anthropic ist **nicht** im Swiss-US Data Privacy Framework zertifiziert (Stand 27.05.2026). Der DPF steht damit als Übermittlungsgrundlage nicht zur Verfügung — die SCCs + Swiss Addendum bleiben die einzige und ausreichende Grundlage.

---

## Entscheidung

Im PoC nutzen wir die Claude API direkt aus den USA über Anthropics Commercial Tier (`console.anthropic.com`). Die Rechtsgrundlage stützt sich auf:
1. Den Anthropic DPA inkl. SCCs (Module 2/3) und Swiss Addendum, der via Commercial Terms automatisch inkorporiert ist.
2. Eine explizite, versionierte informierte Einwilligung des Endusers im Onboarding (US-4 AC4/AC5).

**Vor v1.0** migrieren wir verpflichtend auf AWS Bedrock `eu-central-1` (Frankfurt) oder alternativ Google Vertex AI `europe-west6` (Zürich). Diese Migration ist kein optionales Refactor, sondern Voraussetzung für jeden kommerziellen Launch. Der Claude-API-Call wird ab Sprint 3 hinter einer `InferenceService`-Klasse gekapselt.

**Kritische Voraussetzung:** Eine Datenschutz-Folgenabschätzung (DSFA) nach revDSG Art. 22 muss **vor der ersten Verarbeitung echter Nutzerdaten** (spätestens vor Beginn der TestFlight-Betaphase) abgeschlossen sein — nicht erst vor v1.0. Die DSFA ist kein optionales Dokument, sondern eine gesetzliche Pflicht bei systematischer KI-Analyse von Gesundheitsdaten.

---

## Konsequenzen

### + Positiv

- Drittland-Rechtsgrundlage steht ohne Verhandlungsaufwand: Anthropic-DPA inkl. SCCs und Swiss Addendum gilt automatisch ab Account-Erstellung im Commercial-Tier.
- PoC bleibt im 3-Monats-Scope umsetzbar — kein AWS/GCP-Setup, kein Proxy, keine Cloud-Signatur-Implementierung am Client.
- `InferenceService`-Abstraktion macht die EU-Hosting-Migration zu einem isolierten Refactor — Prompt-Builder und UI bleiben unverändert.
- Anthropic trainiert per Default nicht auf Commercial-API-Daten, was zusätzlich zur DPA das Risiko sekundärer Verarbeitung (Modell-Training) reduziert.

### - Negativ

- **Daten verlassen die Schweiz und gehen in die USA.** Der DPA deckt die Übermittlung vertraglich ab; die Informationspflicht gegenüber Endusern (Art. 19 revDSG) bleibt bei FitBuddy — Consent-Text in US-4 AC4 muss die USA als Drittland und Anthropic Inc. als Empfänger ausdrücklich nennen.
- **Safety Classifier verarbeitet Prompt-Inhalte:** Anthropic verwendet automatisierte Klassifizierer zur Abuse Detection, die Prompts (inklusive Trainingsdaten im Context) verarbeiten. Das ist kein Modell-Training, aber eine Form der Verarbeitung, die im Consent-Text oder in der DSFA adressiert werden sollte.
- **Controller-Pflichten liegen vollständig bei FitBuddy:** Verzeichnis der Bearbeitungstätigkeiten (Art. 12 revDSG), DSFA (Art. 22 revDSG), Datenschutzerklärung mit Drittlandhinweis. Diese Pflichten gelten ab der ersten echten Datenverarbeitung — auch im PoC.
- **Controller-Person-Risiko:** Wenn ein Teammitglied seinen Privataccount für den Anthropic Commercial-Account nutzt, trägt diese Person persönlich die Controller-Pflichten für Gesundheitsdaten Dritter. Der Account-Inhaber muss klar definiert sein (BFH, juristische Person des Teams oder Privatperson mit vollem Bewusstsein der Implikationen).
- **EU-Hosting-Migration kostet realistisch 2–3 Sprints:** AWS-Konto, IAM-Rollen, Bedrock-Modell-Quotas beantragen, Region-Latenz testen und Client-Integration neu abnehmen. Google Vertex AI `europe-west6` als Alternative evaluieren — möglicherweise geringerer Overhead für ein Team ohne AWS-Erfahrung. Der Aufwand ist verschoben, nicht eingespart.
- **Preisänderungs- und ToS-Risiko:** Bei Anthropic-Preisänderungen oder ToS-Updates ohne EU-Hosting haben wir keine Ausweichmöglichkeit. Bedrock/Vertex würde zusätzlichen Verhandlungsspielraum geben.

---

## Offene Punkte (priorisiert)

| Frage | Priorität | Fällig |
|---|---|---|
| **DSFA (Datenschutz-Folgenabschätzung) erstellen — Pflicht vor erster Nutzerdaten-Verarbeitung (TestFlight-Beta)** | **Kritisch** | **Sprint 2** |
| **Account-Inhaber des Anthropic Commercial-Accounts festlegen — wirkt sich auf Controller-Status aus** | **Kritisch** | **Sprint 1** |
| **AUP-Status intern dokumentieren: Kein AUP-Verbot für Direct-from-Mobile (BYO-Key). BYO-Ansatz entspricht Anthropics Best Practice (verknüpft mit [[ADR-4]])** | Hoch | Sprint 1 |
| **Consent-Text US-4 AC4: USA als Drittland, Anthropic Inc. als Empfänger, Safety-Classifier-Verarbeitung explizit nennen** | **Hoch** | **Sprint 3/4** |
| Verzeichnis der Bearbeitungstätigkeiten (Art. 12 revDSG) anlegen | Hoch | Sprint 2 |
| EU-Hosting-Option evaluieren: AWS Bedrock Frankfurt vs. Google Vertex AI Zürich — Aufwand vergleichen | Mittel | vor v1.0 |
| Rechtliche Einordnung «Trainingsdaten als Gesundheitsdaten» durch EDÖB-Leitfaden oder Rechtsgutachten verifizieren | Mittel | vor v1.0 |
| Bestätigen, dass auf Commercial-API-Daten kein Modell-Training stattfindet (Safety Classifier von Training trennen) | Mittel | Sprint 3 |
