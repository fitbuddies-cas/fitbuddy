# ADR-014: Verdict-Regel der App — Reihenfolge, Schwellen und die vierte Klasse «zu dünne Datenbasis»

**Status:** Accepted
**Datum:** 2026-09-20
**Treiber-QA:** Reliability (QA-2), Maintainability (QA-3)

---

## Kontext

US-16 (#224) verlangt, dass dieselbe Datenlage dieselbe Empfehlung ergibt. Heute ist das Verdict bis auf eine einzige Regel freie Modellwahl: `RecoveryMetrics.needsRecovery` erzwingt ab 6 von 7 Trainingstagen `recover` (`AnalysisReportValidator.swift`), und `#177` stuft ein `progress` auf `hold` zurück, wenn keine Karte den Schritt stützt. Dazwischen entscheidet das Modell. Im Live-Test zu US-15 ergab dasselbe Mock-Profil in drei Läufen drei Verdicts.

#227 verlegt die Entscheidung in die App. Damit muss **vorher** feststehen, welche Kennzahl in welcher Reihenfolge urteilt — sonst wird die Schwelle beim Implementieren erfunden. Dieser ADR legt das fest; er enthält keinen Code.

### Warum die naheliegenden Kennzahlen nicht taugen

Die drei Zahlen, die sich anbieten, messen nicht das, was das Verdict behaupten will:

1. **6 von 7 Trainingstagen** misst *Ruhetage*, nicht Belastung. Für ein gemischtes Profil — drei Läufe, drei Krafteinheiten — sind sechs Tage unauffällig. Der Code sagt das selbst: FitBuddy erfasst keine Intensität, an der es einen Lauf gegen eine Kniebeugen-Einheit reihen könnte.
2. **Volumen-Quotienten** («letzte Woche gegen den Schnitt davor») schwanken stark mit dem gewählten Fenster. FitBuddys Fenster ist dazu nicht einmal fix: `AnalysisWindow.ladder` weitet 4 → 8 → 13 Wochen, bis es Training findet. Dieselbe Historie ergibt je nach Sprosse einen anderen Quotienten.
3. **Tonnage ignoriert Intensität.** 10×10 mit 50 % ist mehr Tonnage als 3×3 mit 90 %, bei deutlich geringerer Belastung.

Was fehlt, ist die Anstrengung. Sie ist eine eigene Story (#241, US-18) und liegt teilweise schon ungenutzt im Cache. Dieser ADR legt fest, wie die Regel sie nutzt, sobald sie da ist — und was gilt, solange sie fehlt.

### Was die App heute wirklich weiss

Nur drei Aussagen rechnet die App selbst und kann sie belegen:

| Aussage | Herkunft im Code | Gilt für |
|---|---|---|
| «An wie vielen der letzten 7 Tage wurde trainiert» | `RecoveryMetrics.trainingDays` | alle Quellen, beide Domänen (#184) |
| «Diese Übung hat in den letzten 3 Sessions keine neue e1RM-Bestleistung erreicht» | `ExerciseProgression.isPlateaued` (US-9 AC2) | nur Kraft |
| «Diese Übung hat ihre Fenster-Bestleistung in der jüngsten Session gesetzt» | `ExerciseProgression.bestEstimateKg` / `.latestEstimateKg` | nur Kraft |

Alles andere ist entweder Umfang (Sessions, Tonnage, Distanz) oder Modelltext. Die Regel baut deshalb ausschliesslich auf diesen drei Aussagen auf — und gibt zu, wenn keine davon trägt.

---

## Entscheidung

### 1. Vier Verdict-Klassen

`AnalysisVerdict` erhält einen vierten Fall, `insufficientData`. Er bedeutet: **kein Urteil.** Empfehlung: «trainiere weiter wie bisher». Er ist kein schwächeres `hold` — `hold` ist die Aussage «die Daten tragen keinen Schritt nach oben», `insufficientData` die Aussage «die Daten tragen gar nichts».

### 2. Entscheidungsbaum

Die Stufen laufen in dieser Reihenfolge. Die erste greifende Stufe bestimmt das Verdict; danach läuft nur noch die Deckelung aus Stufe 5.

| Stufe | Bedingung | Ergebnis |
|---|---|---|
| **0 — Ruhetag-Gate** | `recovery.trainingDays >= 6` (US-3 AC6) | `recover` |
| **1 — Datenbasis-Gate** | weniger als **4** analysierte Sessions im aufgelösten Fenster **oder** keine Session in den letzten 7 Tagen | `insufficientData` |
| **2 — Plateau-Entscheidbarkeit** | keine gelistete Übung erreicht **4** Progressionspunkte | `insufficientData` |
| **3 — Plateau-Mehrheit** | **mehr als die Hälfte** der entscheidbaren Übungen ist plateauiert | `hold` |
| **4 — Bestleistung** | mindestens eine entscheidbare, nicht plateauierte Übung hat ihre Fenster-Bestleistung in der jüngsten Session gesetzt | `progress` |
| **Rest** | keine der obigen | `hold` |
| **5 — Anstrengungs-Deckel** (ab #246) | mindestens eine qualifizierte Quelle zeigt steigende Anstrengung | `progress` → `hold`; ein `recover` aus Stufe 0 bleibt `recover`; `insufficientData` bleibt `insufficientData` |

**Zu Stufe 0.** Sie bleibt an erster Stelle, weil US-3 AC6 eine Must-Anforderung ist und weil die Aussage in sich vollständig ist: An 6 von 7 Tagen trainiert heisst, es gab höchstens einen Ruhetag. Das ist wahr, ohne dass eine Intensität bekannt sein müsste. Die Schwelle wird deshalb **weder gesenkt noch erweitert noch in die Gegenrichtung angewendet** — sie kann `recover` erzwingen, nie `progress` erlauben. Headline und Lead sagen weiterhin genau das, was gemessen wurde («You trained on 6 of the last 7 days»), nicht «deine Belastung ist zu hoch». Eine Änderung dieser Schwelle ist eine Anforderungsänderung, kein Regel-Tuning.

**Zu Stufe 1.** «4 Sessions» ist keine Zahl über Trainingslehre, sondern die Untergrenze, unterhalb derer die eigenen Kennzahlen der App nichts hergeben: Unterhalb von vier Sessions kann keine Übung die vier Punkte erreichen, die Stufe 2 verlangt. Die zweite Bedingung ist nötig, weil das Fenster sich weitet, bis es Training findet — ein 13-Wochen-Fenster kann mit wochenlanger Pause enden, und Kennzahlen über die letzten 7 Tage beschreiben dann eine Pause, kein Training.

**Zu Stufe 2.** Entscheidbar ist eine Übung ab **4** Progressionspunkten — genau die Bedingung, unter der `ExerciseProgression.isPlateaued` überhaupt antworten kann (`points.count > plateauSessionCount`, mit `plateauSessionCount = 3`). Die Zahl wird nicht neu gesetzt, sondern aus US-9 AC2 übernommen, damit es nicht zwei Plateau-Begriffe gibt.

**Zu Stufe 4.** «Bestleistung in der jüngsten Session» heisst: `latestEstimateKg` ist das Maximum von `points`. Das ist bewusst eine Aussage *pro Übung* und nicht über die Woche: Sie ist belegbar, sie ist fensterunabhängig, und sie ist genau die Aussage, die eine Progression-Karte tragen muss.

### 3. Wie die Anstrengungsdaten aus #241 einfliessen

Das Verrechnungsverbot aus #242 gilt hier unverändert: Anstrengungswerte werden **nie summiert, gemittelt oder quellenübergreifend verglichen**. Hevy-RPE, Strava Relative Effort und Polar Cardio Load sind drei Skalen ohne dokumentierte Umrechnung.

Daraus folgt für die Regel:

1. **Nur Richtung, nie Niveau.** Die Regel liest «steigt diese Quelle gegen sich selbst», nie «RPE 8 ist hart». Ein Niveau wäre ein Anker von aussen und verletzt Regel 2 des System-Prompts.
2. **Getrennt pro Quelle.** Jede Quelle wird für sich ausgewertet. Steigt eine, greift die Deckelung; die anderen werden nicht dagegen aufgerechnet. Präzisiert durch [ADR-015](ADR-015-anstrengungsskalen-getrennt.md): getrennt je Skala, nicht je Quelle; Polar kann mehrere Reihen beitragen.
3. **Qualifiziert ist eine Quelle**, wenn sie in mindestens **3** Wochen des Fensters *und* in den letzten 7 Tagen einen Wert trägt. Darunter wird sie ignoriert, nicht ergänzt.
4. **Steigend** heisst: Mittel der letzten 7 Tage über **130 %** des Mittels der vorangehenden Wochen derselben Quelle. **Fallend**: unter **80 %**. Dazwischen: stabil.
5. **Anstrengung kann nur deckeln, nie befördern.** Steigende Anstrengung senkt `progress` auf `hold`. Sie erzeugt **kein** `recover` für sich allein — dafür braucht es zusätzlich Stufe 0. Fallende oder stabile Anstrengung erzeugt gar nichts.
6. **Domänengebunden.** Stufe 5 liest nur Quellen der Domänen, die das Profil analysiert (siehe 5.). Ruhetage sind domänenblind — ein Ruhetag ist ein Ruhetag, gleich wofür —, Anstrengung ist eine Aussage über *dieses* Training.

Die Zahlen in 3. und 4. sind gesetzt, nicht gemessen, und ausdrücklich **provisorisch**: Der Quotient in 4. teilt die Fenster-Empfindlichkeit, die dieser ADR oben der Volumen-Kennzahl vorwirft. Der Unterschied ist allein, dass er auf einer Anstrengungsskala läuft statt auf Tonnage — und dass er asymmetrisch wirkt, also im Zweifel vorsichtiger macht statt mutiger. #229 (Streuung messen) und #246 ratifizieren oder korrigieren sie an echten Werten, bevor sie in der Anzeige etwas behaupten dürfen.

**Solange #241 nicht geliefert hat, entfällt Stufe 5 ersatzlos.** Der Baum läuft ohne sie. Das ist die ehrliche Auskunft dieses ADR: Ein belastungsbasiertes `recover` ist vor #241 **nicht** herleitbar. `recover` hat bis dahin genau einen Auslöser, und der ist eine Ruhetag-Zählung.

### 4. Kein Ersatzwert für fehlende Anstrengung

Fehlt die Anstrengung, wird **kein** Wert angenommen — kein Mittelwert, kein «mittel», kein Default. Ein geschätzter Wert sähe auf dem Screen aus wie ein gemessener. Das ist dieselbe Regel, nach der `RecoveryMetrics.averageRPE` heute `nil` ist statt `0`.

Fehlende Anstrengung allein ist aber **kein** Auslöser für `insufficientData`: Die Stufen 2–4 sind Aussagen über e1RM-Verläufe und hängen nicht von der Anstrengung ab. Sind sie entscheidbar, urteilt die Regel; ist es auch das nicht, greift Stufe 1 oder 2.

> #241 AC5 formuliert diesen Rückfall als «die Regel fällt auf die Umfangskennzahlen zurück». Dieser ADR liest das als Rückfall auf die **Progressions- und Plateau-Kennzahlen** der App, nicht auf Tonnage- oder Distanz-Quotienten — die scheiden aus den oben genannten Gründen aus. Wer #241 anders gelesen haben will, muss AC5 ändern, nicht diesen Baum.

### 5. Was die Regel pro Profil liest

`AnalysisProfile` (#185) entscheidet, worüber dieser Lauf urteilt. Das Profil wird vorher auf das verengt bzw. geweitet, was das Fenster hergibt — die Regel bekommt also nie ein Profil ohne Sessions.

| Profil | Stufe 0 | Stufe 1 | Stufen 2–4 | Stufe 5 |
|---|---|---|---|---|
| `.strength` | Ruhetage über **alle** Quellen und beide Domänen (#184) | Kraft-Sessions | ja | nur Hevy-RPE |
| `.endurance` | wie oben | Ausdauer-Sessions | **entfallen** | Strava / Polar, je Skala getrennt (ADR-015) |
| `.overallLoad` | wie oben | alle Sessions | auf der Kraft-Hälfte | alle Quellen, je Skala getrennt (ADR-015) |

Unter `.endurance` gibt es weder gelistete Übungen noch eine Plateau-Aussage; ein e1RM existiert dort nicht. Die Stufen 2–4 entfallen deshalb nicht «weil der Wert 0 ist», sondern weil es die Grösse nicht gibt. Damit gilt:

> **Unter `.endurance` kann die Regel in v0 kein `progress` erzeugen.** Möglich sind `recover` (Stufe 0), `hold` (Stufe 5, ab #246) und sonst `insufficientData`.

Das ist unbequem und trotzdem korrekt: Eine Steigerungsempfehlung für Ausdauer müsste die App aus Wochendistanz oder Wochenzeit ableiten, und das ist genau der Quotient, den dieser ADR verwirft. Der Weg dahin führt über #241, nicht über eine gesetzte Prozentzahl auf der Distanz. Unter `.strength` zählt die Ausdauer-Hälfte der Woche für die Ruhetage mit, wird aber ausdrücklich nicht analysiert — sie taucht dort in keiner anderen Stufe auf.

Nirgendwo steht eine `0` für eine Grösse, die es im Profil nicht gibt. Fehlt eine Grösse, ist sie `nil`, und die Stufe wird übersprungen.

### 6. Anzeige der vierten Klasse

| Element | Inhalt |
|---|---|
| **Headline** (App-Text, ersetzt den Modelltext) | `Not enough data to judge.` |
| **Lead** (App-Text, ersetzt den Modelltext) | `Your logged training doesn't yet support a recommendation for or against more load. Keep training as before — the next analysis will have more to go on.` |
| **Karten** | Keine `progression`-, keine `repProgression`- und keine `recovery`-Karte, ebenso keine `metric`-Karte mit Zielwert (`to`). Zugelassen sind `note`-Karten und Karten, die ausschliesslich gemessene Zahlen wiedergeben (`imbalance`, `interference`). |
| **Begründungs-Note** | Die App fügt **eine** `note` an erster Stelle ein, Titel `Why there's no verdict`, deren Text die greifende Bedingung benennt (zu wenige Sessions im Fenster / keine Session in den letzten 7 Tagen / keine Übung mit genug Sessions / keine Anstrengung erfasst). |

Headline und Lead sind hier App-Text, nicht Modelltext — dieselbe Konstruktion wie `recoveryHeadline` / `recoveryLead`. Der Grund ist derselbe: Der Modell-Lead argumentiert für ein Urteil, das die App gerade zurückgenommen hat.

Eine `progression`-Karte wäre ein Urteil und fällt deshalb weg — ebenso die `repProgression`-Karte aus US-17 ([ADR-013](ADR-013-progressionsband-je-muskelgruppe.md)), die mehr Wiederholungen statt mehr Last empfiehlt, und eine `metric`-Karte, die mit `to` einen Schritt nennt; eine `recovery`-Karte wäre `recover` unter anderem Namen. Bleibt nichts übrig, zeigt der Screen null Karten — das Kartenband ist seit #177 für null bis vier Karten ausgelegt.

Der Lead nennt die fehlende Anstrengung bewusst **nicht**. Der einmalige Hinweis «mit erfasster Anstrengung wird die Analyse genauer» gehört zu #241 AC6 und erscheint genau einmal an seinem eigenen Ort; auf diesem Screen steht er allenfalls in der Begründungs-Note, wenn die fehlende Anstrengung tatsächlich die greifende Bedingung war.

### 7. Das Modell setzt das Verdict nicht mehr

Das Feld `verdict` **bleibt im Antwortschema** und wird von der App gelesen, überschrieben und die Abweichung protokolliert (#228). Es fällt nicht aus dem Schema, weil #224 AC4 und #229 die Modellwahl brauchen, um die Trefferquote über mehrere Läufe zu messen — ohne sie gäbe es nichts zu vergleichen.

`insufficientData` wird dem Modell **nicht** angeboten: Das Schema kennt dort weiterhin nur `progress`, `hold`, `recover`. Die vierte Klasse ist eine Aussage der App über ihre eigene Datenlage, nicht etwas, das ein Modell über sich selbst behaupten kann.

Headline, Lead und Summary bleiben Modelltext, ausser in den Fällen, in denen die App das Verdict überschreibt — dort ersetzt sie sie, wie heute schon bei `recoveryHeadline` und `holdHeadline`.

**Abgrenzung zu [ADR-013](ADR-013-progressionsband-je-muskelgruppe.md).** Band und 2-for-2-Bedingung prüfen einzelne Karten — wie gross ein Schritt sein darf und ob er überhaupt zulässig ist. Sie entscheiden nicht über das Verdict, und dieser ADR entscheidet nicht über die Karten. Eine abgestufte Progression-Karte ändert das Verdict nicht; umgekehrt macht ein `progress` der App keine Karte zulässig, die ADR-013 verwirft.

### 8. Worauf die Regel nicht beruht

- **Keine Populationsnormen, keine Kraftstandards.** Kein «typisches» Volumen für Körpergewicht, Geschlecht oder Alter. Regel 2 des System-Prompts gilt unverändert weiter — und sie gilt jetzt auch für die App: Was das Modell nicht darf, darf der Code erst recht nicht.
- **Keine Herzfrequenzzonen, keine Zielpulse, keine Prozentsätze der Maximalherzfrequenz.** Regel 7 gilt unverändert.
- **Kein veröffentlichtes Belastungsmodell.** Kein Acute-Chronic-Workload-Ratio, kein TRIMP-Schwellenwert, kein Readiness-Score. Polars fertiger `cardio_load_status` wird nicht übernommen (#242).
- **Keine Diagnose.** Die Regel sagt «diese Zahlen tragen keinen Schritt nach oben», nie «du bist übertrainiert».
- **Kein Anspruch auf wissenschaftliche Validierung.** Weder dieser ADR noch der Code noch die UI behaupten, die Regel sei validiert.

### 9. Herkunft der Zahlen

Die Regel benutzt fünf Zahlen. Zwei davon stammen aus dem Projekt selbst, drei sind schlicht gesetzt.

**Übernommen:** Die **6 von 7 Trainingstagen** stehen als US-3 AC6 in den Anforderungen und sind seit #175 im Code; dieser ADR erfindet sie nicht, er ordnet sie nur ein. Die **4 Progressionspunkte** sind die bestehende Plateau-Definition aus US-9 AC2 (`ExerciseProgression.plateauSessionCount = 3` plus die Session, gegen die verglichen wird) — wiederverwendet, damit es im Produkt nur einen Plateau-Begriff gibt.

**Gesetzt:** Die **4 Sessions** des Datenbasis-Gates sind eine Projektentscheidung; sie ist an der Plateau-Definition ausgerichtet, aber nicht aus ihr hergeleitet. Die **Mehrheit der plateauierten Übungen** (mehr als die Hälfte) ist eine Projektentscheidung. Die **Anstrengungs-Schwellen** (3 Wochen, 130 %, 80 %) sind Projektentscheidungen und zusätzlich provisorisch — sie stehen hier, damit #246 nicht ohne Vorgabe implementiert, und sind vor dem ersten Einsatz an echten Werten zu prüfen.

Keine dieser Zahlen stammt aus einer Studie, einer Norm oder einem veröffentlichten Belastungsmodell. Wo dieser ADR Literatur erwähnt — etwa die Unzuverlässigkeit von Belastungsquotienten —, ist das ein Argument *gegen* eine Kennzahl, keine Herleitung einer eigenen.

---

## Konsequenzen

### + Positiv

- **Reproduzierbar.** Bei unveränderter Datenlage liefert jeder Lauf dasselbe Verdict, gleich welcher Provider und gleich wie er sampelt — US-16 AC1 hängt allein daran (AC2 ist Hygiene, nicht die Massnahme).
- **Belegbar.** Jede Stufe steht auf einer Zahl, die die App selbst gerechnet hat und auf dem Screen zeigen kann.
- **Die Lücke ist sichtbar statt kaschiert.** Wo die Kennzahlen kein Urteil tragen, sagt der Screen das, statt zwischen `hold` und `recover` zu raten.
- **Eine Zahl, eine Stelle.** Plateau-Definition und Ruhetag-Schwelle werden aus bestehenden Konstanten gelesen, nicht neu geschrieben; #227 referenziert diesen ADR im Kommentar.
- **Das Verrechnungsverbot bleibt unangetastet.** Anstrengung wirkt pro Quelle und nur deckelnd — es gibt keine Stelle, an der zwei Skalen zusammenkämen.

### – Negativ

- **`insufficientData` trägt vorerst viele Fälle.** Jeder Nutzer mit weniger als vier Sessions im Fenster und jeder, dessen Übungen noch keine vier Sessions haben, bekommt kein Urteil. Bei den Mock-Profilen und bei einem frisch verbundenen Polar-Konto (nur Trainings nach der Registrierung, [ADR-011](ADR-011-polar-als-dritte-quelle.md)) ist das der Normalfall.
- **Ausdauer bekommt in v0 kein `progress`.** Ein reiner Läufer sieht «Ready to progress» nie. Das ist die direkte Folge davon, dass die App für Ausdauer keine der drei belegbaren Aussagen besitzt — und es macht #241 zur Voraussetzung dafür, dass US-15 sein Versprechen für Ausdauer einlöst.
- **`recover` steht vor #241 auf einer Ruhetag-Zählung.** Genau die Kennzahl, die dieser ADR als Belastungsmass verwirft, ist bis dahin der einzige Auslöser. Sie bleibt nur, weil sie als *Ruhetag*-Aussage wahr ist und weil US-3 AC6 sie verlangt.
- **Das Modell verliert das Verdict.** Es formuliert nur noch. Headline und Lead müssen in vier statt zwei Fällen durch App-Text ersetzt werden können, und der Modelltext wird häufiger verworfen — bezahlte Tokens, die nicht auf den Screen kommen. Das Kartenschema und die Karten-Validierung aus #175/#177 bleiben davon unberührt.
- **Die Schwellen driften, wenn sie doppelt gepflegt werden.** ADR und Code müssen dieselbe Zahl führen; der Code nennt diesen ADR im Kommentar, aber eine technische Kopplung gibt es nicht.
- **Drei der fünf Zahlen sind Setzungen.** Sie wirken auf dem Screen wie Messungen, sobald ein Verdict darauf steht. Dagegen hilft nur, dass keine von ihnen ein `recover` allein auslösen kann.

### Was #227 ergänzen muss

`AnalysisReportEvidence` trägt heute `exercises`, `muscleGroupsPerWeek` und `recovery` — **kein** Volumen-Trend-Feld und **kein** Plateau-Feld. Die Regel braucht zusätzlich:

| Feld | Inhalt | Woher |
|---|---|---|
| `sessionsInWindow` | Anzahl analysierter Sessions im aufgelösten Fenster, in den Domänen des Profils | `AnalysisPromptBuilder.analysedSessions` |
| Plateau-Fakten je gelisteter Übung | Punktzahl, `isPlateaued`, «jüngste Session ist Fenster-Bestleistung» | `ExerciseProgression` — der Prompt-Builder rechnet das für `plateauVerdict(_:)` bereits und wirft es danach weg |
| `analysisProfile` | das Profil des Laufs | kommt mit #185 |
| Anstrengung je Quelle | Werte pro Quelle und Woche, nach Skala getrennt | #246, später |

Die Plateau-Fakten gehören an `ListedExercise`, nicht in eine parallele Liste: Evidence führt die Übungen bereits, und zwei Listen über dieselben Zeilen sind zwei Chancen, sich zu widersprechen.

Ein **Volumen-Trend-Feld wird bewusst nicht ergänzt.** Die Regel benutzt keines, und ein Feld, das nur der Prompt liest, gehört nicht in die Evidence.

---

## Offene Punkte

| Frage | Priorität | Fällig |
|---|---|---|
| Anstrengungs-Schwellen (3 Wochen, 130 %, 80 %) an echten Werten ratifizieren oder korrigieren | Hoch | mit #246 / #229 |
| Ableitung eines `progress` für Ausdauer — was die App dort belegen kann, das kein Distanz-Quotient ist | Hoch | v1, nach #241 |
| Ob `insufficientData` bei sehr dünner Datenlage häufiger erscheint, als die Nutzer es akzeptieren — Messung statt Vermutung | Mittel | mit #229 |
| Ob die Ruhetag-Schwelle nach #241 in eine Anstrengungsaussage überführt und US-3 AC6 entsprechend geändert wird | Mittel | v1 |
