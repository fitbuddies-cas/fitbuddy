# ADR-0003: `FitnessConnector`-Protocol als Abstraktion ab Sprint 1

**Status:** Proposed
**Datum:** 2026-05-27
**Treiber-QA:** Maintainability (QA-3)

## Kontext

Risiko R1 dokumentiert, dass die Hevy API keine Stabilitätsgarantie liefert; Strava hat 2020 die eigene API massiv eingeschränkt. Eine zweite Datenquelle (Strava in v1.1) ist daher nicht optional, sondern strategische Absicherung — sie steht in MoSCoW als Should (US-5) und ist in PROJECT.md als R1-Mitigation verankert. Wenn HevyConnector-Code direkt in Dashboard-Views und den Claude-Prompt-Builder verwächst, wird jeder neue Connector zum Refactor statt zum Feature. Das Team hat 3 Monate für den PoC — die Abstraktion muss in Sprint 1 stehen, bevor Hevy-spezifische Felder in Schichten eindringen, die quellen-agnostisch bleiben müssen.

## Entscheidung

Wir definieren das `FitnessConnector`-Protocol in Sprint 1 **vor** der ersten `HevyConnector`-Implementierung und committen gleichzeitig einen `StravaConnector`-Stub, der kompiliert und `NotImplemented` wirft. Alle nachgelagerten Schichten (Dashboard, AI Analysis Engine, Cache) lesen ausschliesslich aus dem normalisierten `Activity`-Modell, niemals direkt aus Connector-spezifischen Typen. Der Vertrag besteht aus `connect`, `validate`, `fetchActivities(since:)` und `disconnect`.

## Konsequenzen

**Positiv (+)**
- Strava-Integration in v1.1 ist eine neue Connector-Klasse plus OAuth-Flow — keine Änderung an Dashboard oder AI-Prompt-Builder nötig.
- Der Stub-Connector erzwingt Protocol-Stabilität: Tests laufen gegen den Stub, was Protocol-Drift zwischen Sprint 1 und v1.1 unmöglich macht.
- Unit-Tests können einen `MockConnector` einsetzen, ohne gegen die echte Hevy API zu testen — beschleunigt CI und entkoppelt von Rate-Limits.

**Negativ (−)**
- Initialer Overhead in Sprint 1: Protocol-Design plus Stub kostet ca. einen Personentag, der sonst in US-1 fliessen würde.
- Das normalisierte `Activity`-Modell muss von Anfang an reichhaltig genug sein, um Strava-Daten (Distanz, Pace) abzubilden — Risiko, dass wir Felder vorab modellieren, die im PoC tot bleiben.
- Hevy-spezifische Features (z. B. Routinen-Metadaten), die nicht ins Protocol passen, brauchen einen expliziten Ausweg — entweder Hevy-only-Sub-Interface oder bewusster Verzicht.
