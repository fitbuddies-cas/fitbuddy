# FitBuddy — Requirements Document
*Strukturierte Zusammenfassung für CAS ADAI 2026, Modul 3.
Konsolidiert aus `PROJECT.md`, `REQUIREMENTS.md` und `ARCHITECTURE.md`.*


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
| AC2 | Hevy API-Key wurde eingegeben und gespeichert | User tippt auf «Next» | Bis zu drei LLM-Provider-Keys (Claude, Gemini, Mistral) können über einen Provider-Picker in Prioritätsreihenfolge hinterlegt oder vorerst übersprungen werden. Die Reihenfolge bestimmt, welcher Provider bei der Analyse zuerst verwendet wird (Fallback bei Fehler oder fehlendem Guthaben); sie wird lokal persistiert (nur die Reihenfolge, nie Key-Material) und überlebt einen Kaltstart. Alle Keys landen ausschliesslich im iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`); keine Live-Validierung — ein ungültiger Key fällt erst beim ersten Analyse-Call auf. **v0-Einschränkung:** Der Analyse-Call bedient ausschliesslich den Claude-Endpoint; Gemini- und Mistral-Keys werden bereits gespeichert und in die Prioritätsreihenfolge aufgenommen, aber erst mit der Fallback-Kette (#79) tatsächlich aufgerufen. Schritt 3 weist explizit darauf hin, damit ein Setup ohne Claude-Key nicht als funktionsfähig missverstanden wird |
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
> Strava- und Polar-Sessions fliessen weder in die Übungsliste noch in die Progressionskurve oder den Analyse-Prompt ein — die quellenübergreifende Auswertung bleibt v1 (siehe Kapitel 4).

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
> **Bewusst minimal:** nur Ziel und Erfahrungslevel. Equipment, Wunschfrequenz und Verletzungen sind ausgeklammert — Verletzungsdaten sind Gesundheitsdaten nach Art. 5 lit. c revDSG und zögen Consent-Text und Risikonotiz nach sich. Die Erfahrung wird in Jahren erhoben statt als Selbsteinschätzung, weil Jahre objektiv sind. Das Profil geht in den User-Prompt, nicht in den System-Prompt: Es ist ein Faktum über diese Person, kein Auftrag an das Modell — der System-Prompt bleibt für alle Nutzer identisch, was die Regel aus US-3 AC3 prüfbar hält.



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
| US-5 | Zweite Datenquelle verbinden | **Should** | Differenzierung durch zweite Quelle ist Produktargument. Strava- und Polar-Connector (OAuth im BYO-App-Modell, Normalisierung, quellenbezogener Cache) sind im PoC umgesetzt; die kombinierte Analyse über alle Quellen bleibt v1. |
| US-6 | Analyse-Kontext transparent machen | **Should** | AC1 könnte als AC in US-3 wandern; eigenständige Story v. a. wegen AC2 (Warnung bei dünner Datenbasis). |
| US-7 | Übungssuche & Filter | **Should** | Wird notwendig, sobald User-Historie >20 Übungen erreicht. Für PoC-Demos mit wenigen Sessions verzichtbar. |
| US-8 | Datenquelle-Status sichtbar | **Could** | Bei nur einer Quelle (Hevy) trägt der Sync-Zeitstempel aus US-2 AC2 den Grossteil. AC1 und AC2 sind in v0 dennoch umgesetzt (Stale-Indikator ab >24 h mit Retry, aktive Benachrichtigung bei widerrufenem Key), weil der blosse Zeitstempel veraltete Daten nicht als solche kenntlich macht. Vollwertig — mehrere Quellen nebeneinander — relevant ab v1. |
| US-13 | Trainingsprofil für gezieltere AI-Empfehlungen | **Should** | Hebt die Qualität von US-3 spürbar, ohne dass irgendetwas davon abhängt: Ohne Profil verhält sich die App exakt wie bisher. Zwei Felder, überspringbar — der Aufwand steht in keinem Verhältnis zum Gewinn an Treffsicherheit der Empfehlung. |
| US-9 | Progressionskurven pro Übung | **Could** | US-3 deckt den Hauptnutzen ab. Epley-Formel + Plateau-Detection sind nicht-trivial. |
| US-10 | Daten manuell neu laden | **Could** | iOS-Pattern, das User erwarten — kein Showstopper. 1–2 Tage Aufwand, ergänzt US-2 AC2. |
| US-11 | Wochenübersicht als Push-Notification | **Won't** | iOS-Permission-Flow + Background-Scheduling + LLM-Call-Fallback ist eigenes Sub-System. Relevant ab v1.2. |
| US-12 | Trainingsvorschlag zurück in Hevy schreiben | **Won't** | Setzt Hevy PRO voraus, erfordert UX-Klärung (Write-Target, Undo). Risiko: Empfehlung falsch übernommen. Relevant ab v1.2. |


## 3. Nicht-funktionale Anforderungen

| Bereich | Anforderung |
|---|---|
| Performance | Spinner erscheint sofort nach Tap auf «Analysieren»; Cancel-Button nach 30s ohne Antwort (US-3 AC1) |
| Performance | Dashboard-Load innerhalb von 3 Sekunden nach Kaltstart (US-1 AC2) |
| Sicherheit | API-Keys ausschliesslich im iOS Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) |
| Privacy | Keine User-Daten auf externen Servern (ausser direktem API-Call zu Hevy/Claude) |
| Sprache | English-only (alle UI-Strings, Fehlermeldungen, System-Prompt) — kein i18n-Framework |
| Datenschutz | Nur Daten des eingeloggten Users im LLM-Prompt (keine Benchmarks fremder Nutzer) |
| Datenschutz | Consent (Datenübertragung an Anthropic + Eigenverantwortung) wird beim Onboarding eingeholt und lokal gespeichert (US-4 AC4/AC5) |
| Datenschutz (nDSG) | Trainingsdaten sind Gesundheitsdaten nach Art. 5 lit. c nDSG — explizite Einwilligung ist Pflicht. Die Übertragung an Anthropic (USA) stützt sich auf den DPA des Endusers (Anthropic Commercial Terms inkl. SCCs + Swiss Addendum, automatisch gültig ab Account-Erstellung). Das FitBuddy-Team schliesst keinen eigenen DPA ab — im BYO-Key-Modell ist der Enduser Anthropic-«Customer». |
| Datenschutz (nDSG) | Die App enthält einen statischen Datenschutzerklärung-Screen (erreichbar aus Onboarding + Einstellungen) mit: Verantwortlichem, bearbeiteten Daten, Zweck, Drittempfängern (Hevy/Anthropic), Drittland USA, Rechten der betroffenen Person (Auskunft, Löschung). |
| Datenschutz (nDSG) | User kann jederzeit alle lokal gespeicherten Daten löschen (Keychain-Einträge + Cache) über «Daten löschen / Account zurücksetzen» in den Einstellungen — App kehrt in den Onboarding-Zustand zurück. |
| LLM-Kosten | Analyse jederzeit auf Knopfdruck; Button disabled während laufendem Call, danach kein Cooldown. Hartes Kostenlimit ist das Spending Limit im Anthropic-Account des Users (BYO-Key, ADR-004) |
| LLM-Kosten | Analyse-Button disabled während laufendem Call — kein Doppel-Submit möglich |


## 4. Out of Scope

Bewusst ausgeschlossen für den PoC. Dokumentiert, damit später kein Scope-Creep entsteht.

| Bereich | Out of Scope weil |
|---|---|
| **US-11** Push-Notifications (Wochenübersicht) | iOS-Permission-Flow, Background-Scheduling, LLM-Fallback bei Offline-Zustand — eigenes Sub-System. Frühestens v1.2 sinnvoll, wenn Retention-Daten zeigen, dass User die App nicht regelmässig öffnen. |
| **US-12** Write-back nach Hevy | Erfordert Hevy PRO, ungeklärtes Write-Target (Routine vs. zukünftiges Workout) und Undo-UX. Falsch übernommene AI-Empfehlung ist ein realer Schaden für den User (R3). |
| **Cross-Source-Analyse** | Die Strava- und Polar-Connectoren samt OAuth-Flow und quellenbezogenem Cache sind mit US-5 im PoC umgesetzt (ADR-010, ADR-011). Ausserhalb des Scope bleibt die quellenübergreifende Auswertung: Cardio-Sessions fliessen in v0 weder in den Analyse-Prompt noch in die Übungsliste oder die Progressionskurve ein. |
| **Apple Health Integration** | Siehe Risiko 1 — Vorschlag: OUT für PoC. |
| **i18n / Lokalisierung** | English-only ist Definition of Done — kein Framework, keine zweite Sprache. Spart Übersetzungs-Roundtrips beim Prompt-Tuning. |
| **App Store Release** | Distribution ausschliesslich via TestFlight / Sideload. Spart App-Store-Review, Marketing-Assets und Compliance-Roundtrips. |
| **Backend-Proxy für Claude API** | ADR-1: Key direkt im Keychain, Call direkt vom Gerät. Vereinfacht PoC, ist aber vor v1.0 zwingend zu revisiten (Key-Exposition bei Gerätekompromittierung). |
| **AWS Bedrock EU (eu-central-1)** | ADR-5: PoC nutzt Claude API USA über BYO-Key-Modell (User-DPA + Consent). Migration auf Bedrock Frankfurt ist v1.0-Pflicht, nicht PoC-Inhalt. |
| **Eigenes Tracking / Analytics** | Kein Mixpanel, kein Amplitude, kein Crashlytics im PoC. Würde Datenschutz-Erklärung verkomplizieren und Consent verändern. |
| **Plateau-Detection als eigenständiges Feature** | Teil von US-9 (Could), kein eigenes Item. Wenn US-9 nicht in den Sprint passt, fällt es ersatzlos weg. |


## 5. Quality Attributes — Top 3 Architektur-Treiber

*Analysiert aus den Requirements und Projektdokumentation. Direkter Input für ADR-Entscheide und Sprint-Planung.*

---

### QA-1 — Security / Privacy *(kritischster Treiber)*

**Warum für FitBuddy besonders wichtig:**

Das Kernversprechen der App *ist* Security: «API-Keys verbleiben im iOS Keychain — alle API-Calls laufen direkt vom Gerät.» Trainingsdaten sind Gesundheitsdaten nach nDSG Art. 5 lit. c — rechtlich eine der höchstgeschützten Datenkategorien. Jeder Claude-API-Call überträgt diese Daten an Anthropic (Vertragspartner: Anthropic Ireland, Limited; Verarbeitung in den USA durch Anthropic PBC) ohne Angemessenheitsbeschluss der Schweiz. Die Rechtsgrundlage ist der DPA des Endusers (inkl. SCCs + Swiss Addendum), automatisch gültig mit Erstellung des eigenen Anthropic-Accounts. Wenn der Claude-API-Key auf dem Gerät kompromittiert wird, gibt es keinen server-seitigen Kill-Switch: der User muss ihn manuell neu eingeben.

**Konkrete architektonische Massnahmen:**

| Massnahme | Begründung |
|---|---|
| `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (US-1 AC1) | Verhindert iCloud-Sync des Keys und Zugriff bei gesperrtem Gerät — falsches Attribut = Key landet in iCloud-Backup |
| Certificate Pinning für Hevy + Claude API | Einziger verbleibender Angriffsvektor bei kompromittiertem Netzwerk — **fehlt noch als NFR, muss ergänzt werden** |
| Consent-Text US-4 AC4 korrekt formulieren **vor erstem TestFlight-Build** | Anthropic Ireland Ltd als Vertragspartner, USA als Drittland, DPA des Users als Rechtsgrundlage — inhaltlich falscher Consent verletzt Art. 19 revDSG |
| Consent mit Version + Timestamp im Keychain (US-4 AC5) | Versionierter Consent ist Pflicht: bei Änderung der Datenverarbeitung muss erneut eingeholt werden |
| Kein Logging von Key-Material | Eine einzige Log-Zeile mit API-Key in einem Crash-Report reicht für eine Kompromittierung |

