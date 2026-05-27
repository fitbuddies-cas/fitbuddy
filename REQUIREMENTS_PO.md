# FitBuddy — Requirements Document
*Strukturierte Zusammenfassung für CAS ADAI 2026, Modul 3.
Konsolidiert aus `PROJECT.md`, `REQUIREMENTS.md` und `ARCHITECTURE.md`.*



# 1. Projektzusammenfassung

FitBuddy ist eine native iOS-App, die Trainingsdaten aus Hevy (PoC) und perspektivisch Strava (v1.1) auf einem gemeinsamen Datenmodell normalisiert und in einem 90-Tage-Dashboard zusammenführt. Auf Knopfdruck generiert die Claude API daraus eine personalisierte Progressionsempfehlung mit konkreten Werten (z. B. Gewicht, Übung, Recovery-Hinweis). API-Keys verbleiben im iOS Keychain — die App hat kein Backend, alle API-Calls laufen direkt vom Gerät.



# 2. Personas

### Marcus Huber — Technikaffiner Power-User

| | |
|---|---|
| **JTBD** | Will seine Gesamtbelastung aus Kraft- und Ausdauertraining auf einen Blick beurteilen, um datenbasiert zu entscheiden, ob er steigert oder regeneriert. |
| **Problem** | Trainingsdaten liegen in Silos (Hevy, Strava, Apple Health). Hat einen Hevy Pro Account inkl. API-Key, ist mit API-Key-Handling vertraut. |
| **Ziel** | Ein einziges Dashboard, das Kraft- und Cardio-Last konsolidiert; AI-Empfehlung mit Recovery-Berücksichtigung. |
| **Risiko-Trigger** | Onboarding-Komplexität (zwei API-Keys) ist für ihn akzeptabel, aber nicht beliebig. |

### Jana Vogel — Krafttraining-Einsteigerin

| | |
|---|---|
| **JTBD** | Will ohne eigene Dateninterpretation wissen, ob sie diese Woche steigern kann — konkret, nicht abstrakt. |
| **Problem** | Trainiert regelmässig, kann ihre Trainingsdaten aber nicht selbst auswerten. Kein technischer Hintergrund. |
| **Ziel** | Eine konkrete Handlungsempfehlung pro Trainingswoche ("Erhöhe Kniebeuge um 2.5 kg"), ohne Fachjargon. |
| **Risiko-Trigger** | Bricht bei zu technischem Onboarding ab — API-Key-Setup ist hier echtes Produktrisiko (R4). |



# 3. User Stories mit Acceptance Criteria

## 3.1 Must Have — Zwingend für MVP

