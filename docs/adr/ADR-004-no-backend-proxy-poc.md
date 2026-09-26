# ADR-004: Kein Backend-Proxy im PoC — Direkter API-Call vom iOS-Client

**Status:** Accepted
**Datum:** 2026-06-03
**Treiber-QA:** Security / Privacy (QA-1), Maintainability (QA-3)

## Kontext

FitBuddy muss sowohl die Hevy REST API (Trainingsdaten) als auch die Claude API (AI-Empfehlung) aufrufen. Ein Backend-Proxy wäre Best Practice, um den Claude-API-Key serverseitig zu halten und Rate-Limits zentral durchzusetzen — kostet aber ein eigenes Deployment-, Auth- und Operations-Sub-System, das wir in 3 Monaten mit 2–3 Personen nicht zusätzlich tragen können. Zielgruppe sind Hevy-Pro-Nutzer (Persona Marcus), die mit API-Keys umgehen können; Persona Jana kann den Claude-Key in US-4 explizit überspringen. Die Distribution erfolgt im PoC ausschliesslich über TestFlight/Sideload — kein öffentlicher App-Store-Release.

**AUP-Status (intern geprüft und dokumentiert):** Die Anthropic Usage Policy regelt Nutzungszwecke (Inhalte) — nicht die technische Key-Architektur. Die Empfehlung «keine API-Keys im Client» ist eine Security-Best-Practice, die gegen das *Einbetten des eigenen Entwickler-Keys* in ausgelieferten Code gerichtet ist. Im BYO-Key-Ansatz (User gibt *eigenen* Key ein, dieser wird lokal im iOS Keychain gespeichert, Calls laufen auf eigene Rechnung) greift diese Empfehlung nicht. Anthropics eigene Best Practice «jeder User beschafft seinen eigenen Key» ist durch diesen Ansatz sogar erfüllt. Eine schriftliche Bestätigung durch Anthropic-Support ist weder realistisch noch erforderlich.

---

## Geprüfte Alternativen

| Option | Aufwand | Einschätzung |
|---|---|---|
| **Kein Proxy (gewählt)** | 0 | Kein serverseitiger Kill-Switch bei Key-Kompromittierung. |
| **Cloudflare AI Gateway** | ~0.5 Tage | Zero-Setup-Proxy für AI-APIs: Rate Limiting, Request Logging, Caching im Free Tier. API-Key bleibt serverseitig. Plan B falls zentrale Logging- oder Rate-Limit-Anforderungen in v1.0 einen Proxy erfordern. |
| **AWS Lambda + API Gateway** | ~1–2 Tage | Einzelner Lambda-Endpoint für Claude-Calls. Weniger Aufwand als ein „vollständiges Backend". Signature V4 am iOS-Client entfällt (Cognito-Credentials). |
| **BFH-Infrastruktur (Hochschul-Server)** | Unklar | Nicht geprüft. Als CAS-Projekt möglicherweise verfügbar — evaluieren, falls v1.0-Proxy-Anforderungen (nDSG/Bedrock) entstehen. |
| **Vollständiges Backend (Node/Python + Auth)** | 2–3 Sprints | Zu aufwendig im PoC-Scope. Für v1.0 nach Bedrock-Migration relevant. |

---

## Entscheidung

Wir verzichten im PoC auf einen Backend-Proxy. Sowohl Hevy- als auch Claude-API-Calls laufen direkt vom iOS-Gerät an die jeweiligen Anbieter, mit API-Keys aus dem iOS Keychain. Wir kapseln den Claude-Call in einer eigenen `InferenceService`-Klasse, sodass ein späterer Wechsel auf AWS Bedrock EU oder Cloudflare AI Gateway nur diese eine Klasse berührt — der Entscheid ist bewusst reversibel.

---

## Konsequenzen

### + Positiv

