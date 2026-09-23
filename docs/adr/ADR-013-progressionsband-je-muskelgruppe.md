# ADR-013: Progressionsband je Muskelgruppe — eine erlaubte Spanne statt eines Zielwerts, konditional auf 2-for-2

**Status:** Accepted
**Datum:** 2026-09-23
**Treiber-QA:** Reliability (QA-2), Maintainability (QA-3)

---

## Kontext

Die Steigerungsempfehlung ist heute an zwei Stellen auf **genau einen** Zielwert pro Übung festgelegt:

1. **Prompt-Regel 6** (`AnalysisPromptBuilder`) sagt dem Modell: Langhantelübungen in Schritten von 2.5 kg, alle anderen höchstens um den kleinsten gelisteten Schritt, ohne gelisteten Schritt Wiederholungen statt Gewicht (#173).
2. **`AnalysisReportValidator.maxStepKg(for:)`** lässt genau diesen einen Schritt durch (#175). Alles darüber wird zur Notiz abgestuft — auch dann, wenn 100 → 105 kg auf der Kniebeuge fachlich der vernünftigere Vorschlag war.

Das ist **Geräte-Granularität**: die kleinste Scheibe, die auf die Stange passt. Sie sagt, in welchen Schritten man steigern *kann*, nicht, um wie viel man steigern *sollte*. Als Obergrenze verwechselt sie beides. Der Live-Test zu US-15 hat gezeigt, dass der Validator damit brauchbare Modellvorschläge verwirft (siehe #224, #225).

Dazu fehlt eine Bedingung: Regel 6 bietet eine Steigerung an, sobald ein letztes Arbeitsgewicht vorliegt — unabhängig davon, ob der User das Ziel, gegen das er trainiert hat, überhaupt erreicht hat. Eine Steigerung ohne diese Bedingung ist eine unkonditionale Empfehlung, wo die Trainingslehre eine konditionale kennt.

US-17 (#225) verlangt deshalb eine **erlaubte Spanne** pro Übung (AC1), die sich **primär nach der Muskelgruppe** richtet (AC5), eine **2-for-2-Bedingung** (AC7) und einen ADR, der Herkunft und Nicht-Herkunft der Zahlen festhält (AC4). Dieser ADR legt die Zahlen fest; #232 (Prompt), #233 (Validator) und #240 (Routinen-Ziele) setzen sie um.

---

## Entscheidung

**1. Das Band ist eine Obergrenze in Prozent des Arbeitsgewichts, gestaffelt nach Muskelgruppe.** Ausgangspunkt ist der Korridor von 2–10 % Laststeigerung, mit dem kleineren Anteil für kleine und dem grösseren für grosse Muskelgruppen. Daraus werden zwei Stufen, zugeordnet über das bestehende `MuscleGroup`:

| Stufe | `MuscleGroup` | Obergrenze |
|---|---|---|
| Gross | `legs`, `back`, `chest` | **+10 %** |
| Klein | `shoulders`, `arms`, `core`, `other` | **+5 %** |

`other` ist bewusst in der kleinen Stufe: Was die Titel-Heuristik nicht erkennt, bekommt die vorsichtigere Grenze, nicht die grosszügigere. Mehr als zwei Stufen gibt die Grundlage nicht her — eine dritte Stufe wäre eine Zahl ohne Begründung.

**2. Die Untergrenze ist ein Geräte-Schritt, nicht ein Prozentwert.** Der Korridor beginnt bei 2 %, aber diese Kante wird **nicht** erzwungen: Ein einzelner Schritt ist immer eine zulässige Steigerung. Wer bei 200 kg Kreuzheben 202.5 kg vorschlägt, liegt unter 2 % und trotzdem richtig — die kleinste mögliche Steigerung zu verbieten, wäre Geräte-Granularität durch die Hintertür. Die 2 % bleiben im ADR als Herkunftsangabe, nicht als Regel.

**3. Die Spanne wird auf die Granularität der Übung gerundet, und die Granularität bleibt, was #173 und #175 festgelegt haben.**

- Langhantelübung (`AnalysisPromptBuilder.isBarbell(title:)`): Schritt 2.5 kg (`minimumStepKg`).
- Jede andere Übung: der kleinste gelistete Schritt (`ListedExercise.smallestStepKg`).
- Keine Langhantel und kein gelisteter Schritt: **keine Gewichtsprogression**, wie bisher — dort sind Wiederholungen der Hebel (#234).

Die genannte Spanne reicht vom Arbeitsgewicht **plus einem Schritt** bis zum grössten Vielfachen des Schritts, das die Obergrenze nicht überschreitet. Beispiele:

| Übung | Gruppe | Arbeitsgewicht | Schritt | Obergrenze | Spanne im Prompt |
|---|---|---|---|---|---|
| Bench Press (Barbell) | chest, gross | 60 kg | 2.5 kg | 66 kg | 62.5–65 kg |
| Squat (Barbell) | legs, gross | 100 kg | 2.5 kg | 110 kg | 102.5–110 kg |
| Lateral Raise (Dumbbell) | shoulders, klein | 10 kg | 2 kg (gelistet) | 10.5 kg | 12 kg |
| Bicep Curl (Cable) | arms, klein | 25 kg | — (keiner gelistet) | — | keine, Reps |

Die dritte Zeile zeigt den Normalfall bei leichten Übungen: Die Obergrenze liegt unter einem Schritt, also gilt Entscheidung 2 und die Spanne ist genau ein Schritt — dasselbe Ergebnis wie heute. Das Band lockert nur dort, wo ein Arbeitsgewicht mehrere Schritte trägt.

**4. Die Trainingserfahrung (US-13, `TrainingExperience`) ist kein Modifikator — weder primär noch sekundär.** Drei Gründe:

- Die Grundlage differenziert das Prozentband nach Muskelgrösse. Nach Trainingsstand differenziert sie das *Wiederholungsspektrum* (Einsteiger 8–12 RM, Fortgeschrittene periodisiert 1–12 RM), nicht den Prozentsatz. Eine Spreizung des Bands nach Erfahrung hätte keine Quelle.
- `TrainingExperience` ist eine dreistufige Selbstauskunft in Jahren. Die individuelle Trainingsantwort auf dieselbe Belastung streut enorm; drei Stufen tragen keine Personalisierung, die diesen Namen verdient. Sie einzubauen, würde eine Präzision behaupten, die die Variable nicht hat.
- Das Band ist ohnehin konditional (Entscheidung 5). Wer schneller vorankommt, erfüllt die Bedingung öfter und steigert öfter — die Anpassung an den Trainingsstand passiert über die Bedingung, nicht über den Prozentsatz.

Die Erfahrung bleibt im Prompt-Abschnitt «Profile», wo sie heute steht, und darf die Formulierung der Empfehlung färben. Die Zahlen berührt sie nicht.

**5. Das Band ist konditional: die 2-for-2-Regel entscheidet, ob überhaupt eine Gewichtsprogression angeboten wird.** Eine Steigerung wird nur vorgeschlagen, wenn der User das **Zielrepertoire** der Übung in den **zwei letzten Einheiten** dieser Übung um **mindestens 2 Wiederholungen** überschritten hat — massgeblich ist jeweils der letzte Arbeitssatz der Einheit, Warmup-Sätze zählen nicht.

- **Das Ziel** ist die obere Kante des Wiederholungsbereichs der Hevy-Routine, gegen die das Workout geloggt wurde (`rep_range.end`), mit der Fallback-Kette `rep_range.end` → `rep_range.start` → `reps` → **kein Ziel** (#240). Es wird beim Sync gesnapshottet, weil Routinen nachträglich veränderbar sind.
- **Zwei Einheiten** heisst die zwei jüngsten Sessions im Fenster, in denen die Übung vorkommt — nicht die zwei jüngsten Kalendertage. Liegt nur eine Session im Fenster, ist die Bedingung nicht erfüllt.
- **Mindestens 2** und nicht 1: die Regel ist so formuliert, wie ihre Quelle sie formuliert. Eine einzelne Extra-Wiederholung ist Tagesform; zwei in zwei aufeinanderfolgenden Einheiten sind eine Reserve.

**6. Fehlt das Ziel, ist die Bedingung nicht prüfbar — nicht erfüllt.** Ein Workout ohne `routine_id`, eine Routine ohne `rep_range` und ohne `reps`, eine Übung, die in der Routine nicht vorkommt: In allen Fällen gibt es **keine Gewichtsprogression**. Die Karte fällt auf Rep-Progression (#234) oder eine Notiz zurück, und der Prompt sagt dem Modell, dass für diese Übung kein Ziel vorliegt, statt eine Spanne zu nennen. «Nicht prüfbar» als «erfüllt» zu lesen, würde die Bedingung für jeden frei loggenden User aushebeln — und das ist der häufigste Fall.

**7. Herkunft.** Der Korridor 2–10 %, die Staffelung nach Muskelgrösse und die 2-for-2-Regel stammen aus dem ACSM Position Stand «Progression Models in Resistance Training for Healthy Adults» (Medicine & Science in Sports & Exercise 41(3), 2009). Von uns **gesetzt** sind: der Schnitt bei 5 % für kleine Gruppen (die Quelle nennt den Korridor, keine Zwischenstufe), die Zuordnung von `core` und `other` zur kleinen Stufe, die Entscheidung, die 2-%-Kante nicht zu erzwingen, und «der letzte Arbeitssatz» als Satz, der für die 2-for-2-Regel zählt. Der Geräte-Schritt als Granularität stammt aus #173/#175. Nichts davon ist an FitBuddy-Nutzern validiert, und weder Prompt noch UI dürfen das behaupten.

**8. Worauf das Band nicht beruht.** Nicht auf Geräte-Granularität — die bestimmt nur die Rundung, nicht die Grenze. Nicht auf Kraftstandards, Populationsnormen, Körpergewicht, Geschlecht oder Alter — Regel 2 des System-Prompts verbietet dem Modell genau das, und die App darf sich nicht erlauben, was sie dem Modell verbietet. Nicht auf der Erfahrungsstufe (Entscheidung 4). Und nicht auf der Datenlage eines anderen Users: Die Spanne wird pro Übung aus dem eigenen Arbeitsgewicht berechnet, nichts sonst fliesst ein.

---

## Konsequenzen

### + Positiv

- **Die Ablehnungsrate sinkt.** 100 → 105 kg auf der Kniebeuge ist keine Notiz mehr, sondern eine Progression. Der Validator verwirft nur noch, was ausserhalb einer begründeten Spanne liegt — das ist die Regel, die #224 fehlte.
- **Die Empfehlung ist konditional.** Kein Steigerungsvorschlag mehr, nur weil ein Arbeitsgewicht existiert. Wer sein Ziel nicht erreicht hat, bekommt keine höhere Last vorgeschlagen — das ist der grössere fachliche Gewinn gegenüber dem Band selbst.
- **Eine Achse, die die Daten hergeben.** `MuscleGroup` liegt an jeder Übungszeile an; kein neues Feld, keine neue Frage im Onboarding.
- **Die Herkunft ist an einer Stelle festgehalten** und die Grenzen zwischen «aus der Quelle» und «von uns gesetzt» sind benannt. #232 und #233 verweisen hierher, statt Zahlen zu wiederholen.
- **Leichte Übungen verhalten sich wie heute.** Wo die Obergrenze unter einem Schritt liegt, ist die Spanne ein Schritt — kein Verhalten ändert sich, das bisher richtig war.

### – Negativ

- **Frei loggende User verlieren Gewichtsprogressions-Karten.** Ohne Routine gibt es kein Ziel, ohne Ziel keine 2-for-2-Prüfung, ohne Prüfung keine Gewichtssteigerung. Das ist beabsichtigt, wird aber als weniger Empfehlung wahrgenommen. Rep-Progression (#234) und eine ehrliche Notiz («kein Ziel hinterlegt») fangen es auf; die Notiz muss dem User sagen, *warum*.
- **Mehr Latitude fürs Modell heisst mehr Verantwortung beim Validator.** Bisher gab es genau einen richtigen Wert; jetzt gibt es mehrere. Ob das Modell innerhalb der Spanne sinnvoll wählt, ist nur über die Protokollierung aus #228 messbar.
- **Das Band hängt an der Titel-Heuristik.** Eine falsch klassifizierte Übung bekommt die falsche Stufe. Der Schaden ist begrenzt — beide Stufen liegen im Korridor —, aber ein `Hamstring Curl`, der als Arme gelesen würde, bekäme 5 % statt 10 %.
- **Die Bedingung braucht Hevy-Routinen.** Sie ist nur für Hevy-Workouts prüfbar; Strava und Polar liefern keine Sätze und sind nicht betroffen. Eine nachträglich geänderte Routine wird erst beim nächsten Sync als neues Ziel gesnapshottet — bis dahin wird gegen das alte geprüft, was für vergangene Sessions das richtige Verhalten ist.
- **Zwei Regeln statt einer im Prompt.** Regel 6 muss Spanne und Bedingung transportieren (#232); ein längerer Prompt kostet Token-Budget (TD-1, #187).
- **Das Band ist nicht validiert** und darf nirgends so genannt werden. Sollte sich später zeigen, dass 10 % für Anfänger auf der Kniebeuge zu viel ist, wird die Obergrenze hier revidiert, nicht im Code ad hoc gesenkt.

---

## Offene Punkte

| Frage | Priorität | Fällig |
|---|---|---|
| Rep-Progression als eigene Kartenvariante, damit «kein Ziel» und «Ziel nicht erreicht» eine Empfehlung tragen (#234) | Hoch | v1 |
| Trefferquote des Modells innerhalb der Spanne, gemessen über die Protokollierung aus #228 | Mittel | v1 |
| Ob `MuscleGroup` irgendwann aus `GET /v1/exercise_templates` statt aus dem Titel kommt — würde die Stufe verlässlicher machen | Niedrig | v1 |