**Wenn ignoriert:**

Rechtliche Haftung nach nDSG, Apple-Review-Ablehnung wegen fehlendem Privacy-Manifest, öffentlicher Trust-Verlust. Konkret: falsches Keychain-Attribut = Keys landen in iCloud-Backup; kein Certificate Pinning = MITM-Angriff im WLAN liest Keys mit; kein AVV = jeder Claude-Call ist rechtswidrig.

---

### QA-2 — Reliability *(Kernvoraussetzung für Nutzbarkeit)*

**Warum für FitBuddy besonders wichtig:**

Beide externen Abhängigkeiten sind instabil — dokumentiert: Hevy hat «no guarantees — we might abandon this entirely» geschrieben (R1). Claude API kann 10–30 Sekunden dauern, Rate-Limit-Fehler werfen oder bei schlechtem Netz ausfallen. Das Dashboard ist der einzige Einstiegspunkt in den gesamten Produktwert — ein leerer Screen beim Öffnen führt zur Deinstallation. US-3 (AI-Analyse) hängt vollständig von gecachten Dashboard-Daten ab: keine Reliability im Cache = keine AI-Analyse.

**Konkrete architektonische Massnahmen:**

| Massnahme | Begründung |
|---|---|
| CoreData für Activity-Cache (nicht UserDefaults) | Relationales Modell für `Activity → Exercise → ExerciseSet`; Migration-Support für Strava-Daten in v1; Queries ohne alles in-memory laden |
| `lastSyncTimestamp` persistent in UserDefaults | Überlebt App-Kills; immer als Banner im Dashboard sichtbar (US-2 AC2) |
| HTTP 401 → harter Logout (US-1 AC3) | Kein stilles Weiterlaufen mit gecachten Daten die der User für aktuell hält → falsche AI-Empfehlung auf Basis veralteter Daten |
| Claude-Timeout 30 s + Cancel-Button (US-3 AC1) | Ohne Cancel-Button: User sieht hängenden Spinner, kill-swipet die App, glaubt sie ist kaputt |
| Doppeltipp-Schutz: Button disabled, solange ein Call läuft — **keine Sperre danach** | Verhindert versehentliche Mehrfach-Calls, ohne den User nach einer Analyse warten zu lassen. Die frühere 60-s-Sperre ist entfernt. Bewusst kein Kostenlimit — das ist das Spending Limit im Account des Users |

