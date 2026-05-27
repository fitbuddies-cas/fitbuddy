# ADR-5: Claude API (USA) via Anthropic Commercial Terms im PoC, Bedrock EU vor v1.0

**Status:** Proposed
**Datum:** 2026-05-27
**Treiber-QA:** Security / Privacy (QA-1), Maintainability (QA-3)

## Kontext

Trainingsdaten gelten nach revDSG Art. 5 lit. c als Gesundheitsdaten und unterliegen damit der höchsten Schutzkategorie. Die Claude API von Anthropic ist in den USA gehostet; die Schweiz hat für die USA keinen allgemeinen Angemessenheitsbeschluss, sodass jede Übermittlung dorthin eine zusätzliche Schutzgrundlage benötigt. AWS Bedrock bietet Claude-Modelle in Region `eu-central-1` (Frankfurt); Azure Switzerland North führt aktuell nur OpenAI-Modelle. Im 3-Monats-PoC ist eine vollständige Bedrock-Integration (AWS-Konto, IAM, Signature V4) nicht leistbar; gleichzeitig ist ein kommerzieller v1.0-Launch ohne EU-Hosting nDSG-rechtlich nicht tragbar.

Recherche zur Anthropic-Rechtslage (Stand 27.05.2026): Der Anthropic Data Processing Addendum (DPA, effektiv 24.02.2025) ist via Section C der Anthropic Commercial Terms of Service **by reference** in den Vertrag inkorporiert, sobald das Team einen Paid-API-Account auf `console.anthropic.com` nutzt. Schedule 3 des DPA enthält die EU-Standardvertragsklauseln (SCCs Module 2 und 3) sowie ein explizites Swiss Addendum, das FADP/revDSG-Datensubjekte abdeckt. Es ist **keine separate Verhandlung oder Unterschrift** mit Anthropic nötig — die Rechtsgrundlage steht durch die blosse Nutzung des kostenpflichtigen Commercial-Tiers (nicht Claude.ai, das Consumer Terms hat).

## Entscheidung

Im PoC nutzen wir die Claude API direkt aus den USA über Anthropics Commercial Tier (`console.anthropic.com`). Die Rechtsgrundlage für die Drittlandübermittlung stützt sich auf (1) den Anthropic DPA inkl. SCCs (Module 2/3) und Swiss Addendum, der via Commercial Terms automatisch inkorporiert ist, und (2) eine explizite, versionierte informierte Einwilligung des Endusers im Onboarding (US-4 AC4/AC5). Vor v1.0 migrieren wir verpflichtend auf AWS Bedrock in Region `eu-central-1` (Frankfurt) — diese Migration ist kein optionales Refactor, sondern Voraussetzung für jeden kommerziellen Launch. Der Claude-API-Call wird ab Sprint 3 hinter einer `InferenceService`-Klasse gekapselt, sodass die Migration eine einzige Klasse berührt.

## Konsequenzen

**Positiv (+)**
- Drittland-Rechtsgrundlage steht ohne Verhandlungsaufwand: Anthropic-DPA inkl. SCCs und Swiss Addendum gilt automatisch ab Account-Erstellung im Commercial-Tier — kein 4–6-Wochen-Legal-Roundtrip, der Sprint 3 blockieren könnte.
- PoC bleibt im 3-Monats-Scope umsetzbar — kein AWS-Setup, kein Proxy, keine Signature-V4-Implementierung am Client.
- `InferenceService`-Abstraktion (vgl. [[ADR-4]]) macht die Bedrock-Migration zu einem isolierten Refactor — Prompt-Builder und UI bleiben unverändert.
- Anthropic trainiert per Default nicht auf Commercial-API-Daten, was zusätzlich zur DPA das Risiko sekundärer Verarbeitung reduziert.

**Negativ (−)**
- Daten verlassen die Schweiz und gehen in die USA. Der DPA deckt die *Übermittlung* vertraglich ab; die *Informationspflicht* gegenüber den Endusern (Art. 19 revDSG) bleibt aber bei FitBuddy als Controller — Consent-Text in US-4 AC4 muss USA als Drittland und Anthropic als Empfänger ausdrücklich nennen.
- **Anthropic Acceptable Use Policy (AUP)-Risiko:** Anthropic empfiehlt explizit gegen das Einbetten von API-Keys in Mobile/Web-Clients (siehe [[ADR-4]]). Verstoß führt zu Account-Sperrung — **unabhängig vom DPA**. Bleibt das größte ungelöste Risiko dieses ADRs.
- Controller-Pflichten unter revDSG bleiben bei FitBuddy: Verzeichnis der Bearbeitungstätigkeiten, Datenschutzerklärung mit Drittlandhinweis, ggf. DSFA (Datenschutz-Folgenabschätzung) für Gesundheitsdaten. Im PoC dokumentieren, vor v1.0 produktiv aufsetzen.
- Bedrock-Migration ist Pflicht, nicht optional, und kostet realistisch 1–2 Sprints (AWS-Konto, IAM-Rollen, Quotas neu beantragen, Region-Latenz testen) — der Aufwand ist verschoben, nicht eingespart.
- Bei Anthropic-Preisänderungen oder ToS-Updates können wir nicht in eine andere Region ausweichen — Bedrock würde uns hier zusätzlichen Verhandlungsspielraum geben.

**Offene Punkte (vor Sprint 3 zu klären)**
- AUP-Klärung: Direct-from-Mobile-Client mit Anthropic-Support bestätigen oder minimalen Proxy einplanen.
- Account-Inhaber des Anthropic Commercial-Accounts festlegen (BFH, Privatperson, Team-Mitglied) — wirkt sich auf Controller-Status aus.
- Swiss-US Data Privacy Framework: Anthropic-Zertifizierungsstatus prüfen (nicht load-bearing, aber zusätzliche Stütze).
- Bestätigen, dass auf Commercial-API-Daten kein Training stattfindet (per Default ja, vertraglich verifizieren).
