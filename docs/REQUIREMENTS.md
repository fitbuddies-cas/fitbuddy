# FitBuddy — Requirements Document
*Strukturierte Zusammenfassung für CAS ADAI 2026, Modul 3.
Konsolidiert aus `PROJECT.md`, `REQUIREMENTS.md` und `ARCHITECTURE.md`.*

> **Dokumentationsstand:** Stand nach US-17 «Steigerungsempfehlung passt zur Übung und zur Last» (Issue #225, Task-Kette #231–#240) — drei Datenquellen (Hevy, Strava, Polar), drei LLM-Anbieter mit Fallback-Kette, SwiftData-Schema V6, ADR-001 bis ADR-013.


# 1. User Stories mit Acceptance Criteria

## 1.1 Must Have — Zwingend für PoC

### 1.1.1 US-1 · API-Key sicher speichern 
**Als** technikaffiner Multi-App-Nutzer **möchte ich** meine API-Keys (Hevy sowie bis zu drei LLM-Provider) lokal auf meinem iPhone speichern, **damit** meine Trainingsdaten nie einen fremden Server verlassen.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | App wird zum ersten Mal geöffnet | User gibt Key ein und tippt «Speichern» | Key landet ausschliesslich im iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`); sofort per `GET /workouts` validiert — HTTP 200 → Dashboard, sonst Fehlermeldung, Key wird verworfen |
| AC2 | Valider Key ist im Keychain gespeichert | App wird nach Kaltstart geöffnet | Innerhalb von 10 s (ab `didFinishLaunchingWithOptions`) wird `GET /workouts` ausgeführt — HTTP 200 → Dashboard ohne erneute Key-Eingabe |
| AC3 | Gespeicherter Key wurde in Hevy widerrufen | Ein API-Call gibt HTTP 401 zurück | Key wird aus Keychain gelöscht, User landet auf Onboarding mit Meldung «Dein API-Key ist ungültig. Bitte gib einen neuen Key ein.» |

### 1.1.2 US-2 · 90 Tage Trainingsdaten im Dashboard
**Als** Power-User mit Kraft- und Ausdauerdaten **möchte ich** meine letzten 90 Tage Hevy-Trainings in einem einzigen Dashboard sehen, **damit** ich meine Gesamtbelastung und Progression auf einen Blick beurteilen kann.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Gültiger API-Key ist hinterlegt | User öffnet das Dashboard | Angezeigt werden: Tabelle mit Sessions pro Datum, Gesamtvolumen in kg (Gewicht × Reps × Sets), Ø Trainingstage/Woche, Diagramm zur Muskelbelastungsverteilung — Zeitraum: letzte 90 Tage |
| AC2 | Hevy API ist nicht erreichbar | Dashboard wird geladen | Gecachte Daten werden angezeigt mit sichtbarem Hinweis auf letzten Sync-Zeitstempel |
| AC3 | User ist neu in Hevy oder hat >90 Tage nicht trainiert | User öffnet das Dashboard | Text: «No training data for the last 90 days» |

### 1.1.3 US-3 · AI-Analyse auf Knopfdruck
**Als** Krafttraining-Einsteigerin **möchte ich** auf Knopfdruck eine AI-Analyse meiner Trainingslast abrufen, **damit** ich ohne Selbstinterpretation weiss, ob ich diese Woche steigern kann.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Mindestens 2 Wochen Trainingsdaten vorhanden | User tippt auf «Analysieren» | Spinner erscheint sofort; Empfehlung wird angezeigt sobald Claude antwortet; nach 30 s ohne Antwort erscheint Cancel-Button «Analysis is taking longer than expected — tap to cancel» |
| AC2 | Analyse ist abgeschlossen | User liest die Empfehlung | Empfehlung enthält eine konkrete Handlung («Erhöhe Kniebeuge-Gewicht um 2.5 kg»), nicht nur allgemeine Aussagen |
| AC3 | Analyse wird ausgeführt | LLM-Prompt wird zusammengestellt | Prompt enthält ausschliesslich Daten des eingeloggten Users — keine Benchmarks oder Normwerte fremder Nutzer |
| AC4 | User hat in 4 Wochen Beine, Oberkörper und Rücken trainiert | Empfehlung wird angezeigt | Geht auf mindestens 2 verschiedene Muskelgruppen ein |
| AC5 | User hat hohes Volumen aber konstant niedrige Gewichte | Analyse läuft | AI empfiehlt explizit Intensitätssteigerung (Gewicht), nicht pauschal «mehr trainieren» |
| AC6 | User hat in den letzten 7 Tagen an ≥6 Tagen trainiert | Analyse wird ausgeführt | Empfehlung enthält expliziten Hinweis auf Recovery-Bedarf — keine Steigerungsempfehlung ohne diesen Hinweis |
| AC7 | Analyse ist abgeschlossen | Empfehlung wird angezeigt | Nennt mindestens eine konkrete Übung mit konkretem Wert («Erhöhe Bankdrücken von 60 kg auf 62.5 kg») |
| AC8 | User trainiert Brust 3×/Woche, Beine nur 1×/Woche | Empfehlung wird generiert | AI weist auf Muskelgruppen-Dysbalance hin |
| ~~AC9~~ | — | — | *Entfernt:* «Helpful» / «Not helpful»-Buttons. Die Bewertung blieb nur lokal, wurde nicht ausgewertet und floss in keinen Prompt ein — kein Nutzen für User oder Team. Nummer bleibt frei, damit AC10/AC11 stabil referenzierbar bleiben. |
| AC10 | Eine Analyse wurde abgeschlossen | User öffnet die App später erneut | Die neueste Empfehlung wird wieder angezeigt, mit Zeitstempel oben links auf der Karte |
| AC11 | Mehrere Analysen wurden durchgeführt | User öffnet den History-Screen | Alle gespeicherten Analysen erscheinen chronologisch absteigend (max. 20); jede lässt sich per Swipe einzeln löschen |

> **Hinweis:** US-3 ist als Epic geführt und vor Sprint-Planung in Child Stories aufzuteilen (Prompt-Design, UI, Error-Handling, Disclaimer).

### 1.1.4 US-4 · Onboarding in 3 Schritten
**Als** Nutzerin ohne technischen Hintergrund **möchte ich** den Hevy-Key und optional bis zu drei LLM-Provider-Keys (Claude, Gemini, Mistral) in maximal 3 verständlichen Schritten einrichten, **damit** ich die App nutzen kann, ohne eine Dokumentation lesen zu müssen.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | User öffnet FitBuddy zum ersten Mal | Onboarding-Flow startet | Jeder Schritt erklärt mit Screenshot, wo in Hevy der API-Key zu finden ist |
| AC2 | Hevy API-Key wurde eingegeben und gespeichert | User tippt auf «Next» | Bis zu drei LLM-Provider-Keys (Claude, Gemini, Mistral) können über einen Provider-Picker in Prioritätsreihenfolge hinterlegt oder vorerst übersprungen werden. Die Reihenfolge bestimmt, welcher Provider bei der Analyse zuerst verwendet wird (Fallback bei Fehler oder fehlendem Guthaben); sie wird lokal persistiert (nur die Reihenfolge, nie Key-Material) und überlebt einen Kaltstart. Alle Keys landen ausschliesslich im iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`); keine Live-Validierung — ein ungültiger Key fällt erst beim ersten Analyse-Call auf. Die Fallback-Kette ist mit #79 umgesetzt (ADR-007): Der Analyse-Call arbeitet die Prioritätsreihenfolge ab und wechselt bei jedem Fehler zum nächsten hinterlegten Anbieter. Ein Setup ohne Claude-Key ist damit voll funktionsfähig |
| AC3 | User gibt ungültigen Key ein | User tippt auf «Verbinden» | Fehlermeldung erscheint mit direktem Link zur Hevy API-Key-Seite |
| AC4 | Onboarding-Flow startet | Consent-Screen wird angezeigt | User sieht und bestätigt explizit: (1) Trainingsdaten (Gesundheitsdaten nach nDSG Art. 5 lit. c) werden für die AI-Analyse an die vom User verbundenen LLM-Provider übertragen — ausschliesslich an jene, für die ein Key hinterlegt ist: Anthropic/Claude (Vertragspartner des Users: Anthropic Ireland, Limited, irisches Recht; technische Verarbeitung in den USA durch Anthropic PBC; Rechtsgrundlage: Anthropic DPA des Users inkl. SCCs + Swiss Addendum, automatisch gültig ab Account-Erstellung), Google/Gemini (Verarbeitung in den USA) und/oder Mistral AI (Verarbeitung in der EU) — die USA bietet kein dem Schweizer Recht gleichwertiges Datenschutzniveau; Rechtsgrundlage ist jeweils der API-Vertrag des eigenen Provider-Accounts (→ ADR-007). (2) FitBuddy ist kein medizinisches Produkt — der User trägt selbst die Verantwortung für umgesetzte Empfehlungen. (3) Link zur Datenschutzerklärung sichtbar. Ohne Bestätigung kein Zugang zur App. |
| AC5 | User hat Consent gegeben | Consent wird gespeichert | Datum und Consent-Version werden lokal im Keychain gespeichert — kein erneutes Anzeigen bei App-Updates, sofern Consent-Version identisch |

