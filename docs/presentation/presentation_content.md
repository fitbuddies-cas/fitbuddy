# Präsentation 

## Ablauf

### Einleitung

**Ausgangslage**
* CAS-Rahmen: Projekt im Modulverbund ADAI 2026 (BFH Biel) umsetzen
* Team-Mix ohne Swift-Erfahrung: Android-Dev, DevOps, Business Analyst — bewusst gewähltes Risiko, weil der Kurs zeigt, dass AI genau diese Lücke überbrücken kann (Modul 5A: "AI ist Ausführender, DU gibst die Richtung")
* Internes PostFinance-Projekt verworfen: Datensicherheit, Entwicklungsumgebung, Token-Budget zu heikel für ein PoC-Setting
* Wahl: FitBuddy — eigenständiges, risikoarmes Projekt mit klar abgrenzbarem Scope

**Ziel**
* PoC: "Ein AI-gestützter Trainingsassistent für Kraft- und Ausdauersportler, der Hevy-Kraftdaten und Strava/Polar-Cardio-Daten zusammenführt und daraus personalisierte Übersichten und Progressions-Empfehlungen generiert" (README-Pitch)
* Native iOS-App (SwiftUI), Dashboard mit Sessions, Gesamtvolumen, Muskelbelastungsverteilung + On-demand AI-Progressionsempfehlung per Tap
* Zwei Personas als Leitplanke: **Marcus Huber** (technikaffiner Power-User, mehrere Fitness-Apps, will Gesamtbelastung auf einen Blick) und **Jana Vogel** (Krafttraining-Einsteigerin, kein technischer Hintergrund, will ohne Selbstinterpretation wissen ob sie steigern kann)
* Bewusst kein Backend, kein produktionsreifes Setup — Scope-Grenzen explizit in `docs/REQUIREMENTS.md` Kapitel 4 (Out of Scope) dokumentiert

**Vorgehen**
* Kursstruktur 1:1 als Projekt-Vorgehen übernommen: Requirements (M2) → Architektur (M3) → Planung (M4) → Coding (M5) → Tests (M6) → Doku/CI (M7) → Security (M8)
* Der Kurs nennt das selbst den roten Faden: *"Spec (M2) → Code (5A) → Agenten (5B) → Tests (M6) → Doku/CI (M7) → Sicherheit (M8). Alles Verifikation."*
* Claude als durchgängiger Partner — nicht nur Coding, sondern in jeder Phase (Requirements-Interview, ADR-Review, Task-Breakdown, Testgenerierung, Doku, Security-Review)

---

### Hauptteil

#### 1. Anforderungen (Modul 2)

* **Methode:** AI als Interview-Partner statt wochenlanger Stakeholder-Interviews — Claude stellt die kritischen Fragen, die man selbst nicht gestellt hätte
* **14 User Stories** im Format "Als [Persona] möchte ich [Aktion] damit [Nutzen]" + Given/When/Then Acceptance Criteria — `docs/REQUIREMENTS.md`, gespiegelt in GitHub Issues
* **Must-Have (4):** API-Key sicher im Keychain speichern, 90 Tage Trainingsdaten im Dashboard, AI-Analyse auf Knopfdruck (das eigentliche Produkt-Herzstück, als Epic geführt), Onboarding in max. 3 Schritten
* **Should-Have:** u.a. zweite Datenquelle verbinden (Strava/Polar), Analyse-Kontext transparent machen (welche Daten flossen in die Empfehlung ein), Trainingsprofil (Ziel + Erfahrung) für gezieltere Empfehlungen, AI-Empfehlung als strukturierte Karten statt Fliesstext
* **Could/Won't:** Progressionskurven pro Übung und manuelles Neuladen (Pull-to-Refresh) als Could; Wochenübersicht als Push-Notification und Trainingsvorschlag zurück nach Hevy schreiben explizit als Won't (Risiko: eine falsch übernommene Empfehlung schreibt einen echten Trainingsplan)
* **AI als Advocatus Diaboli:** gezielt Lücken, Widersprüche und "was haben wir unterschätzt" abgefragt, bevor codiert wurde
* **Kritischer Punkt aus dem Kurs, den wir beachtet haben:** AI schlägt vor, das Team entscheidet — Business-Kontext (z.B. BYO-Key-Architekturentscheid, Consent-Formulierung) kennt nur das Team selbst

