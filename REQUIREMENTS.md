# FitBuddy — Requirements

Basierend auf `fitbuddy_user_stories_v5.xlsx` und Modul 2 Selbststudium (MoSCoW & Requirements).

## MoSCoW-Übersicht

| ID | Titel | Persona | MoSCoW |
|---|---|---|---|
| US-1 | API-Key sicher speichern | Marcus | Must |
| US-2 | 90 Tage Trainingsdaten im Dashboard | Marcus | Must |
| US-3 | AI-Analyse auf Knopfdruck | Jana | Must |
| US-4 | Onboarding in 3 Schritten | Jana | Must |
| US-5 | Zweite Datenquelle verbinden | Marcus | Should |
| US-6 | Analyse-Kontext transparent machen | Marcus & Jana | Should |
| US-7 | Übungssuche & Filter | Marcus | Should |
| US-8 | Datenquelle-Status sichtbar | Marcus & Jana | Could |
| US-9 | Progressionskurven pro Übung | Marcus | Could |
| US-10 | Daten manuell neu laden (Pull-to-Refresh) | Marcus | Could |
| US-11 | Wochenübersicht als Push-Notification | Jana | Won't |
| US-12 | Trainingsvorschlag zurück in Hevy schreiben | Marcus | Won't |

---

## Must Have — Zwingend für MVP

### US-1 · API-Key sicher speichern
**Als** technikaffiner Multi-App-Nutzer **möchte ich** meinen Hevy API-Key lokal auf meinem iPhone speichern, **damit** meine Trainingsdaten nie einen fremden Server verlassen.