---

## 1.2 Should Have — Wichtig, PoC funktioniert auch ohne

### 1.2.1 US-5 · Zweite Datenquelle verbinden
**Als** Nutzer **möchte ich** einen zweiten Trainings-Account verbinden (z. B. Strava), **damit** FitBuddy auch meine Ausdauerdaten abruft.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Nutzer tippt auf «Quelle hinzufügen» | Er wählt Quelle und schliesst OAuth-Flow ab | Aktivitäten der letzten 90 Tage erscheinen normalisiert im Dashboard neben bestehenden Daten, die Quelle ist pro Session erkennbar |
| AC2 | Token einer Quelle ist abgelaufen | Dashboard lädt | Hinweis erscheint («Strava-Verbindung erneuern») mit direktem Link zum Re-Auth-Flow |
| AC3 | Nutzer hat noch keine Strava-Zugangsdaten hinterlegt | Er öffnet «Quelle hinzufügen» | Screen zur Eingabe von Client ID und Client Secret erscheint mit Anleitung zur eigenen Strava-API-App; beide Werte landen im Keychain |
| AC4 | Access-Token ist abgelaufen, Refresh-Token ist gültig | Sync läuft | Token wird transparent erneuert, der Sync gelingt ohne Nutzerinteraktion |

> **Hinweis:** Der Strava-Connector ist im PoC (v0) vollständig umgesetzt: OAuth-Flow im BYO-App-Modell nach ADR-010 (Zugangsdaten der eigenen Strava-API-App des Nutzers, kein Backend), transparenter Token-Refresh, quellenbezogener Cache und Fan-out-Sync über die `ConnectorRegistry`. Strava-Sessions erscheinen im Dashboard (AC1) und lösen den Erneuerungshinweis aus (AC2).
>
> Als dritte Quelle ist **Polar AccessLink** nach demselben BYO-App-Modell umgesetzt (ADR-011): eigene AccessLink-App des Nutzers, Verbindung über Settings, quellenbezogener Cache und Sync. AC1–AC3 gelten für Polar sinngemäss. AC4 entfällt, weil AccessLink v3 ein ca. 1 Jahr gültiges Access-Token ohne Refresh-Token ausgibt; nach Ablauf verbindet der Nutzer neu. Polar liefert nur Trainings, die nach dem Verbinden zu Polar Flow hochgeladen wurden.
>
> Strava- und Polar-Sessions fliessen nicht in Übungsliste und Progressionskurve ein — beide bleiben bewusst das Kraftbild (siehe Kapitel 4). In den Analyse-Prompt fliessen sie seit US-15 ein.

> **Zum Zeitfenster in AC1:** Die ursprünglichen «30 Tage» sind auf die 90 Tage des bestehenden Analyse- und Cache-Fensters (`TrainingWindow`) vereinheitlicht — zwei Fenster würden zwei Cache-Invalidierungsregeln bedeuten. Gleiche Korrektur wie bei der Doku-Synchronisation des Analysezeitraums.

### 1.2.2 US-6 · Analyse-Kontext transparent machen
**Als** Nutzer **möchte ich** sehen, auf welcher Datenbasis die AI-Empfehlung generiert wurde, **damit** ich die Empfehlung einordnen und ihr vertrauen oder sie hinterfragen kann.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | AI-Analyse wurde abgeschlossen | Empfehlung wird angezeigt | Kompakte Zusammenfassung: welche Quellen einbezogen, welcher Zeitraum, wie viele Trainings («Basierend auf 12 Hevy-Trainings der letzten 4 Wochen»). Der genannte Zeitraum ist der tatsächlich analysierte: standardmässig 4 Wochen, bei leerem Fenster die aufgeweitete Stufe (8 bzw. 13 Wochen). |
| AC2 | Weniger als 5 Trainings lagen im Analysezeitraum | Empfehlung wird angezeigt | Kontext-Hinweis enthält explizite Warnung, dass Datenbasis dünn ist |