- Spart ein vollständiges Backend (Hosting, Deployment, Auth, Monitoring, Secrets-Rotation) und damit mindestens einen halben Sprint, der für US-3 (Prompt-Engineering) kritisch ist.
- Datenfluss ist transparent: Trainingsdaten gehen nur an Hevy und Anthropic — keine zusätzliche Vertrauensinstanz, die im Consent-Screen (US-4 AC4) erklärt werden müsste.
- Kein Single Point of Failure auf unserer Seite (in Bezug auf Deployment-Abhängigkeiten): Wenn unser Proxy down wäre, wäre die App komplett unbenutzbar. **Kehrseite:** Ohne Proxy gibt es auch keine Logs, keine Fehlerrate-Übersicht und keine Latenz-Metriken — wir fliegen blind. Bei Problemen am Demo-Tag ist die Fehlerdiagnose schwieriger.

### - Negativ

- **Claude-API-Key liegt auf dem Endgerät:** Bei Jailbreak / forensischer Geräteanalyse exponiert; es gibt keinen serverseitigen Kill-Switch ([ADR-003](ADR-003-keychain-this-device-only.md)-Konsequenz). Realistische Bedrohung im TestFlight-Demo-Kontext gering, aber in v1.0 nicht tolerierbar.
- **Kosten-Exposure ohne Spending-Limit:** Eine client-seitige Sperre ist grundsätzlich bypassbar via Jailbreak oder Proxy und taugt deshalb nicht als Kostenlimit. Der ursprünglich vorgesehene 6h-Cooldown ist mit #117 durch eine 60-s-Doppeltipp-Sperre ersetzt: Sie verhindert versehentliche Mehrfach-Calls, mehr soll sie nicht. **Pflicht-Massnahme (unverändert):** Anthropic Spending Limit im Console-Account konfigurieren, bevor die ersten TestFlight-Tester Zugang erhalten. Ohne Spending Limit kann ein einzelner missbrauchter Key unkontrollierte Kosten auslösen — im BYO-Key-Modell auf Rechnung des Users, der ihn beschafft hat.
- **Rate-Limit-Sharing bei Multi-User-TestFlight:** Wenn mehrere Tester denselben Demo-Anthropic-Account nutzen (z. B. für CAS-Präsentation), teilen sich alle Tester das Account-Level-Rate-Limit. Ein Tester, der 5 Calls in Folge macht, blockiert alle anderen bis zum Ablauf des Account-Rate-Limits. **Mitigation:** Für Demo-Phase jeden Tester mit eigenem Anthropic-Key ausstatten oder Cloudflare AI Gateway mit per-User-Rate-Limiting.
- **Certificate Pinning nicht optional:** Ohne Certificate Pinning genügt ein MITM-Proxy (Charles, mitmproxy) im CAS-Kursraum-WLAN, um API-Keys im Klartext abzugreifen. **Umgesetzt mit #153:** deklarativ über `NSPinnedDomains` in der `Info.plist` (nicht per `URLAuthenticationChallenge` — das System prüft vor jedem Handshake, kein Code-Pfad kann es vergessen) für alle sieben Hosts, an die ein Nutzer-Geheimnis geht: `api.hevyapp.com`, `api.anthropic.com`, `generativelanguage.googleapis.com`, `api.mistral.ai`, `www.strava.com`, `www.polaraccesslink.com`, `polarremote.com`. Gepinnt sind die **Root-CAs** (SPKI-SHA256) mit allen Backup-Roots des Anbieters — nicht Leaf oder Intermediate, weil Let's Encrypt und Google Trust Services ihre Intermediates pro Ausstellung rotieren. Ein Pin-Fehler ist fail closed und erscheint dem Nutzer als «connection not trusted». Herleitung, Prüfung, manueller mitmproxy-Test und Rotationsablauf: [`docs/CERTIFICATE-PINNING.md`](../CERTIFICATE-PINNING.md).
- **Keine Betriebsübersicht:** Ohne Proxy gibt es keine zentrale Log-Übersicht. Fehler (API-Down, Rate-Limit, 401) sind nur im Xcode-Debugger oder via On-Device-Logging sichtbar.
- **Vor v1.0 ist die Migration auf Bedrock oder einen Proxy zwingend** — Aufwand ist verschoben, nicht eingespart. Die Bedrock-Migration (AWS Bedrock `eu-central-1`) ist in [ADR-005](ADR-005-claude-api-usa-with-dpa.md) spezifiziert und kostet realistisch 2–3 Sprints.
- **KEIN gemeinsamer Team-Key für externe Tester (Architekturpflicht):** Stellt das Team einen eigenen Anthropic-Key für Demos oder externe CAS-Tester bereit, wird das Team zum Anthropic-«Customer» — es trägt die Kosten und muss die Gesundheitsdaten Dritter vertraglich absichern (DPA, DSFA, Controller-Pflichten kommen vollständig zurück). Diese Pflichten sind für einen 3-Monats-PoC nicht tragbar und werden durch das BYO-Key-Modell bewusst vermieden. **Regel:** Jeder Tester beschafft und finanziert seinen eigenen Anthropic-Account.

