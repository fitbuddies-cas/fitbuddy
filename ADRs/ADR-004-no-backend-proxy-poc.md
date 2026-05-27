# ADR-0002: Kein Backend-Proxy im PoC — Direkter API-Call vom iOS-Client

**Status:** Proposed
**Datum:** 2026-05-27
**Treiber-QA:** Security / Privacy (QA-1), Maintainability (QA-3)

## Kontext

FitBuddy muss sowohl die Hevy REST API (Trainingsdaten) als auch die Claude API (AI-Empfehlung) aufrufen. Ein Backend-Proxy wäre Best Practice, um den Claude-API-Key serverseitig zu halten und Rate-Limits zentral durchzusetzen — kostet aber ein eigenes Deployment-, Auth- und Operations-Sub-System, das wir in 3 Monaten mit 2–3 Personen nicht zusätzlich tragen können. Zielgruppe sind Hevy-Pro-Nutzer (Persona Marcus), die mit API-Keys umgehen können; Persona Jana kann den Claude-Key in US-4 explizit überspringen. Die Distribution erfolgt im PoC ausschliesslich über TestFlight/Sideload — kein öffentlicher App-Store-Release.

## Entscheidung

Wir verzichten im PoC auf einen Backend-Proxy. Sowohl Hevy- als auch Claude-API-Calls laufen direkt vom iOS-Gerät an die jeweiligen Anbieter, mit API-Keys aus dem iOS Keychain. Wir kapseln den Claude-Call in einer eigenen `InferenceService`-Klasse, sodass ein späterer Wechsel auf AWS Bedrock EU (siehe ADR-0006) oder einen Proxy nur diese eine Klasse berührt — der Entscheid ist bewusst reversibel.

## Konsequenzen

**Positiv (+)**
- Spart ein vollständiges Backend (Hosting, Deployment, Auth, Monitoring, Secrets-Rotation) und damit mindestens einen halben Sprint, der für US-3 (Prompt-Engineering) kritisch ist.
- Datenfluss ist transparent: Trainingsdaten gehen nur an Hevy und Anthropic — keine zusätzliche Vertrauensinstanz, die im Consent-Screen (US-4 AC4) erklärt werden müsste.
- Kein Single Point of Failure auf unserer Seite: Wenn unser Proxy down wäre, wäre die App komplett unbenutzbar; ohne Proxy hängt sie nur an den Drittanbieter-SLAs.

**Negativ (−)**
- Claude-API-Key liegt auf dem Endgerät — bei Jailbreak / forensischer Geräteanalyse exponiert; es gibt keinen serverseitigen Kill-Switch (R3-naher Risikotyp).
- Rate-Limiting muss client-seitig durchgesetzt werden (Cooldown 6h via UserDefaults). Ein böswilliger User kann den Cooldown lokal umgehen und Kosten verursachen.
- Vor v1.0 ist die Migration auf einen Proxy oder Bedrock zwingend (ADR-0006) — Aufwand ist verschoben, nicht eingespart.
- Certificate Pinning für Hevy und Claude muss client-seitig implementiert werden, sonst genügt ein MITM im offenen WLAN, um Keys abzugreifen.