**Begründung:** Ohne Keychain-Speicherung kein einziger API-Call; sicherheitskritisch und nicht-trivial, gehört in Sprint 1.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | App wird zum ersten Mal geöffnet | User gibt Key ein und tippt «Speichern» | Key landet ausschliesslich im iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`); sofort per `GET /workouts` validiert — HTTP 200 → Dashboard, sonst Fehlermeldung, Key wird verworfen |
| AC2 | Valider Key ist im Keychain gespeichert | App wird nach Kaltstart geöffnet | Innerhalb von 3s (ab `didFinishLaunchingWithOptions`) wird `GET /workouts` ausgeführt — HTTP 200 → Dashboard ohne erneute Key-Eingabe |
| AC3 | Gespeicherter Key wurde in Hevy widerrufen | Ein API-Call gibt HTTP 401 zurück | Key wird aus Keychain gelöscht, User landet auf Onboarding mit Meldung «Dein API-Key ist ungültig. Bitte gib einen neuen Key ein.» |
| AC4 | Gerät ist beim App-Start noch nicht entsperrt | App versucht, den Key zu lesen | Kein API-Call, kein Absturz — App wartet auf nächsten manuellen Start im entsperrten Zustand |

---

### US-2 · 90 Tage Trainingsdaten im Dashboard
**Als** Power-User mit Kraft- und Ausdauerdaten **möchte ich** meine letzten 90 Tage Hevy-Trainings in einem einzigen Dashboard sehen, **damit** ich meine Gesamtbelastung und Progression auf einen Blick beurteilen kann.

**Begründung:** Dashboard ist die Datenbasis für AI-Analyse (US-3) und alle weiteren Visualisierungen. 90 Tage statt 30: Progression ist erst über 8–12 Wochen sinnvoll messbar.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Gültiger API-Key ist hinterlegt | User öffnet das Dashboard | Angezeigt werden: Tabelle mit Sessions pro Datum, Gesamtvolumen in kg (Gewicht × Reps × Sets), Ø Trainingstage/Woche, Diagramm zur Muskelbelastungsverteilung — Zeitraum: letzte 90 Tage |
| AC2 | Hevy API ist nicht erreichbar | Dashboard wird geladen | Gecachte Daten werden angezeigt mit sichtbarem Hinweis auf letzten Sync-Zeitstempel |
| AC3 | User ist neu in Hevy oder hat >90 Tage nicht trainiert | User öffnet das Dashboard | Text: «No training data for the last 90 days» |

---

### US-3 · AI-Analyse auf Knopfdruck
**Als** Krafttraining-Einsteigerin **möchte ich** auf Knopfdruck eine AI-Analyse meiner Trainingslast abrufen, **damit** ich ohne Selbstinterpretation weiss, ob ich diese Woche steigern kann.

**Begründung:** Die AI-Empfehlung IST das Produkt — ohne sie wird FitBuddy zum reinen Hevy-Viewer. Epic: vor Sprint-Planung in Child Stories aufteilen.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Mindestens 2 Wochen Trainingsdaten vorhanden | Jana tippt auf «Analysieren» | Spinner erscheint sofort; Empfehlung wird angezeigt sobald Claude antwortet; nach 30s ohne Antwort erscheint Cancel-Button mit Meldung «Analysis is taking longer than expected — tap to cancel» |
| AC2 | Analyse ist abgeschlossen | Jana liest die Empfehlung | Empfehlung enthält eine konkrete Handlung («Erhöhe Kniebeuge-Gewicht um 2.5 kg»), nicht nur allgemeine Aussagen |
| AC3 | Analyse wird ausgeführt | LLM-Prompt wird zusammengestellt | Prompt enthält ausschliesslich Daten des eingeloggten Users — keine Benchmarks oder Normwerte fremder Nutzer |
| AC4 | User hat in 4 Wochen Beine, Oberkörper und Rücken trainiert | Empfehlung wird angezeigt | Geht auf mindestens 2 verschiedene Muskelgruppen ein |
| AC5 | User hat hohes Volumen aber konstant niedrige Gewichte | Analyse läuft | AI empfiehlt explizit Intensitätssteigerung (Gewicht), nicht pauschal «mehr trainieren» |
| AC6 | User hat in den letzten 7 Tagen an ≥6 Tagen trainiert | Analyse wird ausgeführt | Empfehlung enthält expliziten Hinweis auf Recovery-Bedarf — keine Steigerungsempfehlung ohne diesen Hinweis |
| AC7 | Analyse ist abgeschlossen | Empfehlung wird angezeigt | Nennt mindestens eine konkrete Übung mit konkretem Wert («Erhöhe Bankdrücken von 60 kg auf 62.5 kg») |
| AC8 | User trainiert Brust 3×/Woche, Beine nur 1×/Woche | Empfehlung wird generiert | AI weist auf Muskelgruppen-Dysbalance hin |
| AC9 | Empfehlung wurde angezeigt | — | Unter der Empfehlung erscheinen zwei Buttons: «Helpful» / «Not helpful» — Tap wird lokal gespeichert; kein Backend-Call |

---

### US-4 · Onboarding in 3 Schritten
**Als** Nutzerin ohne technischen Hintergrund **möchte ich** den Hevy und Claude API-Key in maximal 3 verständlichen Schritten einrichten, **damit** ich die App nutzen kann, ohne eine Dokumentation lesen zu müssen.

**Begründung:** Mit zwei API-Keys (Hevy + Claude) ist das Onboarding für Nicht-Techniker (Persona Jana) echtes Produktrisiko.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Jana öffnet FitBuddy zum ersten Mal | Onboarding-Flow startet | Jeder Schritt erklärt mit Screenshot wo in Hevy der API-Key zu finden ist |
| AC2 | Hevy API-Key wurde eingegeben und gespeichert | Jana tippt auf «Next» | Claude API-Key kann eingegeben oder vorerst übersprungen werden |
| AC3 | Jana gibt ungültigen Key ein | Sie tippt auf «Verbinden» | Fehlermeldung erscheint mit direktem Link zur Hevy API-Key-Seite |
| AC4 | Onboarding-Flow startet | Consent-Screen wird angezeigt | User sieht und bestätigt explizit: (1) Trainingsdaten werden für die AI-Analyse an Anthropic (USA) übertragen, (2) FitBuddy ist kein medizinisches Produkt — der User trägt selbst die Verantwortung für umgesetzte Empfehlungen und Steigerungen. Ohne Bestätigung kein Zugang zur App. |
| AC5 | User hat Consent gegeben | Consent wird gespeichert | Datum und Consent-Version werden lokal im Keychain gespeichert — kein erneutes Anzeigen bei App-Updates sofern Consent-Version identisch |

---

## Should Have — Wichtig, MVP funktioniert auch ohne

### US-5 · Zweite Datenquelle verbinden
**Als** Nutzer **möchte ich** einen zweiten Trainings-Account verbinden (z.B. Strava), **damit** FitBuddy auch meine Ausdauerdaten abruft.

**Begründung:** Differenzierung durch zweite Quelle ist Produktargument; Connector-Interface wird in MVP architektonisch verankert, Strava-Connector selbst erst v1.1 (OAuth + Normalisierung + kombinierte Analyse ≈ 1.5–2 Sprints).

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Nutzer tippt auf «Quelle hinzufügen» | Er wählt Quelle und schliesst OAuth-Flow ab | Aktivitäten der letzten 30 Tage erscheinen normalisiert im Dashboard neben bestehenden Daten |
| AC2 | Token einer Quelle ist abgelaufen | Dashboard lädt | Hinweis erscheint («Strava-Verbindung erneuern») mit direktem Link zum Re-Auth-Flow |

---

### US-6 · Analyse-Kontext transparent machen
**Als** Nutzer **möchte ich** sehen, auf welcher Datenbasis die AI-Empfehlung generiert wurde, **damit** ich die Empfehlung einordnen und ihr vertrauen oder sie hinterfragen kann.

**Begründung:** AC1 («Basierend auf X Trainings») sollte als AC in US-3 wandern; eigenständige Story nur für AC2 (Warnung bei dünner Datenbasis).

| # | Given | When | Then |
|---|---|---|---|
| AC1 | AI-Analyse wurde abgeschlossen | Empfehlung wird angezeigt | Kompakte Zusammenfassung: welche Quellen einbezogen, welcher Zeitraum, wie viele Trainings («Basierend auf 12 Hevy-Trainings der letzten 30 Tage») |
| AC2 | Weniger als 5 Trainings lagen im Analysezeitraum | Empfehlung wird angezeigt | Kontext-Hinweis enthält explizite Warnung, dass Datenbasis dünn ist |

---

### US-7 · Übungssuche & Filter
**Als** datengetriebener Nutzer **möchte ich** Übungen in meiner Trainingshistorie suchen und nach Muskelgruppe filtern, **damit** ich bei 50+ Übungen schnell die richtige für die Progressionskurve finde.

**Begründung:** Suche/Filter wird notwendig, sobald User-Historie >20 Übungen erreicht.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Marcus öffnet die Übungsübersicht mit ≥10 Einträgen | Er tippt in das Suchfeld | Liste filtert in Echtzeit (case-insensitive). Keine Ergebnisse → Hinweis «Keine Übungen gefunden». |
| AC2 | Marcus öffnet den Muskelgruppen-Filter | Er wählt «Beine» | Nur Übungen die Hevy der Kategorie Beine zuordnet werden angezeigt. Mehrfachauswahl möglich. |

---

## Could Have — Nice-to-have, wenn Sprint Luft hat

### US-8 · Datenquelle-Status sichtbar
**Als** Nutzer **möchte ich** auf einen Blick sehen, welche Datenquellen verbunden und aktuell sind, **damit** ich weiss, ob die AI-Analyse auf vollständigen oder veralteten Daten basiert.

**Begründung:** Bei nur einer Quelle (Hevy) reicht im PoC der Sync-Zeitstempel aus US-2 AC2; vollwertig relevant ab v1.1 (zweite Quelle live).

| # | Given | When | Then |
|---|---|---|---|
| AC1 | User öffnet das Dashboard | Eine Datenquelle wurde seit >24h nicht synchronisiert | Sichtbarer Indikator mit Zeitstempel des letzten erfolgreichen Syncs und Retry-Button |
| AC2 | Gespeicherter API-Key wurde in Quell-App widerrufen | FitBuddy macht Sync-Versuch | User wird aktiv benachrichtigt — kein stilles Weiterlaufen mit gecachten Daten |

---

### US-9 · Progressionskurven pro Übung
**Als** datengetriebener Nutzer **möchte ich** Progressionskurven pro Übung über Zeit sehen, **damit** ich Plateaus früh erkenne und meinen Plan gezielt anpassen kann.

**Begründung:** US-3 deckt den Hauptnutzen ab; Epley-Formel + Plateau-Detection sind nicht-trivial. Hängt von US-11 ab wenn Historie wächst.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Übung hat ≥2 Sessions mit Gewicht+Reps in 12 Wochen | Marcus öffnet Detailansicht | Liniendiagramm mit 1RM-Schätzwert pro Session (Epley: `weight × (1 + reps/30)`), X=Datum, Y=kg |
| AC2 | Übung hat in 3 aufeinanderfolgenden Sessions keinen höheren 1RM erreicht | Dashboard oder Detailansicht lädt | Übung wird visuell als «Plateau» markiert (gelbes Label) |
| AC3 | Übung hat <2 Sessions mit verwertbaren Daten in 12 Wochen | Detailansicht öffnet | Kein Diagramm — Hinweis: «Noch zu wenig Daten — mindestens 2 Sessions nötig» |

---

### US-10 · Daten manuell neu laden (Pull-to-Refresh)
**Als** Nutzer **möchte ich** die Trainingsdaten manuell neu laden können, **damit** ich nach einem kurzen API-Ausfall sofort aktuelle Daten sehe ohne die App neu zu starten.

**Begründung:** iOS-Pattern, das User erwarten — kein Showstopper. 1–2 Tage Aufwand, ergänzt US-2 AC2 zum vollständigen Offline/Online-Flow.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Dashboard zeigt gecachte Daten (API war down) | User zieht Liste nach unten | Neuer API-Call zu `GET /workouts` wird ausgelöst. Bei Erfolg: Daten aktualisiert, Sync-Zeitstempel erneuert. |
| AC2 | Pull-to-Refresh wurde ausgelöst | API gibt erneut einen Fehler zurück | Fehlermeldung erscheint, gecachte Daten bleiben sichtbar, Spinner verschwindet. |

---

## Won't Have — Bewusst ausgeschlossen für diesen PoC

### US-11 · Wochenübersicht als Push-Notification
**Begründung:** iOS-Permission-Flow + Background-Scheduling + LLM-Call-Fallback ist eigenes Sub-System. Relevant ab v1.2, wenn Retention-Daten zeigen, dass User die App nicht regelmässig öffnen.

### US-12 · Trainingsvorschlag von FitBuddy zurück in Hevy schreiben
**Begründung:** Setzt Hevy PRO voraus. Erfordert Klärung des Write-Targets (Routine vs. zukünftiges Workout) und UX für Bestätigung/Undo. Risiko: Empfehlung könnte falsch übernommen werden. Relevant ab v1.2 nach US-5 (Strava).

---

## Nicht-funktionale Anforderungen

| Bereich | Anforderung |
|---|---|
| Performance | Spinner erscheint sofort nach Tap auf «Analysieren»; Cancel-Button nach 30s ohne Antwort (US-3 AC1) |
| Performance | Dashboard-Load innerhalb von 3 Sekunden nach Kaltstart (US-1 AC2) |
| Sicherheit | API-Keys ausschliesslich im iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) |
| Privacy | Keine User-Daten auf externen Servern (ausser direktem API-Call zu Hevy/Claude) |
| Sprache | English-only (alle UI-Strings, Fehlermeldungen, System-Prompt) — kein i18n-Framework |
| Datenschutz | Nur Daten des eingeloggten Users im LLM-Prompt (keine Benchmarks fremder Nutzer) |
| Datenschutz | Consent (Datenübertragung an Anthropic + Eigenverantwortung) wird beim Onboarding eingeholt und lokal gespeichert (US-4 AC4/AC5) |
| LLM-Kosten | Max. 1 AI-Analyse pro User alle 6 Stunden — Cooldown mit sichtbarem Timer («Next analysis available in Xh Ym») |
| LLM-Kosten | Analyse-Button disabled während laufendem Call — kein Doppel-Submit möglich |

---

## Offene Entscheide

| Frage | Status |
|---|---|
| Apple Health (Schlaf, HRV, Ruheherzrate) — IN oder OUT of Scope? | Offen — Entscheid vor Architektur nötig |
| US-3 (AI-Analyse) und US-5 (zweite Datenquelle) als Epics in Child Stories aufteilen | Offen — vor Sprint-Planung |
| Fehlerzustand 401: harter Logout (US-1 AC3) oder weicher Banner? | Empfehlung: harter Logout im PoC |

---

## Änderungshistorie

| Neue ID | Original ID | Titel | MoSCoW alt → neu | Kommentar |
|---|---|---|---|---|
| US-1 | US-1 | API-Key sicher speichern | Must → Must | Unverändert |
| US-2 | US-2 | 30 Tage Trainingsdaten im Dashboard | Must → Must | Unverändert |
| US-3 | US-3 | AI-Analyse auf Knopfdruck | Must → Must | Unverändert |
| US-4 | US-4 | Onboarding in 3 Schritten | Must → Must | Unverändert |
| US-5 | US-7 | Zweite Datenquelle verbinden | Could → Should | Aufgewertet: strategische Absicherung |
| US-6 | US-10 | Analyse-Kontext transparent machen | Must → Should | Abgewertet |
| US-7 | US-11 | Übungssuche & Filter | Should → Should | Unverändert |
| US-8 | US-9 | Datenquelle-Status sichtbar | Must → Could | Abgewertet |
| US-9 | US-5 | Progressionskurven pro Übung | Should → Could | Abgewertet |
| US-10 | US-12 | Daten manuell neu laden | Should → Could | Abgewertet |
| US-11 | US-6 | Wochenübersicht als Push-Notification | Could → Won't | Zu viel Aufwand für PoC |
| US-12 | US-14 | Trainingsvorschlag zurück in Hevy schreiben | — → Won't | Neu hinzugefügt |
| — | US-13 | App-Sprache Englisch | Must → Entfernt | Als Definition of Done geführt |
