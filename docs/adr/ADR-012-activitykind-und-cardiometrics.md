# ADR-012: `ActivityKind` und `CardioMetrics` — normalisierte Sportart und ein Kennzahlen-Block für alle Quellen

**Status:** Accepted
**Datum:** 2026-09-18
**Treiber-QA:** Maintainability (QA-3), Reliability (QA-2)

---

## Kontext

Mit Hevy (#34), Strava ([ADR-010](ADR-010-strava-oauth-byo-app.md)) und Polar ([ADR-011](ADR-011-polar-als-dritte-quelle.md)) stehen drei Quellen hinter dem `FitnessConnector`-Protocol ([ADR-006](ADR-006-fitness-connector-protocol.md)). US-15 (#171) verlangt eine quellenübergreifende Analyse über Kraft **und** Ausdauer. Drei Punkte stehen dem im Weg:

1. **Die Sportart ist Freitext.** Strava liefert `sport_type` (`TrailRun`, `GravelRide`), Polar `sport` / `detailed_sport_info` (`TREADMILL_RUNNING`). Beides landete bisher nur im Session-Titel. Prompt-Builder und Karten müssten die Domäne aus dem Titel raten — derselbe Fehlermodus wie die Muskelgruppen-Heuristik.
2. **Zwei konkurrierende Kennzahlen-Blöcke.** [ADR-011](ADR-011-polar-als-dritte-quelle.md) führte `ActivityMetrics` ein, ausschliesslich von Polar befüllt. Der Strava-DTO warf seinerseits alles ausser Distanz und Bewegungszeit weg, obwohl die API `average_heartrate`, `total_elevation_gain`, `average_speed`, `kilojoules` und den Relative-Effort-Score mitliefert. Ein zweiter Block für Strava hätte die Herzfrequenz an zwei Stellen geführt — und die Frage «welchen liest der Prompt?» pro Quelle beantwortbar gemacht.
3. **Nichts davon wird persistiert.** `ActivityMetrics` war ein offener Punkt aus [ADR-011](ADR-011-polar-als-dritte-quelle.md): Das SwiftData-Schema kennt die Ausdauer-Kennzahlen nicht, der Cache verliert sie bei jedem Sync.

---

## Entscheidung

**1. `ActivityKind` als normalisierte Sportart.** `enum ActivityKind: String` mit `strength`, `run`, `ride`, `swim`, `hike`, `walk`, `other`. Bewusst grob: benannt werden die Domänen, über die die Analyse urteilt, nicht jede Sportart, die ein Provider kennt. `Activity.kind` hat den Default `.strength` — das ist jeder Hevy-Workout, ohne dass ein Mapping es sagen müsste.

Jede Quelle übersetzt ihr eigenes Vokabular an **genau einer Stelle**, im jeweiligen DTO:

- Strava über das **Suffix** des kleingeschriebenen `sport_type` (`run`, `ride`, `swim`, `hike`, `walk`), weil die feinere Klassifikation aus der groben zusammengesetzt ist: `TrailRun`, `EMountainBikeRide`. Eine Sportart, die Strava später ergänzt, bleibt damit klassifiziert, statt bis zur nächsten Tabellenerweiterung in `.other` zu fallen. `WeightTraining` und `Crossfit` sind Kraft; `Workout` ist Stravas Sammelposten (Mobility, Stretching, ein Kurs) und bleibt `.other`.
- Polar über einen **Teilstring** des grossgeschriebenen Labels, weil die Disziplin dort am Ende (`TREADMILL_RUNNING`) oder am Anfang (`RUNNING_INDOOR`) steht. Zuerst wird `detailed_sport_info` gefragt, bei `.other` zusätzlich das gröbere `sport` — Polar erweitert das detaillierte Label laufend, und ein unbekanntes `FUNCTIONAL_TRAINING` darf ein `sport: STRENGTH_TRAINING` nicht aus der Kraft-Domäne werfen.

Unbekannt heisst immer `.other`, nie eine falsche Vermutung. Auch das Decoding ist entsprechend tolerant: Ein Rohwert, den erst ein neuerer Build kennt, liest als `.other`, statt die ganze `Activity` scheitern zu lassen.

**2. `CardioMetrics` ersetzt `ActivityMetrics`.** Ein Block für alle Quellen, jedes Feld optional: `averageHeartRate`, `maxHeartRate`, `elevationGainMeters`, `averageSpeedMetersPerSecond`, `energyKilojoules`, `perceivedEffort` sowie die aus [ADR-011](ADR-011-polar-als-dritte-quelle.md) übernommenen `activeCalories`, `distanceMeters`, `durationSeconds` und `trainingLoad`. `Activity.metrics` heisst neu `Activity.cardio`.

Der Block bleibt ein eigener optionaler Typ statt loser Felder: Ein Hevy-Workout lässt ihn ganz `nil`, und «gibt es hier Ausdauer-Daten?» ist eine Prüfung statt zehn. Ist keine einzige Kennzahl erfasst, wird `nil` statt eines leeren Blocks ausgeliefert.

Distanz und Dauer bleiben bei Hevy und Strava auf dem `ActivityExerciseSet`, wo das Dashboard sie bereits aggregiert; nur Polar, das keine Sets liefert, führt sie im Block. `averageSpeedMetersPerSecond` wird für Polar aus beiden Werten abgeleitet. Eine `0` gilt bei Strava durchgehend als «nicht erfasst» — die API sendet sie auch für das, was sie nie gemessen hat.

**3. Schema V5 persistiert beides.** `Workout` erhält `kindRawValue` und zehn flache Cardio-Spalten; `Activity+Workout` und `WorkoutSummary` reichen sie durch. Damit ist der offene Punkt «SwiftData-Persistenz von `Activity.metrics`» aus [ADR-011](ADR-011-polar-als-dritte-quelle.md) erledigt.

`kindRawValue` ist **optional**, nicht defaultet. Ein vor V5 geschriebener Store enthält auch Strava- und Polar-Sessions; ein Default `strength` würde einen gecachten Lauf in der falschen Domäne einsortieren. `Workout.kind` löst eine fehlende Sportart stattdessen über die Quelle auf: Hevy → `.strength`, eine Ausdauer-Quelle → `.other`, denn welche Disziplin es war, ist genau das, was nicht erfasst wurde. Der nächste Sync ersetzt das Fenster und füllt die Spalte real.

**4. Die Sportart entscheidet, was Ausdauer ist.** `WorkoutSummary.isCardio` liest neu `kind`, wo dieser gemappt wurde. Die alte Heuristik («kein Gewicht bewegt, aber Distanz oder Zeit erfasst») bleibt nur Rückfall für `.other` — also für Zeilen vor V5 — und für Hevy, wo `.strength` der Modell-Default und keine Klassifikation ist, sodass eine Laufband-Session dort weiterhin als Ausdauer liest.

---

## Konsequenzen

### + Positiv

- **Prompt und Karten raten nicht mehr.** Die Domäne einer Session ist ein Enum-Wert, kein Titel-Substring. US-15 AC2 und AC5 (Kraft-, Ausdauer- und Wochenstruktur-Sektionen, Ausdauer-Einheiten) bauen darauf auf.
- **Ein Block statt zwei.** Der Prompt-Builder liest dieselben Felder, gleich welche Quelle geschrieben hat.
- **Strava-Kennzahlen gehen nicht mehr verloren** — Puls, Höhenmeter, Tempo, Relative Effort landen im Cache.
- **Polar-Sessions zeigen endlich Distanz und Dauer**, weil `WorkoutSummary` auf den Cardio-Block zurückfällt, wenn keine Sets vorliegen.
- **Die Migration ist verlustfrei und leichtgewichtig:** V4 → V5 fügt nur optionale Spalten hinzu.

### – Negativ

- **`ActivityMetrics` und `Activity.metrics` entfallen ersatzlos** — jede Stelle, die sie las, wandert auf `cardio`. Innerhalb des PoC ist das genau der Polar-DTO.
- **Das rohe `sport`-Label wird nicht mehr mitgeführt.** `kind` ersetzt es; der Session-Titel nutzt weiterhin `detailed_sport_info`. Wer später die Feinsportart braucht (`GravelRide` vs. `Ride`), muss sie neu aufnehmen.
- **`.other` ist mehrdeutig:** «diese Sportart kennen wir nicht» und «diese Zeile stammt von vor V5» lesen gleich. Für die Analyse ist beides gleich zu behandeln, für eine spätere Statistik nicht.
- **`perceivedEffort` und `trainingLoad` sind providerspezifisch skaliert** — Stravas Relative Effort ist nicht Polars Training Load. Nur als Trend innerhalb einer Quelle interpretierbar, nie als quellenübergreifender Absolutwert.
- **Zehn flache Spalten** statt eines verschachtelten Typs, weil SwiftData Skalare speichert. Gelesen und geschrieben werden sie nur über `Workout.cardio`.
- **V5 darf nur wachsen, bis es `develop` erreicht.** Danach ist die nächste Änderung V6 — ein Store, der von einem anderen V5 geschrieben wurde, gilt sonst als «unknown model version».

---

## Offene Punkte

| Frage | Priorität | Fällig |
|---|---|---|
| Mock-Profile mit Cardio- und gemischten Daten (#188) — heute sind alle Fixtures Hevy-Payloads | Mittel | v0 |
| Feinsportart (`GravelRide` vs. `Ride`) für die Anzeige, falls die Karten sie brauchen | Niedrig | v1 |
| Ausdauer-spezifische Kennzahlen in der Detailansicht (Puls, Höhenmeter) | Mittel | v1 |