#### 2. Architektur (Modul 3)

* **Zitat als Leitplanke:** "Architektur ist die Summe der Entscheidungen, die schwer rückgängig zu machen sind." (Martin Fowler)
* **12 Architecture Decision Records** (Michael-Nygard-Format) in `docs/adr/`, u.a.:
  * SwiftData als lokale Persistenz-Technologie
  * Native iOS (SwiftUI) als Plattform
  * API-Keys im iOS Keychain mit `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
  * Kein Backend-Proxy im PoC — direkter API-Call vom iOS-Client
  * Claude API (USA) via Anthropic Commercial Terms im PoC, EU-Hosting vor v1.0 zu prüfen
  * `FitnessConnector`-Protocol als Abstraktion ab Sprint 1
  * Multi-Provider-LLM (Claude/Gemini/Mistral) im BYO-Key-Modell
  * CI auf selbst gehostetem macOS-Runner (bewusste Abweichung von der GitHub-hosted-Runner-Empfehlung aus Modul 7 — macOS-Runner auf GitHub sind teuer/limitiert)
  * Strava-OAuth2 sowie Polar AccessLink im BYO-App-Modell (Secret gehört dem Nutzer, nicht dem Team — kein Backend nötig)
* **C4-Modell:** C1 System Context (FitBuddy + User + Hevy/Claude/Strava/Polar APIs + Keychain) und C2 Container (iOS App, SwiftData Store, iOS Keychain) — kein Backend-Container
* **Monolith-Entscheid:** für ein Kleinteam über wenige Monate klar für eine native App ohne Server-Tier statt verteilter Architektur
* **MVVM-Schichtenarchitektur:** Presentation (SwiftUI Views) → ViewModel (`@MainActor`) → Service/Domain (InferenceService, ConnectorLayer) → Data (HevyConnector, KeychainService, SwiftData/`ModelActor`) — direkte Umsetzung der Quality-Attribute Testability und Maintainability
* **Quality Attributes als Architektur-Treiber** (Top 3 aus `docs/REQUIREMENTS.md` Kap. 5): **Security/Privacy** — kritischster Treiber, da Trainingsdaten Gesundheitsdaten nach nDSG Art. 5 lit. c sind (Keychain, Certificate Pinning); **Reliability** — Hevy hat selbst geschrieben "no guarantees — we might abandon this entirely" (Claude-Timeout + Cancel-Button, harter Logout bei ungültigem Key); **Maintainability** — `FitnessConnector`-Protocol vor der Hevy-Implementierung eingeführt, damit Strava/Polar ohne Refactor von Dashboard und AI-Engine dazukommen

#### 3. GitHub Project (Modul 4)

* **Von Architecture Draft zum Sprint:** User Stories → Task-Breakdown mit Claude → Sprint-Backlog nach MoSCoW → Sprint mit Definition of Done
* **Team-Rollen** (informell, nicht fix), mit AI-Einsatz analog Kursvorlage (Claude Code für Implementation, Testgenerierung, Review-Vorbereitung)
* **Git-Workflow 1:1 aus dem Kurs übernommen:** `main` (release-stable, nur via PR) / `develop` (Integration) / `feature/task-<issue#>-*` bzw. `fix/bug-<issue#>-*`; PR-Ziel immer `develop`; `develop` → `main` wöchentlich (Mittwochabend) als Bundle-PR; PR-Prozess: Branch pushen → PR öffnen → `/code-review` → Team-Review (mind. 1 Approval) → Merge
* **CLAUDE.md als Projektgedächtnis:** Stack, MVVM-Konventionen, Feature-first-Struktur, Sprachregeln (Code Englisch, Doku/Issues/PRs Deutsch), "was Claude nicht tun soll" (kein Force-Unwrap, XCUITests nicht lokal) — genau das im Kurs postulierte Prinzip ("Kontext ohne Wiederholung", "explizite Verbote werden respektiert")

#### 4. Coding & Tests (Modul 5–6)

