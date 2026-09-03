# ADR-9: CI auf selbst gehostetem macOS-Runner

**Status:** Accepted
**Datum:** 2026-09-02
**Treiber-QA:** Maintainability (QA-3)
**Umgesetzt mit:** #113 (Runner-Setup und `.github/workflows/ci.yml`)

---

## Kontext

Build und Testsuite laufen bisher ausschliesslich lokal über das `build-and-test`-Skill. Das setzt voraus, dass jede Person vor dem Merge daran denkt — ein PR mit roter Suite kann heute nichts daran hindern, nach `develop` zu gehen.

Dazu kommt Toolchain-Drift: Die Arbeitsgeräte im Team sind nicht identisch eingerichtet. Beim Aufsetzen des Runners zeigte sich, dass eine Maschine noch auf macOS 15.2 ohne Xcode stand, während gegen Xcode 26 gebaut wird — «läuft bei mir» ist damit keine belastbare Aussage über den Zustand von `develop`.

Ein iOS-Build braucht macOS und Xcode. GitHub-hosted Runner bieten das, ihre macOS-Minuten sind aber die teuerste Kategorie — genau daran ist die CI-Frage im PoC am 05.08.2026 schon einmal gescheitert. Im Team steht ein Mac mini (Apple Silicon), der die Rolle übernehmen kann.

## Entscheidung

**Wir betreiben CI auf einem selbst gehosteten macOS-Runner (Mac mini, Apple Silicon) im Heimnetz eines Teammitglieds.**

Ein Workflow (`.github/workflows/ci.yml`), der bei `pull_request` gegen `develop` und bei `push` auf `develop` Build und XCTest-Suite gegen den iOS-Simulator fährt und das Ergebnis als Status-Check am PR zurückmeldet.

Bewusst nicht Teil des Umfangs:

- **Keine Secrets.** Durch das BYO-Key-Modell braucht die Testsuite weder Hevy- noch LLM-Keys. Der Runner bekommt keine und soll nie welche sehen.
- **Kein Code-Signing, kein Archive-, kein TestFlight-Job.** Simulator-Builds signieren nicht; der gesamte Zertifikats- und Provisioning-Komplex bleibt draussen. TestFlight-Builds werden weiterhin von Hand erzeugt.

**Der Status-Check läuft vorerst informativ, nicht verbindlich.** Ein erforderlicher Check würde jeden Merge blockieren, sobald der Mac mini schläft, ausgeschaltet ist oder das Heimnetz klemmt — bei einem Rechner, der zugleich Arbeitsgerät ist, ist das ein realistischer Alltag und kein Randfall. Verbindlich (Branch-Protection) wird er, sobald die Verfügbarkeit über einige Wochen Betrieb belegt ist.

Der Runner läuft als LaunchAgent unter einem eigenen Benutzer ohne Admin-Rechte. Build-Output landet unter `$GITHUB_WORKSPACE/.derivedData` statt im geteilten `~/Library/Developer/Xcode/DerivedData` und wird nach jedem Job gelöscht.

## Konsequenzen

### + Positiv

- **Keine laufenden Kosten** — der Einwand, an dem die CI-Frage im PoC zuerst gescheitert ist, entfällt mit eigener Hardware.
- **Die Toolchain steht unter eigener Kontrolle:** Der Runner kann exakt dieselbe Xcode-Version fahren wie die Entwicklungsgeräte, statt einem Image-Update von GitHub ausgeliefert zu sein.
- **Ein roter Test wird sichtbar, bevor gemergt wird** — bei aktivierter Branch-Protection auch verbindlich.
- Die Testergebnisse (`.xcresult`) hängen bei einem Fehlschlag am Workflow-Lauf; man braucht keinen Shell-Zugang zum Runner, um zu sehen, welcher Test gefallen ist.

### - Negativ

- **Die CI-Verfügbarkeit hängt an einem privaten Rechner.** Ist er aus, im Ruhezustand oder das Heimnetz gestört, bleiben Checks «pending». Bei erforderlichem Status-Check blockiert das jeden Merge — die Entscheidung «erforderlich oder informativ» ist deshalb bewusst zu treffen.
- **Ein einzelner Runner arbeitet seriell.** Bei mehreren offenen PRs entsteht eine Warteschlange.
- **Bindung an eine Person:** Hardware, Stromrechnung und Xcode-Updates hängen an dem Teammitglied, bei dem der mini steht.
- **Kein echter Headless-Betrieb.** Simulator-Tests brauchen eine GUI-Session; der Benutzer muss automatisch angemeldet sein und der Ruhezustand deaktiviert.
- **Nur zulässig, solange das Repository privat ist.** Bei einem öffentlichen Repo könnte ein Fork-PR beliebigen Code auf privater Hardware im Heimnetz ausführen. Wird das Repo je öffentlich gemacht, muss der Runner entfernt oder der Workflow auf Approval-Gates umgestellt werden — dieser Punkt ist Teil der Entscheidung, nicht bloss ein Hinweis.
- **Persistenter Runner heisst geteilter Zustand** zwischen Läufen (Caches, Simulator-Zustand). Für ein PoC-Team vertretbar; ein ephemerer Runner wäre sauberer, kostet aber pro Job die Xcode-Aufwärmzeit.

## Offene Punkte

| Frage | Priorität | Fällig |
|---|---|---|
| Status-Check verbindlich schalten (Branch-Protection), sobald die Runner-Verfügbarkeit belegt ist | Mittel | nach ~4 Wochen Betrieb |
| Zweiter Runner, falls die Warteschlange stört | Niedrig | bei Bedarf |
| Ephemere Runner, falls geteilter Zustand zu Fehlschlägen führt | Niedrig | bei Bedarf |