**Wenn ignoriert:**

Hevy hat einen Ausfall → leerer Screen (Cache war in-memory, App wurde über Nacht gecleaned) → Deinstallation. Claude-Call läuft > 30 s → kein Cancel-Button → App muss neu gestartet werden. Stiller 401-Fehler → User erhält AI-Empfehlung auf Basis veralteter Daten.

---

### QA-3 — Maintainability *(Voraussetzung für geplante Roadmap)*

**Warum für FitBuddy besonders wichtig:**

Zwei dokumentierte Roadmap-Items blockieren ohne saubere Abstraktion: Strava (v1, in MoSCoW als Should gelistet) und die Bedrock-Migration (v1.0, ADR-5: «obligatorisch vor kommerziellem Launch»). Wenn HevyConnector-Code in Dashboard-Logik und AI-Prompt-Builder verwächst, muss bei jedem neuen Connector alles angefasst werden. Der Entscheid muss vor Sprint 1 getroffen sein — «Im PoC wird nur das `FitnessConnector`-Interface verankert» bedeutet: die Architektur muss jetzt stimmen.

**Konkrete architektonische Massnahmen:**

| Massnahme | Begründung |
|---|---|
| `FitnessConnector`-Protocol **vor** HevyConnector implementieren (ADR-3) | Verhindert, dass Hevy-spezifische Typen in UI und AI Engine eindringen |
| `StravaConnector`-Stub im PoC committen (kompiliert, wirft `NotImplemented`) | Verhindert Protocol-Drift zwischen Sprint 1 und v1 — Interface bleibt stabil |
| AI Analysis Engine liest **nur** aus dem Activity-Cache, nie direkt vom Connector | Claude-Prompt-Builder bleibt unverändert wenn Strava dazukommt |
| Claude-API-Call in eigene `InferenceService`-Klasse kapseln | Bedrock-Migration = eine Klasse austauschen, nicht jeden Call im Codebase |
| ADRs 1–5 im Code verlinkt | Neue Teammitglieder verstehen warum Entscheidungen so sind — verhindert «versehentliches Rückgängigmachen» |

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