* **Chat + Claude Code als Tandem:** Chat zum Denken/Planen, Claude Code (CLI) zum Umsetzen — genau der im Kurs beschriebene Loop (Chat → Spec besprechen → Claude Code implementiert → Chat-Review → Fix)
* **Permission Model bewusst genutzt:** einzelne Freigaben für Lerneffekt, später "yes, all session" für Tempo bei Routine-Tasks
* **Selbstverifikation:** Claude führt nach jeder Änderung die Tests selbst aus (XCTest in `FitBuddyTests/`) — "ein grüner Test ist ein Beweis, kein grüner Test eine Meinung"
* **Wer schreibt die Tests:** Agent schreibt die Masse (Happy Path, Edge Cases, Regressionstests), das Team schreibt die eigentlichen Spec-/Domänen-Invarianten-Tests — bewusst gegen die Falle "Agent testet sich selbst"
* **Prüf-Pyramide** angewendet: Compiler/Linter → Tests → Review (Claude + Mensch) → Mensch entscheidet
* **Wichtige Team-Regel:** XCUITests laufen nur in CI (Simulator-Boot kostet Zeit), lokal nur Unit Tests (`-skip-testing:FitBuddyUITests`) — Kurs-Prinzip "Verifier soll von selbst laufen" (CI = Modul 7), umgesetzt auf einem selbst gehosteten macOS-Runner (siehe Architektur-Entscheid zu CI oben)

#### 5. DevOps & CI (Modul 7)

* **Eigener macOS-Mini als selbst gehosteter GitHub-Actions-Runner:** statt der von GitHub gehosteten (teuren/limitierten) macOS-Runner läuft die Pipeline auf einem eigenen Mac mini im Team — bewusste Abweichung von der Kursvorlage, weil ein iOS-Build/Simulator-Lauf auf GitHub-gehosteten macOS-Runnern für ein Studierendenprojekt zu teuer bzw. zu limitiert gewesen wäre
* **Bei jedem Pull Request** führt dieser Runner automatisch die Unit-Tests (XCTest, `FitBuddyTests/`) aus — der Verifier-Loop aus Modul 6 (Mensch tippt lokal `pytest`/Tests) läuft jetzt bei jedem `git push`, ohne dass jemand ihn manuell startet
* **Zusätzlich laufen dort die XCUITests** (`FitBuddyUITests/`, Simulator-Boot) — genau der Grund, warum sie lokal bewusst übersprungen werden (`-skip-testing:FitBuddyUITests`): der Simulator-Boot dauert Minuten und blockiert die eigene Maschine, gehört also in CI statt in den lokalen Loop
* **Merge-Gate:** rot in CI = kein Merge in `develop` — dasselbe Prinzip wie im Kurs ("Continuous Integration = der Verifier ist nicht mehr optional")

#### 6. Live-Demo

* Onboarding-Screens (Hevy-Key + bis zu drei LLM-Provider-Keys, Trainingsprofil, Consent-Screen)
* Settings (Key-Verwaltung, zweite/dritte Datenquelle verbinden, Daten löschen/Reset)
* Dashboard (90 Tage aggregierte Hevy-Daten, Sessions, Gesamtvolumen, Muskelbelastungsverteilung)
* AI-Analyse (Prompt-Aufbau aus aggregierten Metriken, strukturierte Ergebnis-Karten mit Übung/Wert-von-nach/Begründung, Recovery- und Dysbalance-Hinweise)

---

### Persönliches Fazit / Erfahrungen

* Beeindruckend: mit AI + diesem strukturierten Vorgehen eine vollständige iOS-App bauen, ohne vorher Swift zu können
* Klarer, kursvorgegebener Ablauf half enorm — ohne ihn wäre das Projekt vermutlich unstrukturiert explodiert
* Kognitiver Nebeneffekt: Weil Claude Code so viel übernimmt, bleibt man teils weniger "invested" und lernt Swift selbst weniger tief — bewusster Trade-off zwischen Tempo und eigenem Lernerfolg

---

### Ausblick

**Nächste mögliche Features (v1, nicht Teil des PoC — aus `docs/REQUIREMENTS.md` Kap. 4 "Out of Scope")**
* Quellenübergreifende Analyse: Strava-/Polar-Sessions sind im PoC bereits verbunden, fliessen aber noch nicht in Analyse-Prompt, Übungsliste oder Progressionskurve ein
* Apple-Health-Integration (Schlaf/HRV/Ruheherzrate) — bewusst als offene Architekturfrage geführt, Empfehlung "OUT für PoC"
* Wochenübersicht als Push-Notification, Trainingsvorschlag zurück nach Hevy schreiben (beide bewusst "Won't" — Risiko: eine falsch übernommene AI-Empfehlung verändert einen echten Trainingsplan)

