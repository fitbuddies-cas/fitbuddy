# FitBuddy

> "Ein AI-gestützter Trainingsassistent für Kraft- und Ausdauersportler, der Hevy-Kraftdaten und Strava-Cardio-Daten zusammenführt und daraus personalisierte Übersichten und Progressions-Empfehlungen generiert."

FitBuddy ist eine native iOS-App, die Trainingsdaten aus mehreren Fitness-Apps in einem einzigen Dashboard aggregiert und auf Knopfdruck AI-gestützte Progressions-Empfehlungen liefert.

---

## Problem

Trainingsdaten (Kraft, Ausdauer) sind auf mehrere Apps verteilt (Hevy, Strava, Apple Health). Eine ganzheitliche Sicht fehlt, Fortschritte müssen manuell verfolgt werden. AI-gestützte Progression existiert isoliert (Hevy Coach via CSV-Import), aber ohne Aggregation aus mehreren Quellen und ohne nahtlose Nutzererfahrung.

**Heute löst man das so:** Manuell über mehrere Apps und Blatt Papier.

## Lösung (PoC)

Native iOS-App (SwiftUI), die:

1. **Hevy-Trainingsdaten via API aggregiert** (PoC: Hevy only)
2. **Ein Dashboard liefert** — Sessions, Gesamtvolumen, Muskelbelastungsverteilung
3. **On-demand AI-Progressionsempfehlungen generiert** — ein Tap für eine konkrete, verständliche Empfehlung via Claude API
4. **API-Keys lokal im iOS Keychain speichert** — keine fremden Server
5. **Onboarding in 3 Schritten** bietet — für nicht-technische Nutzer, ohne Dokumentation bedienbar

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

## Datenquellen

| Quelle | Status |
|---|---|
| Hevy (Kraft) | PoC |
| Strava (Cardio) | Geplant v1 |
| Apple Health | In Abklärung |

## Anforderungen

Der PoC umfasst vier **Must-Have**-User-Stories: API-Key sicher speichern (US-1), Trainingsdaten im Dashboard (US-2), AI-Analyse auf Knopfdruck (US-3) und Onboarding in 3 Schritten (US-4).

Alle 12 User Stories mit Akzeptanzkriterien, MoSCoW-Priorisierung und Out of Scope: siehe [REQUIREMENTS.md](docs/REQUIREMENTS.md).

## Architektur

Native iOS (SwiftUI), kein Backend: Alle API-Keys verbleiben auf dem Gerät im iOS Keychain, die Aufrufe an Hevy- und Claude-API laufen direkt vom Gerät. Ein `FitnessConnector`-Interface kapselt die Datenquellen, damit Strava (v1) ohne Umbau ergänzt werden kann.

Systemdesign, Tech-Stack, Datenmodell, ADRs und offene Architektur-Fragen: siehe [ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Risiken

| # | Risiko | Massnahme |
|---|---|---|
| R1 | **Plattform-Abhängigkeit**: Hevy API ohne Garantien ("no guarantees — we might abandon this entirely"). Strava hat 2020 die API bereits massiv eingeschränkt. | Connector-Interface so bauen, dass ein zweiter Datenlieferant ohne Umbau integrierbar ist. Hevy ToS auf kommerzielle API-Nutzung prüfen. |
| R2 | **Markt-Differenzierung**: Hevy könnte eine native Strava-Integration ankündigen → Kern-Value für Hevy-only-Nutzer obsolet. | Echter Moat ist die AI-Qualität der Empfehlungen, nicht die Datenaggregation allein. |
| R3 | **Write-back-Risiko**: AI-generierte Pläne direkt in Hevy schreiben → falsche Progression, überschriebener Plan. | Im PoC bewusst als Won't priorisiert (US-12). |
| R4 | **Onboarding-Hürde**: Zwei API-Keys (Hevy + Claude) sind für Nicht-Techniker (Persona Jana) echtes Produktrisiko. | US-4 als Must-have: Onboarding in max. 3 verständlichen Schritten. |