### 1.2.3 US-7 · Übungssuche & Filter 
**Als** datengetriebener Nutzer **möchte ich** Übungen in meiner Trainingshistorie suchen und nach Muskelgruppe filtern, **damit** ich bei 50+ Übungen schnell die richtige für die Progressionskurve finde.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | User öffnet die Übungsübersicht mit ≥10 Einträgen | User tippt in das Suchfeld | Liste filtert in Echtzeit (case-insensitive). Keine Ergebnisse → Hinweis «Keine Übungen gefunden». |
| AC2 | User öffnet den Muskelgruppen-Filter | User wählt «Beine» | Nur Übungen, die Hevy der Kategorie Beine zuordnet, werden angezeigt. Mehrfachauswahl möglich. |

### 1.2.4 US-13 · Trainingsprofil für gezieltere AI-Empfehlungen
**Als** Nutzer **möchte ich** beim Onboarding mein Trainingsziel und meine Erfahrung angeben, **damit** die AI-Analyse Empfehlungen gibt, die zu dem passen, worauf ich hintrainiere, statt zu einem Durchschnittsnutzer.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Onboarding Schritt 1–3 abgeschlossen | Schritt 4 erscheint | Zwei Fragen: Ziel (Muskelaufbau / Kraft / Fettabbau / Ausdauer verbessern / Fitness halten) und Krafttrainings-Erfahrung (<1 Jahr / 1–3 Jahre / >3 Jahre) |
| AC2 | User will die Angaben nicht machen | «Skip for now» wird getippt | Onboarding ist abgeschlossen, die App funktioniert unverändert, der Schritt erscheint nicht erneut |
| AC3 | Ein Profil ist gespeichert | AI-Analyse wird gestartet | Ziel und Erfahrung stehen als «Profile»-Abschnitt im User-Prompt. Der Abschnitt hält fest, dass nur Kraftsessions vorliegen. Ohne Profil entfällt er ersatzlos. |
| AC4 | Ein Profil ist gespeichert | Analyse-Screen zeigt die Datenbasis (US-6) | Ziel und Erfahrung sind dort mit aufgeführt |
| AC5 | Profil wurde gesetzt oder übersprungen | Settings werden geöffnet | Bereich «Training profile» erlaubt Ändern und Entfernen |

> **Fünf Ziele, darunter Ausdauer:** Strava und Polar werden in den Settings verbunden, nicht im Onboarding — Schritt 4 weiss also nicht, ob ein Kraft- oder ein Ausdauersportler davorsitzt, und die Frage muss quellenneutral sein. Ohne «Ausdauer verbessern» wählt eine Läuferin «Fitness halten» und bekommt einen Kraftblock empfohlen. Jetzt ist es ein Enum-Fall, später Migration plus Prompt- und Teständerungen. Dasselbe Ziel kann später den Standard für die Profil-Auswahl in US-15 AC1 setzen, statt dort ein zweites Mal zu fragen.
>
> **Erfahrung ist domänenspezifisch:** Gefragt wird nach **Krafttrainings**-Erfahrung, im UI und im Prompt-Abschnitt so benannt. Fünf Jahre Laufen und sechs Monate Krafttraining sind für die Empfehlung zwei verschiedene Werte, und solange nur Kraftsessions analysiert werden, ist die engere Frage die ehrlichere. Mit US-15 (quellenübergreifende Analyse) wäre sie pro Domäne zu stellen oder ausdrücklich als allgemeine Trainingserfahrung zu benennen.
>
> **Das Profil darf keinen Kontext erfinden lassen:** `AnalysisPromptBuilder` filtert heute alle Strava-Sessions aus dem Prompt. Wer dreimal läuft und einmal Kraft macht, bekommt sonst eine Analyse dieser einen Session unter einem Ziel, das nach Ausdauerkontext ruft. Der «Profile»-Abschnitt hält deshalb fest, dass die Datenbasis nur Kraftsessions umfasst — bis US-15 das auflöst.
>
> **Bewusst minimal:** nur Ziel und Erfahrungslevel. Equipment, Wunschfrequenz und Verletzungen sind ausgeklammert — Verletzungsdaten sind Gesundheitsdaten nach Art. 5 lit. c nDSG und zögen Consent-Text und Risikonotiz nach sich. Die Erfahrung wird in Jahren erhoben statt als Selbsteinschätzung, weil Jahre objektiv sind. Das Profil geht in den User-Prompt, nicht in den System-Prompt: Es ist ein Faktum über diese Person, kein Auftrag an das Modell — der System-Prompt bleibt für alle Nutzer identisch, was die Regel aus US-3 AC3 prüfbar hält.

### 1.2.5 US-14 · AI-Empfehlung als strukturierte Karten
**Als** Krafttraining-Einsteigerin **möchte ich** die AI-Empfehlung als konkrete Karten sehen (Übung, Wert von → nach, Begründung; Recovery mit Kennzahlen; Dysbalance mit Balken), **damit** ich sie ohne Lesen von Fliesstext direkt umsetzen kann.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Analyse abgeschlossen | Ergebnis wird angezeigt | Oben eine Headline mit Verdikt, darunter die Kontextzeile aus US-6, ein Kurzfazit (1–3 Sätze), dann 0–4 Karten, dann «Show full analysis» mit der ausführlichen Analyse (aufgeklappt, wenn keine umsetzbare Karte vorliegt), dann der Disclaimer |
| AC2 | Modell empfiehlt eine Steigerung | Karte wird angezeigt | Karte nennt Übung, Muskelgruppe, Ausgangswert (durchgestrichen), Zielwert, Delta und eine Begründung in einem Satz |
| AC3 | Modell nennt eine Übung oder einen Ausgangswert | Karte wird gebaut | Übung kommt im Analysefenster vor und der Ausgangswert entspricht dem letzten Arbeitsgewicht im Cache; sonst wird die Karte verworfen und die Begründung als Prosa gezeigt |
| AC4 | User hat an ≥6 der letzten 7 Tage trainiert (US-3 AC6) | Ergebnis wird angezeigt | Recovery-Karte mit Kennzahlen aus der App (Sessions/7 Tage, Ø RPE falls vorhanden, empfohlene Pause) — keine Steigerungs-Karte ohne diesen Hinweis |
| AC5 | Modell antwortet nicht schema-konform oder ein Provider kann kein JSON-Schema | Ergebnis wird verarbeitet | Fallback auf die heutige Prosa-Darstellung, kein Fehler für den User |
| AC6 | Frühere Analysen (Prosa) sind gespeichert | User öffnet die History | Alte Einträge bleiben lesbar, neue Einträge zeigen Karten |
| AC7 | Prompt wird gebaut | LLM-Aufruf | Prompt enthält pro relevanter Übung das letzte Arbeitsgewicht, Wiederholungen, RPE und den 1RM-Trend aus dem Cache — nur eigene Daten (US-3 AC3) |