### 3.1.1 US-1 · API-Key sicher speichern 
**Als** technikaffiner Multi-App-Nutzer **möchte ich** meinen Hevy API-Key lokal auf meinem iPhone speichern, **damit** meine Trainingsdaten nie einen fremden Server verlassen.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | App wird zum ersten Mal geöffnet | User gibt Key ein und tippt «Speichern» | Key landet ausschliesslich im iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`); sofort per `GET /workouts` validiert — HTTP 200 → Dashboard, sonst Fehlermeldung, Key wird verworfen |
| AC2 | Valider Key ist im Keychain gespeichert | App wird nach Kaltstart geöffnet | Innerhalb von 3 s (ab `didFinishLaunchingWithOptions`) wird `GET /workouts` ausgeführt — HTTP 200 → Dashboard ohne erneute Key-Eingabe |
| AC3 | Gespeicherter Key wurde in Hevy widerrufen | Ein API-Call gibt HTTP 401 zurück | Key wird aus Keychain gelöscht, User landet auf Onboarding mit Meldung «Dein API-Key ist ungültig. Bitte gib einen neuen Key ein.» |
| AC4 | Gerät ist beim App-Start noch nicht entsperrt | App versucht, den Key zu lesen | Kein API-Call, kein Absturz — App wartet auf nächsten manuellen Start im entsperrten Zustand |

### 3.1.2 US-2 · 90 Tage Trainingsdaten im Dashboard
**Als** Power-User mit Kraft- und Ausdauerdaten **möchte ich** meine letzten 90 Tage Hevy-Trainings in einem einzigen Dashboard sehen, **damit** ich meine Gesamtbelastung und Progression auf einen Blick beurteilen kann.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Gültiger API-Key ist hinterlegt | User öffnet das Dashboard | Angezeigt werden: Tabelle mit Sessions pro Datum, Gesamtvolumen in kg (Gewicht × Reps × Sets), Ø Trainingstage/Woche, Diagramm zur Muskelbelastungsverteilung — Zeitraum: letzte 90 Tage |
| AC2 | Hevy API ist nicht erreichbar | Dashboard wird geladen | Gecachte Daten werden angezeigt mit sichtbarem Hinweis auf letzten Sync-Zeitstempel |
| AC3 | User ist neu in Hevy oder hat >90 Tage nicht trainiert | User öffnet das Dashboard | Text: «No training data for the last 90 days» |

### 3.1.3 US-3 · AI-Analyse auf Knopfdruck
**Als** Krafttraining-Einsteigerin **möchte ich** auf Knopfdruck eine AI-Analyse meiner Trainingslast abrufen, **damit** ich ohne Selbstinterpretation weiss, ob ich diese Woche steigern kann.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Mindestens 2 Wochen Trainingsdaten vorhanden | Jana tippt auf «Analysieren» | Spinner erscheint sofort; Empfehlung wird angezeigt sobald Claude antwortet; nach 30 s ohne Antwort erscheint Cancel-Button «Analysis is taking longer than expected — tap to cancel» |
| AC2 | Analyse ist abgeschlossen | Jana liest die Empfehlung | Empfehlung enthält eine konkrete Handlung («Erhöhe Kniebeuge-Gewicht um 2.5 kg»), nicht nur allgemeine Aussagen |
| AC3 | Analyse wird ausgeführt | LLM-Prompt wird zusammengestellt | Prompt enthält ausschliesslich Daten des eingeloggten Users — keine Benchmarks oder Normwerte fremder Nutzer |
| AC4 | User hat in 4 Wochen Beine, Oberkörper und Rücken trainiert | Empfehlung wird angezeigt | Geht auf mindestens 2 verschiedene Muskelgruppen ein |
| AC5 | User hat hohes Volumen aber konstant niedrige Gewichte | Analyse läuft | AI empfiehlt explizit Intensitätssteigerung (Gewicht), nicht pauschal «mehr trainieren» |
| AC6 | User hat in den letzten 7 Tagen an ≥6 Tagen trainiert | Analyse wird ausgeführt | Empfehlung enthält expliziten Hinweis auf Recovery-Bedarf — keine Steigerungsempfehlung ohne diesen Hinweis |
| AC7 | Analyse ist abgeschlossen | Empfehlung wird angezeigt | Nennt mindestens eine konkrete Übung mit konkretem Wert («Erhöhe Bankdrücken von 60 kg auf 62.5 kg») |
| AC8 | User trainiert Brust 3×/Woche, Beine nur 1×/Woche | Empfehlung wird generiert | AI weist auf Muskelgruppen-Dysbalance hin |
| AC9 | Empfehlung wurde angezeigt | — | Unter der Empfehlung erscheinen zwei Buttons: «Helpful» / «Not helpful» — Tap wird lokal gespeichert; kein Backend-Call |

> **Hinweis:** US-3 ist als Epic geführt und vor Sprint-Planung in Child Stories aufzuteilen (Prompt-Design, UI, Error-Handling, Disclaimer).

### 3.1.4 US-4 · Onboarding in 3 Schritten
**Als** Nutzerin ohne technischen Hintergrund **möchte ich** den Hevy und Claude API-Key in maximal 3 verständlichen Schritten einrichten, **damit** ich die App nutzen kann, ohne eine Dokumentation lesen zu müssen.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Jana öffnet FitBuddy zum ersten Mal | Onboarding-Flow startet | Jeder Schritt erklärt mit Screenshot, wo in Hevy der API-Key zu finden ist |
| AC2 | Hevy API-Key wurde eingegeben und gespeichert | Jana tippt auf «Next» | Claude API-Key kann eingegeben oder vorerst übersprungen werden |
| AC3 | Jana gibt ungültigen Key ein | Sie tippt auf «Verbinden» | Fehlermeldung erscheint mit direktem Link zur Hevy API-Key-Seite |
| AC4 | Onboarding-Flow startet | Consent-Screen wird angezeigt | User sieht und bestätigt explizit: (1) Trainingsdaten (Gesundheitsdaten nach nDSG Art. 5 lit. c) werden für die AI-Analyse an Anthropic Inc., USA übertragen — die USA bietet kein dem Schweizer Recht gleichwertiges Datenschutzniveau; die Übertragung stützt sich auf den von FitBuddy abgeschlossenen AVV/DPA mit Anthropic. (2) FitBuddy ist kein medizinisches Produkt — der User trägt selbst die Verantwortung für umgesetzte Empfehlungen. (3) Link zur Datenschutzerklärung sichtbar. Ohne Bestätigung kein Zugang zur App. |
| AC5 | User hat Consent gegeben | Consent wird gespeichert | Datum und Consent-Version werden lokal im Keychain gespeichert — kein erneutes Anzeigen bei App-Updates, sofern Consent-Version identisch |

---

## 3.2 Should Have — Wichtig, MVP funktioniert auch ohne

### 3.2.1 US-5 · Zweite Datenquelle verbinden
**Als** Nutzer **möchte ich** einen zweiten Trainings-Account verbinden (z. B. Strava), **damit** FitBuddy auch meine Ausdauerdaten abruft.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Nutzer tippt auf «Quelle hinzufügen» | Er wählt Quelle und schliesst OAuth-Flow ab | Aktivitäten der letzten 30 Tage erscheinen normalisiert im Dashboard neben bestehenden Daten |
| AC2 | Token einer Quelle ist abgelaufen | Dashboard lädt | Hinweis erscheint («Strava-Verbindung erneuern») mit direktem Link zum Re-Auth-Flow |

> **Hinweis:** Im PoC wird nur das `FitnessConnector`-Interface verankert; der Strava-Connector selbst erst in v1.1.

### 3.2.2 US-6 · Analyse-Kontext transparent machen
**Als** Nutzer **möchte ich** sehen, auf welcher Datenbasis die AI-Empfehlung generiert wurde, **damit** ich die Empfehlung einordnen und ihr vertrauen oder sie hinterfragen kann.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | AI-Analyse wurde abgeschlossen | Empfehlung wird angezeigt | Kompakte Zusammenfassung: welche Quellen einbezogen, welcher Zeitraum, wie viele Trainings («Basierend auf 12 Hevy-Trainings der letzten 30 Tage») |
| AC2 | Weniger als 5 Trainings lagen im Analysezeitraum | Empfehlung wird angezeigt | Kontext-Hinweis enthält explizite Warnung, dass Datenbasis dünn ist |

### 3.2.3 US-7 · Übungssuche & Filter 
**Als** datengetriebener Nutzer **möchte ich** Übungen in meiner Trainingshistorie suchen und nach Muskelgruppe filtern, **damit** ich bei 50+ Übungen schnell die richtige für die Progressionskurve finde.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Marcus öffnet die Übungsübersicht mit ≥10 Einträgen | Er tippt in das Suchfeld | Liste filtert in Echtzeit (case-insensitive). Keine Ergebnisse → Hinweis «Keine Übungen gefunden». |
| AC2 | Marcus öffnet den Muskelgruppen-Filter | Er wählt «Beine» | Nur Übungen, die Hevy der Kategorie Beine zuordnet, werden angezeigt. Mehrfachauswahl möglich. |



## 3.3 Could Have — Nice-to-have, wenn Sprint Luft hat

### 3.3.1 US-8 · Datenquelle-Status sichtbar
**Als** Nutzer **möchte ich** auf einen Blick sehen, welche Datenquellen verbunden und aktuell sind, **damit** ich weiss, ob die AI-Analyse auf vollständigen oder veralteten Daten basiert.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | User öffnet das Dashboard | Eine Datenquelle wurde seit >24 h nicht synchronisiert | Sichtbarer Indikator mit Zeitstempel des letzten erfolgreichen Syncs und Retry-Button |
| AC2 | Gespeicherter API-Key wurde in Quell-App widerrufen | FitBuddy macht Sync-Versuch | User wird aktiv benachrichtigt — kein stilles Weiterlaufen mit gecachten Daten |

### 3.3.2 US-9 · Progressionskurven pro Übung
**Als** datengetriebener Nutzer **möchte ich** Progressionskurven pro Übung über Zeit sehen, **damit** ich Plateaus früh erkenne und meinen Plan gezielt anpassen kann.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Übung hat ≥2 Sessions mit Gewicht+Reps in 12 Wochen | User öffnet Detailansicht | Liniendiagramm mit 1RM-Schätzwert pro Session (Epley: `weight × (1 + reps/30)`), X=Datum, Y=kg |
| AC2 | Übung hat in 3 aufeinanderfolgenden Sessions keinen höheren 1RM erreicht | Dashboard oder Detailansicht lädt | Übung wird visuell als «Plateau» markiert (gelbes Label) |
| AC3 | Übung hat <2 Sessions mit verwertbaren Daten in 12 Wochen | Detailansicht öffnet | Kein Diagramm — Hinweis: «Noch zu wenig Daten — mindestens 2 Sessions nötig» |

### 3.3.3 US-10 · Daten manuell neu laden / Pull-to-Refresh
**Als** Nutzer **möchte ich** die Trainingsdaten manuell neu laden können, **damit** ich nach einem kurzen API-Ausfall sofort aktuelle Daten sehe, ohne die App neu zu starten.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Dashboard zeigt gecachte Daten (API war down) | User zieht Liste nach unten | Neuer API-Call zu `GET /workouts` wird ausgelöst. Bei Erfolg: Daten aktualisiert, Sync-Zeitstempel erneuert. |
| AC2 | Pull-to-Refresh wurde ausgelöst | API gibt erneut einen Fehler zurück | Fehlermeldung erscheint, gecachte Daten bleiben sichtbar, Spinner verschwindet. |


## 3.4 Won't Have — Bewusst ausgeschlossen für diesen PoC

### 3.4.1 US-11 · Wochenübersicht als Push-Notification 
Out of Scope — siehe Abschnitt 7.

### 3.4.2 US-12 · Trainingsvorschlag zurück in Hevy schreiben 
Out of Scope — siehe Abschnitt 7.



## 4. MoSCoW-Priorisierung mit Begründungen

| ID | Titel | Persona | MoSCoW | Begründung |
|---|---|---|---|---|
| US-1 | API-Key sicher speichern | Marcus | **Must** | Ohne Keychain-Speicherung kein einziger API-Call. Sicherheitskritisch, nicht-trivial — gehört in Sprint 1. |
| US-2 | 90 Tage Trainingsdaten im Dashboard | Marcus | **Must** | Datenbasis für AI-Analyse (US-3) und alle Visualisierungen. 90 Tage statt 30, da Progression erst über 8–12 Wochen messbar ist. |
| US-3 | AI-Analyse auf Knopfdruck | Jana | **Must** | Die AI-Empfehlung *ist* das Produkt — ohne sie wird FitBuddy zum reinen Hevy-Viewer. |
| US-4 | Onboarding in 3 Schritten | Jana | **Must** | Zwei API-Keys (Hevy + Claude) sind für Persona Jana echtes Produktrisiko (R4). Onboarding muss ohne Doku machbar sein. |
| US-5 | Zweite Datenquelle verbinden | Marcus | **Should** | Differenzierung durch zweite Quelle ist Produktargument. Connector-Interface wird im MVP architektonisch verankert, Strava-Connector erst v1.1 (OAuth + Normalisierung + kombinierte Analyse ≈ 1.5–2 Sprints). |
| US-6 | Analyse-Kontext transparent machen | Marcus & Jana | **Should** | AC1 könnte als AC in US-3 wandern; eigenständige Story v. a. wegen AC2 (Warnung bei dünner Datenbasis). |
| US-7 | Übungssuche & Filter | Marcus | **Should** | Wird notwendig, sobald User-Historie >20 Übungen erreicht. Für PoC-Demos mit wenigen Sessions verzichtbar. |
| US-8 | Datenquelle-Status sichtbar | Marcus & Jana | **Could** | Bei nur einer Quelle (Hevy) reicht im PoC der Sync-Zeitstempel aus US-2 AC2. Vollwertig relevant ab v1.1. |
| US-9 | Progressionskurven pro Übung | Marcus | **Could** | US-3 deckt den Hauptnutzen ab. Epley-Formel + Plateau-Detection sind nicht-trivial. |
| US-10 | Daten manuell neu laden | Marcus | **Could** | iOS-Pattern, das User erwarten — kein Showstopper. 1–2 Tage Aufwand, ergänzt US-2 AC2. |
| US-11 | Wochenübersicht als Push-Notification | Jana | **Won't** | iOS-Permission-Flow + Background-Scheduling + LLM-Call-Fallback ist eigenes Sub-System. Relevant ab v1.2. |
| US-12 | Trainingsvorschlag zurück in Hevy schreiben | Marcus | **Won't** | Setzt Hevy PRO voraus, erfordert UX-Klärung (Write-Target, Undo). Risiko: Empfehlung falsch übernommen. Relevant ab v1.2. |



## 5. Offene Risiken — vor Sprint-Planung zu klären

Die vier in `PROJECT.md` dokumentierten Risiken (R1–R4) — alle relevant für den PoC, je mit Beschreibung, aktueller Massnahme, was offen bleibt und Klärungsbedarf.

### Risiko 1 — Plattform-Abhängigkeit Hevy API (R1)
- **Beschreibung:** Die Hevy API liefert keine Stabilitätsgarantie («no guarantees — we might abandon this entirely»). Strava hat 2020 die eigene API massiv eingeschränkt, was die Branchenrealität zeigt. Fällt die Hevy API aus oder ändert sich das ToS für kommerzielle Nutzung, ist die einzige Datenquelle im PoC weg.
- **Aktuelle Massnahme:** Connector-Interface (ADR-3) ist architektonisch verankert — zweite Quelle ist ohne Refactor einbindbar.
- **Was noch offen ist:** Die ToS-Prüfung von Hevy für kommerzielle bzw. App-distribuierte API-Nutzung ist als Aufgabe in `PROJECT.md` erwähnt, aber nicht erledigt. Wenn Hevy die API-Nutzung für Drittanbieter-Apps untersagt, ist der PoC distributionsrechtlich problematisch — selbst über TestFlight.
- **Klärungsbedarf:** ToS-Review vor Sprint 1 abschliessen. Falls kritisch: zweite Quelle (Strava) als gleichwertige Must-Have-Option erwägen.

### Risiko 2 — Markt-Differenzierung (R2)
- **Beschreibung:** Hevy könnte selbst eine native Strava-Integration ankündigen. In dem Moment ist die reine Datenaggregation (Hevy + Strava in einer Sicht) als Produktargument für Hevy-only-Nutzer obsolet — FitBuddy bleibt nur differenziert über die Qualität der AI-Empfehlung.
- **Aktuelle Massnahme:** Der echte Moat ist gemäss `PROJECT.md` die AI-Qualität, nicht die Aggregation. US-3 ist entsprechend als Must-Have priorisiert und mit acht inhaltlichen ACs versehen (konkrete Werte, Recovery, Muskelgruppen-Balance, Dysbalance-Erkennung).
- **Was noch offen ist:** «AI-Qualität» ist im PoC nicht messbar definiert. US-3 AC9 sammelt zwar «Helpful / Not helpful»-Feedback lokal — es gibt aber keine festgelegte Erfolgsschwelle und keinen Vergleich gegen einen Baseline-Output (z. B. eine regelbasierte Empfehlung). Ohne diese Definition lässt sich nicht beurteilen, ob der Moat trägt.
- **Klärungsbedarf:** Vor Sprint 3 (US-3-Implementierung): definieren, wie AI-Qualität für die PoC-Demo gemessen wird — mindestens als qualitatives Review-Protokoll mit Testdaten beider Personas. Für die Risiko-Mitigation langfristig: Monitoring der Hevy-Roadmap auf Strava-Integrations-Ankündigungen.

### Risiko 3 — Write-back-Risiko (R3)
- **Beschreibung:** Eine AI-generierte Empfehlung, die direkt in Hevy als Plan geschrieben wird, kann zu falscher Progression oder einem überschriebenen User-Plan führen. Der Schaden ist real (User trainiert nach falschem Wert), nicht nur kosmetisch.
- **Aktuelle Massnahme:** US-12 ist als Won't priorisiert — kein Write-back im PoC.
- **Was noch offen ist:** Das Risiko verschiebt sich, sobald US-12 in v1.2 priorisiert wird. Es gibt heute keine festgelegten Abnahmekriterien für ein sicheres Write-back (Undo-Fenster? Bestätigungsdialog? Schreibziel Routine vs. nächste Session?). Ohne diese Klärung wird US-12 bei späterer Priorisierung erneut zum Showstopper.
- **Klärungsbedarf:** Spätestens vor v1.2-Sprint-Planung Akzeptanzkriterien für Write-back-UX definieren. Für den PoC selbst keine Aktion nötig — Risiko aktiv überwachen.

### Risiko 4 — Onboarding-Hürde (R4)
- **Beschreibung:** Persona Jana hat keinen technischen Hintergrund. Zwei API-Keys (Hevy + Claude) plus Consent-Screen plus Datenschutz-Disclaimer in einem Onboarding sind echtes Produktrisiko: Wenn sie abbricht, kommt sie nie zur AI-Analyse (dem eigentlichen Produktwert).
- **Aktuelle Massnahme:** US-4 ist als Must-have priorisiert mit dem Anspruch «max. 3 verständliche Schritte ohne Doku». Claude-Key kann übersprungen werden (US-4 AC2).
- **Was noch offen ist:** «3 Schritte» ist nicht messbar. Es gibt keinen definierten Abbruchs-Schwellenwert und keinen UX-Test mit einer Jana-ähnlichen Testperson. Der Consent-Screen (US-4 AC4) ist juristisch notwendig, aber inhaltlich anspruchsvoll — eine Hürde, die in den 3 Schritten *zusätzlich* untergebracht werden muss.
- **Klärungsbedarf:** Vor Sprint 4 (Onboarding-Polish): Usability-Test mit mind. einer nicht-technischen Testperson. Definition, was «Erfolg» beim Onboarding heisst (Completion-Rate als beobachtbare Metrik, auch im PoC).

## 6. Nicht-funktionale Anforderungen

| Bereich | Anforderung |
|---|---|
| Performance | Spinner erscheint sofort nach Tap auf «Analysieren»; Cancel-Button nach 30s ohne Antwort (US-3 AC1) |
| Performance | Dashboard-Load innerhalb von 3 Sekunden nach Kaltstart (US-1 AC2) |
| Sicherheit | API-Keys ausschliesslich im iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) |
| Privacy | Keine User-Daten auf externen Servern (ausser direktem API-Call zu Hevy/Claude) |
| Sprache | English-only (alle UI-Strings, Fehlermeldungen, System-Prompt) — kein i18n-Framework |
| Datenschutz | Nur Daten des eingeloggten Users im LLM-Prompt (keine Benchmarks fremder Nutzer) |
| Datenschutz | Consent (Datenübertragung an Anthropic + Eigenverantwortung) wird beim Onboarding eingeholt und lokal gespeichert (US-4 AC4/AC5) |
| Datenschutz (nDSG) | Trainingsdaten sind Gesundheitsdaten nach Art. 5 lit. c nDSG — explizite Einwilligung ist Pflicht. Übertragung an Anthropic (USA) stützt sich auf AVV/DPA, den das FitBuddy-Team einmalig bei Anthropic abschliesst (nicht der Enduser). |
| Datenschutz (nDSG) | Die App enthält einen statischen Datenschutzerklärung-Screen (erreichbar aus Onboarding + Einstellungen) mit: Verantwortlichem, bearbeiteten Daten, Zweck, Drittempfängern (Hevy/Anthropic), Drittland USA, Rechten der betroffenen Person (Auskunft, Löschung). |
| Datenschutz (nDSG) | User kann jederzeit alle lokal gespeicherten Daten löschen (Keychain-Einträge + Cache) über «Daten löschen / Account zurücksetzen» in den Einstellungen — App kehrt in den Onboarding-Zustand zurück. |
| LLM-Kosten | Max. 1 AI-Analyse pro User alle 6 Stunden — Cooldown mit sichtbarem Timer («Next analysis available in Xh Ym») |
| LLM-Kosten | Analyse-Button disabled während laufendem Call — kein Doppel-Submit möglich |


## 7. Out of Scope

Bewusst ausgeschlossen für den PoC. Dokumentiert, damit später kein Scope-Creep entsteht.

| Bereich | Out of Scope weil |
|---|---|
| **US-11** Push-Notifications (Wochenübersicht) | iOS-Permission-Flow, Background-Scheduling, LLM-Fallback bei Offline-Zustand — eigenes Sub-System. Frühestens v1.2 sinnvoll, wenn Retention-Daten zeigen, dass User die App nicht regelmässig öffnen. |
| **US-12** Write-back nach Hevy | Erfordert Hevy PRO, ungeklärtes Write-Target (Routine vs. zukünftiges Workout) und Undo-UX. Falsch übernommene AI-Empfehlung ist ein realer Schaden für den User (R3). |
| **Strava-Connector (Implementierung)** | Nur das `FitnessConnector`-Interface wird verankert (US-5 / ADR-3). Die OAuth-Implementierung samt Token-Refresh und Cross-Source-Analyse kommt in v1.1. |
| **Apple Health Integration** | Siehe Risiko 1 — Vorschlag: OUT für PoC. |
| **i18n / Lokalisierung** | English-only ist Definition of Done — kein Framework, keine zweite Sprache. Spart Übersetzungs-Roundtrips beim Prompt-Tuning. |
| **App Store Release** | Distribution ausschliesslich via TestFlight / Sideload. Spart App-Store-Review, Marketing-Assets und Compliance-Roundtrips. |
| **Backend-Proxy für Claude API** | ADR-1: Key direkt im Keychain, Call direkt vom Gerät. Vereinfacht PoC, ist aber vor v1.0 zwingend zu revisiten (Key-Exposition bei Gerätekompromittierung). |
| **AWS Bedrock EU (eu-central-1)** | ADR-5: PoC nutzt Claude API USA mit AVV + Consent. Migration auf Bedrock Frankfurt ist v1.0-Pflicht, nicht PoC-Inhalt. |
| **Eigenes Tracking / Analytics** | Kein Mixpanel, kein Amplitude, kein Crashlytics im PoC. Würde Datenschutz-Erklärung verkomplizieren und Consent verändern. |
| **Plateau-Detection als eigenständiges Feature** | Teil von US-9 (Could), kein eigenes Item. Wenn US-9 nicht in den Sprint passt, fällt es ersatzlos weg. |


*Stand: 27.05.2026 · Quellen: `PROJECT.md`, `REQUIREMENTS.md` v5, `ARCHITECTURE.md`*