---

## Offene Punkte

| Frage | Priorität | Fällig |
|---|---|---|
| ~~AUP-Status dokumentieren~~ — in Kontext dieses ADR dokumentiert; kein Support-Gate erforderlich. **(geschlossen)** | — | — |
| **Anthropic Spending Limit im Console-Account setzen (vor erstem TestFlight-Build mit echten Usern)** | **Kritisch** | **Sprint 1** |
| ~~Certificate Pinning für `api.anthropic.com` + `api.hevyapp.com` implementieren~~ — mit #153 für alle sieben Hosts über `NSPinnedDomains` umgesetzt, siehe `docs/CERTIFICATE-PINNING.md`. **(geschlossen)** | — | — |
| **Cloudflare AI Gateway als Plan-B vorbereiten (Konfiguration dokumentieren, nicht aktivieren)** | Hoch | Sprint 1 |
| Account-Inhaber des Anthropic Commercial-Accounts festlegen (BFH, Privatperson, Team-Mitglied) — wirkt sich auf Controller-Status aus ([ADR-005](ADR-005-claude-api-usa-with-dpa.md)) | Hoch | Sprint 1 |
| Demo-Strategie für Rate-Limits klären: eigene Keys pro Tester oder Cloudflare Gateway mit User-Isolation | Mittel | Sprint 3 |

---

*Korrektur 2026-06-03: AUP-Offener-Punkt als geschlossen markiert (im Kontext dokumentiert); «Kein Team-Key für externe Tester» als Architekturpflicht ergänzt (BYO-Key-Konsistenz mit ADR-005).*

---

## Nachtrag 2026-09: 60-s-Sperre entfernt

**Kontext:** Die mit #117 eingeführte 60-s-Doppeltipp-Sperre (siehe Konsequenzen oben) liess den User nach jeder Analyse warten, auch wenn er bewusst sofort eine neue starten wollte. Als Kostenlimit taugte sie nie: Sie ist client-seitig und damit bypassbar.

**Entscheidung:** Mit #178 ist die Sperre entfernt. Es gibt keinen Cooldown mehr; doppelte Calls verhindert allein der Button, der gesperrt ist, solange ein Call läuft. «Alle Daten löschen» entfernt den alten Sperr-Zeitstempel weiterhin von Geräten, auf denen ein Build mit Sperre lief.

**Konsequenzen:** Ein neuer Durchlauf ist direkt nach dem vorherigen möglich, und jeder Durchlauf verursacht Kosten auf dem Account des Users. Die Kostenkontrolle liegt damit vollständig beim Spending Limit: **Das Anthropic Spending Limit im Console-Account bleibt Pflicht-Massnahme**, bevor TestFlight-Tester Zugang erhalten (Offene Punkte oben).
