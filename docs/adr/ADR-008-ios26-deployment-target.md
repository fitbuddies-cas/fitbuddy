# ADR-8: Mindest-Deployment-Target iOS 26

**Status:** Accepted
**Datum:** 2026-09-02
**Treiber-QA:** Maintainability (QA-3)
**Umgesetzt mit:** #108 (Anhebung des Deployment-Targets), Erstnutzung in #107 (Bottom-Navigation)

## Kontext

[[ADR-1]] hat mit der Wahl von SwiftData iOS 17 als Untergrenze gesetzt, und [[ADR-2]] hat diese Untergrenze für die Plattformentscheidung übernommen. Seither ist der Stand ein anderer: Gebaut und getestet wird längst mit Xcode 26 gegen das iOS-26-SDK (`/build-and-test` läuft auf dem iPhone-17-Simulator), während `IPHONEOS_DEPLOYMENT_TARGET` als Relikt aus dem Projektstart auf 17.0 stehen blieb.

Das kostet ab #107 konkret Substanz: Die Bottom-Navigation will die wertbasierte `Tab`-API (iOS 18+), und die Liquid-Glass-Tab-Bar samt `.tabBarMinimizeBehavior` existiert erst ab iOS 26. Mit einer Untergrenze von iOS 17 wäre jede dieser APIs nur hinter `if #available` nutzbar — also zwei parallel gepflegte UI-Varianten pro Screen, für ein 2–3-köpfiges Team im 3-Monats-PoC der teuerste denkbare Weg. Weitere Screens werden dieselben APIs wollen.

Die Gegenseite der Rechnung ist die Reichweite: iOS 26 verlangt A13 oder neuer, also iPhone 11 / SE (2. Gen.) aufwärts. Die Distribution läuft ausschliesslich über TestFlight an das Team und einige CAS-Teilnehmende ([[ADR-2]]) — es gibt keine öffentliche Installationsbasis, die verloren gehen könnte, sondern eine überschaubare, abgleichbare Liste realer Testgeräte.

## Entscheidung

**Wir setzen `IPHONEOS_DEPLOYMENT_TARGET = 26.0` in allen Build-Configs und geben damit iOS 26 als Mindestversion für v0 vor.**

Die Anhebung ist eine reine Untergrenzen-Änderung: Es wird in #108 kein Code auf neue APIs umgestellt und kein `if #available` entfernt (es existierte keines). Die Umstellung passiert in den Feature-Tasks, die sie brauchen — zuerst #107.

Die Entscheidungen aus [[ADR-1]] (SwiftData) und [[ADR-2]] (Native iOS / SwiftUI) bleiben unverändert gültig; überholt ist ausschliesslich die dort abgeleitete Untergrenze iOS 17. Beide ADRs tragen dazu einen Nachtrag, der hierher verweist, und werden nicht umgeschrieben.

## Konsequenzen

### + Positiv

- **(QA-3) Keine Verfügbarkeits-Zweige:** iOS-18- und iOS-26-APIs sind direkt nutzbar. #107 baut die Tab-Bar einmal statt zweimal; jeder Folge-Screen profitiert gleichermassen.
- **Liquid Glass ohne Sonderweg:** Die iOS-26-Tab-Bar ist ausdrücklich gewollt (#107) und nicht nur geduldet — sie setzt das Deployment-Target zwingend voraus.
- **Ehrlicher Projektstand:** Build-Toolchain (Xcode 26 / iOS-26-SDK) und deklariertes Minimum stimmen wieder überein.
- **Verifiziert kostenneutral:** Build und Testsuite laufen nach dem Sprung unverändert grün (538 Tests, 0 Failures); die drei bzw. vier bestehenden Warnungen sind vorbestehend und deployment-target-unabhängig.

### - Negativ

- **Gerätebasis schrumpft auf A13+:** Nicht mehr nur das iPhone 8 fällt weg (so die alte Konsequenz in [[ADR-1]]/[[ADR-2]]), sondern alles unterhalb iPhone 11 / SE (2. Gen.) — **iPhone X, XS, XS Max und XR eingeschlossen**. TestFlight liefert an solche Geräte schlicht nicht aus. Mitigation: vor dem Merge gegen die realen Testgeräte im Team und bei den externen CAS-Testern abgleichen.
- **Xcode 26 wird Team-Minimum:** Das iOS-26-SDK verlangt Xcode 26 und damit eine hinreichend aktuelle macOS-Version — eine harte Anforderung an jede Person im Team, nicht nur an CI. Ergänzt die Hardware-Konsequenz in [[ADR-2]].
- **Für ein Produkt ausserhalb des PoC zu aggressiv:** Ein Minimum auf der jeweils aktuellsten iOS-Major-Version ist nur tragfähig, weil v0 eine geschlossene TestFlight-Verteilung ist. Vor einem v1-Launch ist die Untergrenze neu zu bewerten (typisch: aktuelle Version minus 1–2).
- **Kein Rückweg ohne Kosten:** Sobald #107 und Folge-Screens iOS-26-APIs nutzen, wäre ein Zurück auf iOS 17 nicht mehr eine Zeile im pbxproj, sondern ein UI-Refactor.

## Offene Punkte

| Frage | Priorität | Fällig |
|---|---|---|
| Gerätebasis mit Team und externen CAS-Testern abgleichen — sperrt A13+ jemanden aus? | Hoch | vor dem Merge von #108 |
| Ein TestFlight-Build mit dem neuen Minimum einmal durchlaufen lassen | Hoch | vor dem Merge von #108 |
| Xcode-26-Verfügbarkeit auf allen Dev-Maschinen bestätigen | Hoch | vor dem Merge von #108 |
| `@Attribute(.unique)` auf `Workout.id` neu bewerten — die SwiftData-Bugs aus iOS 17.x sind als Begründung entfallen (das tragende Argument «Fenster wird ersetzt statt gemerged» bleibt davon unberührt) | Niedrig | Folge-Issue |
| Untergrenze vor v1-Launch neu festlegen | Mittel | vor v1.0 |
