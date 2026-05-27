# ADR-0006: Claude API (USA) mit AVV/DPA im PoC, Bedrock EU vor v1.0

**Status:** Proposed
**Datum:** 2026-05-27
**Treiber-QA:** Security / Privacy (QA-1), Maintainability (QA-3)

## Kontext

Trainingsdaten gelten nach nDSG Art. 5 lit. c als Gesundheitsdaten und unterliegen damit der höchsten Schutzkategorie. Die Claude API von Anthropic ist in den USA gehostet; die Schweiz hat für die USA keinen Angemessenheitsbeschluss, sodass jede Übermittlung dorthin eine zusätzliche Schutzgrundlage benötigt. AWS Bedrock bietet Claude-Modelle in Region `eu-central-1` (Frankfurt), Azure Switzerland North führt aktuell nur OpenAI-Modelle. Im 3-Monats-PoC ist eine vollständige Bedrock-Integration (AWS-Konto, IAM, Signature V4, Proxy-Architektur) nicht leistbar; gleichzeitig ist ein kommerzieller v1.0-Launch ohne EU-Hosting nDSG-rechtlich nicht tragbar.

## Entscheidung

Im PoC nutzen wir die Claude API direkt aus den USA mit zwei Schutzgrundlagen: (1) ein vom FitBuddy-Team einmalig mit Anthropic abgeschlossener AVV/DPA und (2) eine explizite, versionierte informierte Einwilligung im Onboarding (US-4 AC4/AC5). Vor v1.0 migrieren wir verpflichtend auf AWS Bedrock in Region `eu-central-1` (Frankfurt) — diese Migration ist kein optionales Refactor, sondern Voraussetzung für jeden kommerziellen Launch. Der Claude-API-Call wird ab Sprint 3 hinter einer `InferenceService`-Klasse gekapselt, sodass die Migration eine einzige Klasse berührt.

## Konsequenzen

**Positiv (+)**
- PoC bleibt im 3-Monats-Scope umsetzbar — kein AWS-Setup, kein Proxy, keine Signature-V4-Implementation am Client.
- Rechtsgrundlage für den PoC steht (AVV + Consent + akademischer Kontext) — TestFlight-Distribution an wenige Tester ist tragbar.
- `InferenceService`-Abstraktion macht die Bedrock-Migration zu einem isolierten Refactor — der Prompt-Builder und die UI bleiben unverändert.

**Negativ (−)**
- Daten verlassen die Schweiz und gehen in die USA — Vertrauensaussage in Marketing und App-Description muss diesen Punkt offen benennen, sonst ist der Consent juristisch wertlos.
- Vor jedem Build, der nicht klar als „academic PoC“ markiert ist, muss explizit geprüft werden, dass AVV unterschrieben und Consent-Screen aktiv ist — operatives Risiko, das menschliche Disziplin erfordert.
- Die Bedrock-Migration ist Pflicht, nicht optional, und kostet schätzungsweise 1–2 Sprints (AWS-Konto, IAM-Rollen, Proxy oder Direct-Call entscheiden, Region-Latenz testen) — dieser Aufwand ist verschoben, nicht eingespart.
- Bei Anthropic-Preisänderungen oder ToS-Updates müssen wir reagieren, ohne die Region wechseln zu können — Bedrock würde uns hier mehr Verhandlungsspielraum geben.