> **Hinweis:** Entspricht den Design-Screens 3.4 «Result · progression», 3.4b «Result · thin data», 3.5 «Result · recovery» und 3.7b «Saved analysis · detail» in `design/fb-screens.jsx`. Die Karten brauchen einen strukturierten Output (JSON-Schema bei Claude, Gemini und Mistral) und Übungsdaten im Prompt. Nur Kraftdaten (Hevy) — die Ausdauer-Karten folgen mit US-15 «Quellenübergreifende AI-Analyse» (#171). Umsetzung und Tasks: Issue #170.
>
> **Kurzfazit statt Füllkarten:** Bei wenig Daten stützt nichts eine Karte. Das Modell liefert dann keine Karten statt erfundener Platzhalter; das Kurzfazit und die aufgeklappte ausführliche Analyse tragen die Antwort. Liegt eine umsetzbare Karte (Steigerung, Recovery, Dysbalance) vor, stehen die Karten vorne und die ausführliche Analyse ist zugeklappt. Qualitative Empfehlungen, wie sie mit Strava und Polar (US-15) häufig sind, passen so in dieselbe Darstellung.
>
> **Nummerierung:** US-13 ist an #189 «Trainingsprofil für gezieltere AI-Empfehlungen» vergeben (PR #193), deshalb US-14.

### 1.2.6 US-15 · Quellenübergreifende AI-Analyse
**Als** Power-User mit Hevy, Strava und Polar **möchte ich** eine AI-Analyse über meine Gesamtbelastung, **damit** Kraft- und Ausdauertraining zusammen beurteilt werden und die Empfehlung meine echte Wochenlast berücksichtigt.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Im Analysefenster liegen Kraft- **und** Ausdauer-Sessions (massgeblich ist die gemappte Sportart nach ADR-012, nicht die Quelle) | User startet eine Analyse | User wählt ein Profil: «Strength», «Endurance» oder «Overall load»; Default ist «Overall load». Liegt nur eine Domäne im Fenster, entfällt die Auswahl und das Profil ist implizit «Strength» bzw. «Endurance» — zwei Quellen mit ausschliesslich Kraft ergeben keine Auswahl, ein reines Hevy-Konto mit Laufband-Sessions alle drei Optionen |
| AC2 | Profil «Overall load» | Prompt wird gebaut | Prompt enthält eine Kraft-Sektion, eine Ausdauer-Sektion (Wochen-km/-h, Puls, Tempo, Trend) und eine Sektion zur Wochenstruktur (Kraft- und Cardio-Tage, harte Tage in Folge) |
| AC3 | User hat an ≥6 der letzten 7 Tage trainiert, Kraft und Cardio zusammengezählt | Analyse läuft | Recovery-Hinweis erscheint (US-3 AC6 gilt über alle Quellen) |
| AC4 | Analyse abgeschlossen | Kontextzeile wird angezeigt | Zeile nennt die Zählung pro Quelle («14 Hevy · 9 Strava sessions · last 4 weeks»); die Warnung «Thin data» wird pro Domäne beurteilt |
| AC5 | Profil «Endurance» | Ergebnis wird angezeigt | Karten nutzen Ausdauer-Einheiten (km, min/km, bpm, h) und nennen keine Kilogramm-Werte |
| AC6 | Prompt wird gebaut | LLM-Aufruf | Prompt nennt keine Populationsvergleiche oder Normwerte; allgemeine Trainingsprinzipien (z. B. Intensitätsverteilung) sind erlaubt und im System-Prompt so benannt (US-3 AC3 bleibt erfüllt) |
| AC7 | Eine Quelle liefert eine Kennzahl nicht (z. B. kein RPE bei Strava) | Karte wird gebaut | Die Zelle entfällt; es wird kein Platzhalter «—» angezeigt |
| AC8 | 90 Tage Kraft + Cardio im Cache | Prompt wird gebaut | Prompt bleibt unter einem definierten Token-Budget (TD-1); Cardio wird bei Bedarf als Wochenaggregat statt Sessionliste übergeben |

> **Hinweis:** Hebt die Abgrenzung «Cross-Source-Analyse» aus Kapitel 4 auf. Bis dahin filtert `AnalysisPromptBuilder` alle Cardio-Sessions aus dem Prompt, die Kontextzeile ist auf «Hevy» festgelegt, und der Strava-DTO speichert nur Distanz und Zeit (kein Puls, keine Höhenmeter, kein Tempo). Setzt US-14 «AI-Empfehlung als strukturierte Karten» (#170) voraus — die Ausdauer-Karten bauen auf deren Karten-Schema auf — sowie die Polar-Tasks als dritte Quelle. Umsetzung und Tasks: Issue #171.
>
> **Die Sportart entscheidet, nicht die Quelle:** Seit ADR-012 (`ActivityKind`) übersetzt jede Quelle ihr Sportart-Vokabular an genau einer Stelle in eine normalisierte Domäne. Ob die Profil-Auswahl erscheint, hängt deshalb an den Trainingsarten im Fenster, nicht an der Zahl der verbundenen Quellen: Zwei Quellen, die beide nur Kraft liefern, sind eine Domäne und bekommen keine Auswahl; ein reines Hevy-Konto, in dem Laufband-Sessions protokolliert werden, bekommt alle drei Optionen.
>
> **Ein Verdikt pro Screen:** «You're ready to progress» und «Recover this week» schliessen sich gegenseitig aus. Bei gemischtem Profil kann Kraft steigern und Ausdauer erholen — das gewählte Profil hält den Prompt klein, macht die Empfehlung eindeutig und lässt die Kraft-Kriterien aus US-3 im Profil «Strength» unverändert prüfbar. Das Trainingsziel aus US-13 kann den Standard für diese Auswahl setzen, statt ein zweites Mal zu fragen.
>
> **Nummerierung:** US-13 ist an #189 «Trainingsprofil für gezieltere AI-Empfehlungen» vergeben (PR #193) und US-14 an #170, deshalb US-15.



## 1.3 Could Have — Nice-to-have, wenn Sprint Luft hat

### 1.3.1 US-8 · Datenquelle-Status sichtbar
**Als** Nutzer **möchte ich** auf einen Blick sehen, welche Datenquellen verbunden und aktuell sind, **damit** ich weiss, ob die AI-Analyse auf vollständigen oder veralteten Daten basiert.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | User öffnet das Dashboard | Eine Datenquelle wurde seit >24 h nicht synchronisiert | Sichtbarer Indikator mit Zeitstempel des letzten erfolgreichen Syncs und Retry-Button |
| AC2 | Gespeicherter API-Key wurde in Quell-App widerrufen | FitBuddy macht Sync-Versuch | User wird aktiv benachrichtigt — kein stilles Weiterlaufen mit gecachten Daten |

### 1.3.2 US-9 · Progressionskurven pro Übung
**Als** datengetriebener Nutzer **möchte ich** Progressionskurven pro Übung über Zeit sehen, **damit** ich Plateaus früh erkenne und meinen Plan gezielt anpassen kann.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Übung hat ≥2 Sessions mit Gewicht+Reps in 12 Wochen | User öffnet Detailansicht | Liniendiagramm mit 1RM-Schätzwert pro Session (Epley: `weight × (1 + reps/30)`), X=Datum, Y=kg |
| AC2 | Übung hat in 3 aufeinanderfolgenden Sessions keinen höheren 1RM erreicht | Dashboard oder Detailansicht lädt | Übung wird visuell als «Plateau» markiert (gelbes Label) |
| AC3 | Übung hat <2 Sessions mit verwertbaren Daten in 12 Wochen | Detailansicht öffnet | Kein Diagramm — Hinweis: «Noch zu wenig Daten — mindestens 2 Sessions nötig» |

### 1.3.3 US-10 · Daten manuell neu laden / Pull-to-Refresh
**Als** Nutzer **möchte ich** die Trainingsdaten manuell neu laden können, **damit** ich nach einem kurzen API-Ausfall sofort aktuelle Daten sehe, ohne die App neu zu starten.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Dashboard zeigt gecachte Daten (API war down) | User zieht Liste nach unten | Neuer API-Call zu `GET /workouts` wird ausgelöst. Bei Erfolg: Daten aktualisiert, Sync-Zeitstempel erneuert. |
| AC2 | Pull-to-Refresh wurde ausgelöst | API gibt erneut einen Fehler zurück | Fehlermeldung erscheint, gecachte Daten bleiben sichtbar, Spinner verschwindet. |

### 1.3.4 US-17 · Steigerungsempfehlung passt zur Übung und zur Last
**Als** Nutzer **möchte ich** eine Steigerung vorgeschlagen bekommen, die zur Übung und zu meinem Trainingsstand passt, **damit** die Empfehlung weder unrealistisch noch trivial ist.

| # | Given | When | Then |
|---|---|---|---|
| AC1 | Eine Übung steht im Prompt | Prompt wird gebaut | Der Prompt nennt pro Übung eine **erlaubte Spanne** («Next: 62.5–65 kg»), nicht einen einzelnen Zielwert — berechnet aus dem Band in [ADR-013](adr/ADR-013-progressionsband-je-muskelgruppe.md), gerundet auf die Granularität der Übung (Langhantel 2.5 kg, sonst der kleinste geloggte Schritt) |
| AC2 | Das Modell schlägt einen Wert innerhalb der Spanne vor | Report wird validiert | Die Karte bleibt eine Progression; Übung, Muskelgruppe und Ausgangsgewicht kommen weiterhin aus dem Cache der App (US-14 AC3) |
| AC3 | Eine Übung stagniert und hat keinen passenden Gewichtsschritt (z. B. Kurzhantel-Sprung zu gross, einzige geloggte Hantel) | Karte wird gebaut | Die Empfehlung progressiert **Wiederholungen** statt Gewicht: eigene Kartenart «More reps» («12 reps → 14 reps at 10 kg»), geprüft gegen Arbeitsgewicht und Wiederholungen aus dem Cache, höchstens zwei Wiederholungen mehr |
| AC4 | Die Spanne wird festgelegt | Review | Herkunft und Begründung des Prozentbands sind in ADR-013 dokumentiert — inkl. der Aussage, worauf es **nicht** beruht (nicht Geräte-Granularität, nicht Normwerte, nicht Erfahrungsstufe) |
| AC5 | Eine Übung steht im Prompt | Spanne wird berechnet | Die Spanne richtet sich **nach der Muskelgruppe** (`MuscleGroup`): +10 % Obergrenze für Beine, Rücken, Brust; +5 % für Schultern, Arme, Rumpf und Unklassifiziertes. Die Trainingserfahrung aus US-13 ist **kein** Modifikator (ADR-013, Entscheidung 4). Ein Geräteschritt ist immer erlaubt, auch wo die Obergrenze darunter liegt |
| AC6 | Das Modell schlägt etwas oberhalb der Spanne vor — oder unterhalb eines Geräteschritts | Report wird validiert | Die Karte wird zur Notiz abgestuft; der Fall wird mit seinem Grund protokolliert (`aboveRange` bzw. `belowRange`), damit die Trefferquote über mehrere Läufe messbar ist (US-16) |
| AC7 | Der User hat das Zielrepertoire der Übung in den letzten zwei Einheiten **nicht** um mindestens 2 Wiederholungen überschritten (letzter Arbeitssatz, Ziel aus der Hevy-Routine) | Karte wird gebaut | Es wird **keine** Gewichtsprogression vorgeschlagen: die Spanne hängt an der 2-for-2-Bedingung. Der Prompt sagt es der Übungszeile an («progress reps, not weight»), der Validator stuft eine Gewichtsprogression trotzdem ab (`conditionNotMet`). Fehlt das Ziel (keine Routine, `rep_range` und `reps` leer), gilt die Bedingung als **nicht prüfbar** — nie als erfüllt (`conditionNotCheckable`) — und die Karte fällt auf Rep-Progression oder Notiz zurück |

> **Hinweis:** v1. Bis US-17 liess der Validator pro Übung genau **einen** Zielwert zu (Langhantel `minimumStepKg`, sonst der kleinste gelistete Schritt) — Geräte-Granularität als Trainingslehre. Die Spanne, ihre Staffelung nach Muskelgruppe und die 2-for-2-Bedingung sind in [ADR-013](adr/ADR-013-progressionsband-je-muskelgruppe.md) festgelegt; dort steht auch, dass nichts davon an FitBuddy-Nutzern validiert ist. Setzt US-14 (#170) und US-15 (#171) voraus, nutzt die Trainingserfahrung aus US-13 bewusst nicht. Grenzt an US-16 ab: dort geht es um die **Stabilität des Verdicts**, hier um die **Dosierung einer Steigerung**. Umsetzung und Tasks: Issue #225.
>
> **Datengrundlage der Bedingung:** Das Ziel ist die obere Kante des Wiederholungsbereichs der Hevy-Routine, gegen die das Workout geloggt wurde (`rep_range.end` → `rep_range.start` → `reps` → kein Ziel). Der `HevyConnector` liest `GET /v1/routines` beim Sync und **snapshottet** das Ziel pro Satz in den Cache (Schema V6: `Workout.routineID`, `.routineUpdatedAt`, `ExerciseSet.targetReps`) — Routinen sind veränderlich und unversioniert, ein Live-Join würde vergangene Sessions gegen einen Plan vergleichen, der damals nicht galt. «Kein Ziel» ist ein modellierter Zustand, kein Fehler.
>
> **Konsequenz für frei loggende User:** Ohne Routine gibt es kein Ziel, ohne Ziel keine Gewichtsprogression. Die App sagt das in der Übungszeile («No rep target on file») und bietet Rep-Progression an — das ist die bewusste Konsequenz aus ADR-013, nicht ein Defekt. Das Mock-Profil «plateau» (#235) zeigt alle Fälle in einem Fenster.


## 1.4 Won't Have — Bewusst ausgeschlossen für diesen PoC

### 1.4.1 US-11 · Wochenübersicht als Push-Notification 
Out of Scope — siehe Abschnitt 4.

### 1.4.2 US-12 · Trainingsvorschlag zurück in Hevy schreiben 
Out of Scope — siehe Abschnitt 4.



## 2. MoSCoW-Priorisierung mit Begründungen

| ID | Titel | MoSCoW | Begründung |
|---|---|---|---|
| US-1 | API-Key sicher speichern | **Must** | Ohne Keychain-Speicherung kein einziger API-Call. Sicherheitskritisch, nicht-trivial — gehört in Sprint 1. |
| US-2 | 90 Tage Trainingsdaten im Dashboard | **Must** | Datenbasis für AI-Analyse (US-3) und alle Visualisierungen. 90 Tage statt 30, da Progression erst über 8–12 Wochen messbar ist. |
| US-3 | AI-Analyse auf Knopfdruck | **Must** | Die AI-Empfehlung *ist* das Produkt — ohne sie wird FitBuddy zum reinen Hevy-Viewer. |
| US-4 | Onboarding in 3 Schritten | **Must** | Zwei API-Keys (Hevy + Claude) sind für nicht-technische User echtes Produktrisiko (R4). Onboarding muss ohne Doku machbar sein. |
| US-5 | Zweite Datenquelle verbinden | **Should** | Differenzierung durch zweite Quelle ist Produktargument. Strava- und Polar-Connector (OAuth im BYO-App-Modell, Normalisierung, quellenbezogener Cache) sind im PoC umgesetzt; die kombinierte Analyse über alle Quellen liefert US-15 nach. |
| US-6 | Analyse-Kontext transparent machen | **Should** | AC1 könnte als AC in US-3 wandern; eigenständige Story v. a. wegen AC2 (Warnung bei dünner Datenbasis). |
| US-7 | Übungssuche & Filter | **Should** | Wird notwendig, sobald User-Historie >20 Übungen erreicht. Für PoC-Demos mit wenigen Sessions verzichtbar. |
| US-8 | Datenquelle-Status sichtbar | **Could** | Bei nur einer Quelle (Hevy) trägt der Sync-Zeitstempel aus US-2 AC2 den Grossteil. AC1 und AC2 sind in v0 dennoch umgesetzt (Stale-Indikator ab >24 h mit Retry, aktive Benachrichtigung bei widerrufenem Key), weil der blosse Zeitstempel veraltete Daten nicht als solche kenntlich macht. Vollwertig — mehrere Quellen nebeneinander — relevant ab v1. |
| US-13 | Trainingsprofil für gezieltere AI-Empfehlungen | **Should** | Hebt die Qualität von US-3 spürbar, ohne dass irgendetwas davon abhängt: Ohne Profil verhält sich die App exakt wie bisher. Zwei Felder, überspringbar — der Aufwand steht in keinem Verhältnis zum Gewinn an Treffsicherheit der Empfehlung. |
| US-14 | AI-Empfehlung als strukturierte Karten | **Should** | Macht die Empfehlung aus US-3 direkt umsetzbar, statt sie als Fliesstext lesen zu lassen. Die App prüft Übung und Ausgangswert jeder Karte gegen den Cache; antwortet ein Modell nicht schema-konform, bleibt die Prosa-Darstellung. Der PoC funktioniert auch ohne. |
| US-15 | Quellenübergreifende AI-Analyse | **Should** | Löst das Versprechen aus US-5 ein: Kraft und Ausdauer werden zusammen beurteilt statt nebeneinander angezeigt. Der PoC funktioniert auch ohne — ohne die Story bleibt die Analyse auf Kraftdaten beschränkt, wie sie es heute ist, und Cardio-Sessions erscheinen weiterhin nur im Dashboard. |
| US-9 | Progressionskurven pro Übung | **Could** | US-3 deckt den Hauptnutzen ab. Epley-Formel + Plateau-Detection sind nicht-trivial. |
| US-10 | Daten manuell neu laden | **Could** | iOS-Pattern, das User erwarten — kein Showstopper. 1–2 Tage Aufwand, ergänzt US-2 AC2. |
| US-17 | Steigerungsempfehlung passt zur Übung und zur Last | **Could** | Verbessert die Dosierung der Progression-Karte aus US-14, ohne dass etwas davon abhängt: Spanne statt Einzelwert (ADR-013), 2-for-2 als Vorbedingung, Rep-Progression als eigene Karte. Braucht Hevy-Routinen mit Zielwerten — wer frei loggt, bekommt Rep- statt Gewichtsprogression. v1-Material, im v0-Code umgesetzt, weil der Live-Test zu US-15 zeigte, dass der Validator sinnvolle Vorschläge verwarf. |
| US-11 | Wochenübersicht als Push-Notification | **Won't** | iOS-Permission-Flow + Background-Scheduling + LLM-Call-Fallback ist eigenes Sub-System. Relevant ab v1.2. |
| US-12 | Trainingsvorschlag zurück in Hevy schreiben | **Won't** | Setzt Hevy PRO voraus, erfordert UX-Klärung (Write-Target, Undo). Risiko: Empfehlung falsch übernommen. Relevant ab v1.2. |


## 3. Nicht-funktionale Anforderungen

| Bereich | Anforderung |
|---|---|
| Performance | Spinner erscheint sofort nach Tap auf «Analysieren»; Cancel-Button nach 30s ohne Antwort (US-3 AC1) |
| Performance | Dashboard-Load innerhalb von 3 Sekunden nach Kaltstart (US-1 AC2) |
| Sicherheit | API-Keys ausschliesslich im iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) |
| Privacy | Keine User-Daten auf externen Servern — ausser den direkten API-Calls vom Gerät an die verbundenen Quellen (Hevy, Strava, Polar) und an den gewählten LLM-Anbieter (Claude, Gemini, Mistral) |
| Sprache | English-only (alle UI-Strings, Fehlermeldungen, System-Prompt) — kein i18n-Framework |
| Datenschutz | Nur Daten des eingeloggten Users im LLM-Prompt (keine Benchmarks fremder Nutzer) |
| Datenschutz | Consent (Datenübertragung an den gewählten LLM-Anbieter — Anthropic, Google oder Mistral — und an die verbundenen Quellen + Eigenverantwortung) wird beim Onboarding eingeholt und lokal gespeichert (US-4 AC4/AC5) |
| Datenschutz (nDSG) | Trainingsdaten sind Gesundheitsdaten nach Art. 5 lit. c nDSG — explizite Einwilligung ist Pflicht. Die Übertragung stützt sich pro Anbieter auf die API-Bedingungen des Enduser-Accounts: Anthropic (USA; Commercial Terms inkl. DPA mit SCCs + Swiss Addendum, automatisch gültig ab Account-Erstellung), Google (USA) und Mistral AI (EU). Das FitBuddy-Team schliesst keinen eigenen DPA ab — im BYO-Key-Modell ist der Enduser «Customer» des jeweiligen Anbieters (ADR-007). |
| Datenschutz (nDSG) | Die App enthält einen statischen Datenschutzerklärung-Screen (erreichbar aus Onboarding + Einstellungen) mit: Verantwortlichem, bearbeiteten Daten, Zweck, Drittempfängern (Quellen: Hevy, Strava, Polar — LLM-Anbieter: Anthropic, Google, Mistral), Drittland USA, Rechten der betroffenen Person (Auskunft, Löschung). |
| Datenschutz (nDSG) | User kann jederzeit alle lokal gespeicherten Daten löschen (Keychain-Einträge + Cache) über «Daten löschen / Account zurücksetzen» in den Einstellungen — App kehrt in den Onboarding-Zustand zurück. |
| LLM-Kosten | Analyse jederzeit auf Knopfdruck; Button disabled während laufendem Call, danach kein Cooldown. Hartes Kostenlimit ist das Spending Limit im Account des Users beim gewählten Anbieter (BYO-Key, ADR-004) |
| LLM-Kosten | Analyse-Button disabled während laufendem Call — kein Doppel-Submit möglich |


## 4. Out of Scope

Bewusst ausgeschlossen für den PoC. Dokumentiert, damit später kein Scope-Creep entsteht.

| Bereich | Out of Scope weil |
|---|---|
| **US-11** Push-Notifications (Wochenübersicht) | iOS-Permission-Flow, Background-Scheduling, LLM-Fallback bei Offline-Zustand — eigenes Sub-System. Frühestens v1.2 sinnvoll, wenn Retention-Daten zeigen, dass User die App nicht regelmässig öffnen. |
| **US-12** Write-back nach Hevy | Erfordert Hevy PRO, ungeklärtes Write-Target (Routine vs. zukünftiges Workout) und Undo-UX. Falsch übernommene AI-Empfehlung ist ein realer Schaden für den User (R3). |
| **Cardio in Übungsliste und Progressionskurve** | Die quellenübergreifende Auswertung selbst ist **nicht** mehr out of scope: Mit US-15 fliessen Ausdauer-Sessions in Analyse-Prompt, Kontextzeile und Karten ein (ADR-012, Schema V5). Ausserhalb des Scope bleibt nur, sie auch in Übungsliste (US-7) und Progressionskurve (US-9) zu führen — beide bleiben bewusst das Kraftbild, weil ein Lauf weder Gewicht noch Wiederholungen hat und dort nur eine leere Kurve beitragen könnte. |
| **Apple Health Integration** | Siehe Risiko 1 — Vorschlag: OUT für PoC. |
| **i18n / Lokalisierung** | English-only ist Definition of Done — kein Framework, keine zweite Sprache. Spart Übersetzungs-Roundtrips beim Prompt-Tuning. |
| **App Store Release** | Distribution ausschliesslich via TestFlight / Sideload. Spart App-Store-Review, Marketing-Assets und Compliance-Roundtrips. |
| **Backend-Proxy für die LLM-APIs** | ADR-004: Key direkt im Keychain, Call direkt vom Gerät. Vereinfacht PoC, ist aber vor v1.0 zwingend zu revisiten (Key-Exposition bei Gerätekompromittierung). |
| **AWS Bedrock EU (eu-central-1)** | ADR-005: PoC nutzt Claude API USA über BYO-Key-Modell (User-DPA + Consent). Migration auf Bedrock Frankfurt ist v1.0-Pflicht, nicht PoC-Inhalt. |
| **Eigenes Tracking / Analytics** | Kein Mixpanel, kein Amplitude, kein Crashlytics im PoC. Würde Datenschutz-Erklärung verkomplizieren und Consent verändern. |
| **Plateau-Detection als eigenständiges Feature** | Teil von US-9 (Could), kein eigenes Item. Wenn US-9 nicht in den Sprint passt, fällt es ersatzlos weg. |


## 5. Quality Attributes — Top 3 Architektur-Treiber

*Analysiert aus den Requirements und Projektdokumentation. Direkter Input für ADR-Entscheide und Sprint-Planung.*

---

### QA-1 — Security / Privacy *(kritischster Treiber)*

**Warum für FitBuddy besonders wichtig:**

Das Kernversprechen der App *ist* Security: «API-Keys verbleiben im iOS Keychain — alle API-Calls laufen direkt vom Gerät.» Trainingsdaten sind Gesundheitsdaten nach nDSG Art. 5 lit. c — rechtlich eine der höchstgeschützten Datenkategorien. Jeder Analyse-Call überträgt diese Daten an den gewählten LLM-Anbieter: Anthropic (Vertragspartner: Anthropic Ireland, Limited; Verarbeitung in den USA durch Anthropic PBC) oder Google — beide ohne Angemessenheitsbeschluss der Schweiz — oder Mistral AI in der EU. Die Rechtsgrundlage ist jeweils der API-Vertrag des eigenen Accounts, bei Anthropic der DPA des Endusers inkl. SCCs + Swiss Addendum, automatisch gültig mit Erstellung des Accounts (ADR-005, ADR-007). Wenn ein Key auf dem Gerät kompromittiert wird, gibt es keinen server-seitigen Kill-Switch: der User muss ihn in der Konsole des Anbieters widerrufen.

**Konkrete architektonische Massnahmen:**

| Massnahme | Begründung |
|---|---|
| `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (US-1 AC1) | Verhindert iCloud-Sync des Keys und Zugriff bei gesperrtem Gerät — falsches Attribut = Key landet in iCloud-Backup |
| Certificate Pinning für alle sieben Hosts (Quellen + LLM-Anbieter) | Einziger verbleibender Angriffsvektor bei kompromittiertem Netzwerk. **Status: umgesetzt (#153)** — Root-CA-Pins über `NSPinnedDomains` in der `Info.plist`, Details in [CERTIFICATE-PINNING.md](CERTIFICATE-PINNING.md) |
| Consent-Text US-4 AC4 korrekt formulieren **vor erstem TestFlight-Build** | Anthropic Ireland Ltd als Vertragspartner, USA als Drittland, DPA des Users als Rechtsgrundlage — inhaltlich falscher Consent verletzt Art. 19 nDSG |
| Consent mit Version + Timestamp im Keychain (US-4 AC5) | Versionierter Consent ist Pflicht: bei Änderung der Datenverarbeitung muss erneut eingeholt werden |
| Kein Logging von Key-Material | Eine einzige Log-Zeile mit API-Key in einem Crash-Report reicht für eine Kompromittierung |

**Wenn ignoriert:**

Rechtliche Haftung nach nDSG, Apple-Review-Ablehnung wegen fehlendem Privacy-Manifest, öffentlicher Trust-Verlust. Konkret: falsches Keychain-Attribut = Keys landen in iCloud-Backup; kein Certificate Pinning = MITM-Angriff im WLAN liest Keys mit; fehlender oder inhaltlich falscher Consent = die Übertragung der Gesundheitsdaten hat keine Rechtsgrundlage (im BYO-Key-Modell ist der Vertrag des Users die Grundlage, nicht ein Team-DPA — ADR-005).

---

### QA-2 — Reliability *(Kernvoraussetzung für Nutzbarkeit)*

**Warum für FitBuddy besonders wichtig:**

Alle externen Abhängigkeiten sind instabil — dokumentiert: Hevy hat «no guarantees — we might abandon this entirely» geschrieben (R1), Strava und Polar hängen zusätzlich an OAuth-Tokens, die ablaufen können. Ein LLM-Call kann 10–30 Sekunden dauern, Rate-Limit-Fehler werfen oder bei schlechtem Netz ausfallen — dagegen steht die Fallback-Kette über bis zu drei Anbieter (ADR-007). Das Dashboard ist der einzige Einstiegspunkt in den gesamten Produktwert — ein leerer Screen beim Öffnen führt zur Deinstallation. US-3 (AI-Analyse) hängt vollständig von gecachten Dashboard-Daten ab: keine Reliability im Cache = keine AI-Analyse.

**Konkrete architektonische Massnahmen:**

| Massnahme | Begründung |
|---|---|
| SwiftData für den Activity-Cache (nicht UserDefaults) — ADR-001 | Relationales Modell für `Workout → Exercise → ExerciseSet`; versionierte Schema-Migration (inzwischen bis V5, inkl. Strava- und Polar-Daten); Queries ohne alles in-memory zu laden |
| `lastSyncTimestamp` persistent in UserDefaults | Überlebt App-Kills; immer als Banner im Dashboard sichtbar (US-2 AC2) |
| HTTP 401 → harter Logout (US-1 AC3) | Kein stilles Weiterlaufen mit gecachten Daten die der User für aktuell hält → falsche AI-Empfehlung auf Basis veralteter Daten |
| LLM-Timeout 30 s + Cancel-Button (US-3 AC1) | Ohne Cancel-Button: User sieht hängenden Spinner, kill-swipet die App, glaubt sie ist kaputt |
| Doppeltipp-Schutz: Button disabled, solange ein Call läuft — **keine Sperre danach** | Verhindert versehentliche Mehrfach-Calls, ohne den User nach einer Analyse warten zu lassen. Die frühere 60-s-Sperre ist entfernt. Bewusst kein Kostenlimit — das ist das Spending Limit im Account des Users |

**Wenn ignoriert:**

Hevy hat einen Ausfall → leerer Screen (Cache war in-memory, App wurde über Nacht gecleaned) → Deinstallation. Claude-Call läuft > 30 s → kein Cancel-Button → App muss neu gestartet werden. Stiller 401-Fehler → User erhält AI-Empfehlung auf Basis veralteter Daten.

---

### QA-3 — Maintainability *(Voraussetzung für geplante Roadmap)*

**Warum für FitBuddy besonders wichtig:**

Zwei dokumentierte Roadmap-Items blockieren ohne saubere Abstraktion: eine zweite Datenquelle (US-5, als Should gelistet) und die Bedrock-Migration (v1.0, ADR-005: «obligatorisch vor kommerziellem Launch»). *Rückblick: Die Abstraktion hat sich ausgezahlt — Strava und Polar sind über `FitnessConnector` noch im v0 dazugekommen, ohne dass Dashboard oder Prompt-Builder umgebaut werden mussten (ADR-010, ADR-011).* Wenn HevyConnector-Code in Dashboard-Logik und AI-Prompt-Builder verwächst, muss bei jedem neuen Connector alles angefasst werden. Der Entscheid muss vor Sprint 1 getroffen sein — «Im PoC wird nur das `FitnessConnector`-Interface verankert» bedeutet: die Architektur muss jetzt stimmen.

**Konkrete architektonische Massnahmen:**

| Massnahme | Begründung |
|---|---|
| `FitnessConnector`-Protocol **vor** HevyConnector implementieren (ADR-006) | Verhindert, dass Hevy-spezifische Typen in UI und AI Engine eindringen |
| `StravaConnector`-Stub im PoC committen (kompiliert, wirft `NotImplemented`) | Verhindert Protocol-Drift zwischen Sprint 1 und v1 — Interface bleibt stabil |
| AI Analysis Engine liest **nur** aus dem Activity-Cache, nie direkt vom Connector | Claude-Prompt-Builder bleibt unverändert wenn Strava dazukommt |
| Claude-API-Call in eigene `InferenceService`-Klasse kapseln | Bedrock-Migration = eine Klasse austauschen, nicht jeden Call im Codebase |
| ADRs im Code verlinkt | Neue Teammitglieder verstehen warum Entscheidungen so sind — verhindert «versehentliches Rückgängigmachen» |

**Wenn ignoriert:**

Strava-Integration in v1 erfordert Refactor von HevyConnector + Dashboard + AI Engine statt nur eines neuen Connectors. Bedrock-Migration (gesetzliche Pflicht für nDSG-Konformität vor v1.0) berührt jeden Claude-Call statt einer `InferenceService`-Klasse. Das Team schätzt 2 Tage — es werden 2 Wochen mit Regressionen.

---

### Zusammenfassung

| QA | Wenn ignoriert bricht | Risiko-Horizont |
|---|---|---|
| Security / Privacy | Rechtliche Haftung + App-Store-Ablehnung | Vor erstem TestFlight-Build |
| Reliability | App wirkt kaputt beim ersten Hevy-Ausfall | Sprint 2 (Dashboard) |
| Maintainability | Strava v1 und Bedrock v1.0 werden zu Refactors statt Features | Grundlage muss in Sprint 1 gelegt werden |

---

*Stand: 27.05.2026 · Quellen: `PROJECT.md`, `REQUIREMENTS.md` v5, `ARCHITECTURE.md`*
