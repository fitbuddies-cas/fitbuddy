# FitBuddy — Projektübersicht

## Idee in einem Satz

> "Ein AI-gestützter Trainingsassistent für Kraft- und Ausdauersportler, der Hevy-Kraftdaten und Strava-Cardio-Daten zusammenführt und daraus personalisierte Übersichten und Progressions-Empfehlungen generiert."

## Kontext

| | |
|---|---|
| Kurs | CAS Application Development with AI (ADAI) 2026 |
| Team | 2–3 Personen |
| Abgabe | Präsentation Modul 3 |

## Problem

Trainingsdaten (Kraft, Ausdauer) sind auf mehrere Apps verteilt (Hevy, Strava, Apple Health). Eine ganzheitliche Sicht fehlt. Fortschritte müssen manuell verfolgt werden. AI-gestützte Progression existiert zwar isoliert (Hevy Coach via CSV-Import), aber ohne Aggregation aus mehreren Quellen und ohne nahtlose Nutzererfahrung.

**Heute löst man das so:** Manuell über mehrere Apps und Blatt Papier.

## Lösung (PoC)

Native iOS-App, die:

1. Hevy-Trainingsdaten via API aggregiert (PoC: Hevy only)
2. Ein Dashboard mit 90-Tage-Übersicht liefert
3. On-demand AI-Progressionsempfehlungen generiert (Claude API)
4. API-Keys lokal im iOS Keychain speichert — keine fremden Server

## Personas

### Marcus Huber — Technikaffiner Power-User
- Nutzt mehrere Fitness-Apps gleichzeitig (Hevy + Strava oder ähnliches)
- Will seine Gesamtbelastung (Kraft + Ausdauer) auf einen Blick beurteilen
- Hat einen Hevy Pro Account mit API-Key
- Frustration heute: Daten liegen in Silos, kein ganzheitliches Bild
- Könnte abgehalten werden durch: Onboarding-Komplexität (API-Keys)

### Jana Vogel — Krafttraining-Einsteigerin
- Trainiert regelmässig, aber ohne tiefes Datenwissen
- Will ohne Selbstinterpretation wissen, ob sie steigern kann
- Kein technischer Hintergrund
- Frustration heute: Weiss nicht, ob sie richtig trainiert oder ob sie mehr leisten könnte
- Könnte abgehalten werden durch: Zu technisches Onboarding (API-Key-Einrichtung)

## Scope

### PoC-Scope (MVP, 3 Monate)

- Plattform: iOS (native)
- Datenquelle: Hevy (via API Key, lokal im Keychain)
- AI: Claude API, on-demand Analyse (kein automatischer Hintergrundlauf)
- Sprache: English-only (alle UI-Strings, Fehlermeldungen, System-Prompt)

### Architektonisch vorbereitet, aber noch nicht implementiert

- Strava als zweite Datenquelle (Connector-Interface wird im PoC verankert)

### Bewusst ausgeschlossen (Won't)

- Push-Notifications mit wöchentlicher Zusammenfassung (US-11)
- Trainingsvorschlag zurück in Hevy schreiben (US-12 — erfordert Hevy PRO, UX-Klärung)
- i18n / Lokalisierungsframework
- App Store Veröffentlichung — Distribution im PoC ausschliesslich via TestFlight / Sideload

### Offen — Entscheid vor Architektur nötig

- Apple Health: passive Gesundheitsdaten (Schlaf, HRV, Ruheherzrate) — IN oder OUT of Scope?
- Fehlerzustand 401: harter Logout (US-1 AC3) oder weicher Banner?

## Risiken

| # | Risiko | Massnahme |
|---|---|---|
| R1 | **Plattform-Abhängigkeit**: Hevy API ohne Garantien ("no guarantees — we might abandon this entirely"). Strava hat 2020 die API bereits massiv eingeschränkt. | Connector-Interface so bauen, dass zweiter Datenlieferant ohne Umbau integrierbar ist. Hevy ToS auf kommerzielle API-Nutzung sofort prüfen. |
| R2 | **Markt-Differenzierung**: Hevy könnte eine native Strava-Integration ankündigen → Kern-Value für Hevy-only-Nutzer obsolet. | Echter Moat ist die AI-Qualität der Empfehlungen, nicht die Datenaggregation alleine. |
| R3 | **Write-back-Risiko**: AI-generierte Pläne direkt in Hevy schreiben → falsche Progression, überschriebener Plan. | Im PoC bewusst als Won't priorisiert (US-12). |
| R4 | **Onboarding-Hürde**: Zwei API-Keys (Hevy + Claude) sind für Nicht-Techniker (Persona Jana) echtes Produktrisiko. | US-4 als Must-have priorisiert: Onboarding in max. 3 verständlichen Schritten. |

## Zeitplan

| Woche | Sprint-Fokus | User Story |
|---|---|---|
| 1 | iOS Keychain-Integration + Hevy API-Verbindungstest (401, Timeout, Rate Limit) | US-1 |
| 2 | Dashboard mit 90-Tage-Aggregation, Empty States, Partial-Data-Fälle | US-2 |
| 3 | AI-Analyse-Button, Prompt-Entwicklung mit echten Testdaten, Disclaimer | US-3 |
| 4 | End-to-End-Test, Onboarding polieren, Präsentation vorbereiten | US-1–4 |

