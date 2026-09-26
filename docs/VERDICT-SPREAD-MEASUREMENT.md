# Messung: Streuung des Verdicts vor und nach US-16

> **Status:** Gemessen am 26.09.2026 (#229). Sub-Issue von #224 (US-16), AC5.

Diese Notiz hält fest, was nach #226, #227 und #228 bei gleicher Datenlage noch schwankt und was stabil ist. Sie ist eine Messung von Hand mit echten API-Calls, kein automatisierter Test: Die Läufe kosten Geld (BYO-Key) und hängen von der Verfügbarkeit der Provider ab.

## Erwartung

| Grösse | Vorher (bis #227) | Nachher (US-16) |
|---|---|---|
| Verdict | Wahl des Modells, streut (19.09.2026: drei Läufe, drei Verdicts) | Aus den Kennzahlen der App ([ADR-014](adr/ADR-014-verdict-regel-der-app.md)) — muss bei gleichem Cache **identisch** sein (AC1) |
| Headline, Kurzfazit, Kartentexte | Modelltext | Modelltext, darf schwanken (AC1) |
| Kartentypen, gewählte Übung | Modellwahl | Modellwahl, Validator prüft die Zahlen |
| Eingriffe des Validators | nicht sichtbar | im Protokoll (#228), Debug-Ansicht in den Settings |

## Aufbau

- **Build:** Debug-Build — das Protokoll aus #228 und die Mock-Daten gibt es nur dort.
  - *Vorher:* `develop` vor dem Merge von US-16.
  - *Nachher:* Spitze des US-16-Stapels (#239 → #226 → #227 → #228 → Doku).
- **Daten:** Mock-Profil per Launch-Argument `-fbSeedMockData <profil>`, Cache zwischen den Läufen unverändert (kein Sync).
  - `person-a` — das Profil des Befunds vom 19.09.2026 (fünf Trainingstage pro Woche).
  - `plateau` — liegt nach ADR-014 auf `hold` (Stufe 3). *In dieser Messung nicht gelaufen*, siehe unten.
- **Analyse-Profil:** jeweils dasselbe (Standard des Mock-Profils), in der Tabelle vermerkt.
- **Provider:** Claude (`claude-opus-5`), Mistral (`mistral-medium-3-5`), Gemini (`gemini-3.6-flash`). Jeder Provider einzeln — der gemessene Provider steht in *Settings → AI Providers* zuoberst; Läufe mit Fallback-Hinweis zählen nicht.
- **Läufe:** mindestens drei pro erreichbarem Provider und Mock-Profil, vorher und nachher.
- **Festhalten pro Lauf:** Verdict der App, Verdict des Modells (Protokoll: «Modell → App»), Kartentypen in Reihenfolge, Eingriffe des Validators (Gegenstand · Grund).

Nicht erreichbare Provider werden als solche vermerkt (Datum, HTTP-Status), nicht weggelassen.

## Ergebnisse

Simulator iPhone 17 Pro, Debug-Build, `-fbStubHevy accepts -fbSeedMockData person-a`, Analyse-Profil Standard. Vorher: `develop` @ `8aa3945`. Nachher: US-16-Stapel @ `608123a`.

### `person-a` — angezeigtes Verdict pro Lauf

| Provider | Stand | Lauf 1 | Lauf 2 | Lauf 3 |
|---|---|---|---|---|
| Claude | vorher | `hold` · nur Textkarten | `hold` · nur Textkarten | `hold` |
| Claude | nachher | `progress` | `progress` · Rep-Karten | `progress` · keine Karten |
| Mistral | vorher | `recover` · Imbalance-Karte | `recover` · Karten mit mehr Wiederholungen | `recover` · nur Textkarten |
| Mistral | nachher | `progress` · Imbalance-Karten | `progress` · Imbalance-Karten | `progress` · Karten mit mehr Wiederholungen |

**Vorher ist das angezeigte Verdict nicht das Verdict des Modells.** Auf `develop` stufte die App ein `progress` des Modells auf `hold` zurück, sobald keine Progression-Karte die Prüfung überstand (#177). Der Prompt ist zwischen vorher und nachher inhaltlich gleich (#227 hat dort nur intern umgebaut). Die drei `hold` bei Claude sind deshalb sehr wahrscheinlich diese Rückstufung und keine Wahl des Modells. Ein Protokoll, das das belegen würde, gibt es vorher nicht.

### Protokoll der Eingriffe (nachher, 6 Läufe)

Gesamtzählung aus *Settings → DEVELOPER → Validation log*:

| Grösse | Anzahl |
|---|---|
| Analysen mit Protokoll | 6 |
| Unverändert übernommen | 2 |
| Verdict überschrieben (Modell ≠ App) | 2 |
| Analysen ohne Protokoll (die Vorher-Läufe) | 6 |

| Eingriff | Anzahl |
|---|---|
| `imbalance` verworfen: `unknownMuscleGroup` | 4 |
| `verdict` / `headline` / `lead` ersetzt: `verdictOverridden` | je 2 |
| `lead` ersetzt: `noBackingCard` | 2 |
| `recovery` verworfen: `recoveryNotNeeded` | 2 |
| `interference` verworfen: `blankText` | 1 |
| `note` verworfen: `overCardLimit` | 1 |

Die Verteilung auf die Provider ist nur aus der Einzelliste pro Analyse abzulesen, die Gesamtzählung trennt nicht nach Provider. Zwei verworfene `recovery`-Karten zusammen mit zwei überschriebenen Verdicts passen zu zwei Mistral-Läufen, in denen das Modell weiterhin `recover` wählte.

### Nicht gemessen

| Was | Grund |
|---|---|
| Gemini | Im Simulator kein Key hinterlegt. Beim Live-Test am 26.09.2026 (#226) antwortete `gemini-3.6-flash` mit HTTP 503 (Überlast). |
| Mock-Profil `plateau` | Nicht gelaufen. Die Stufe 3 (`hold` bei Plateau-Mehrheit) ist durch Unit-Tests abgedeckt (`AnalysisMockProfileTests`), live nicht bestätigt. |

## Auswertung

**Stabil (AC1 erfüllt):** Nachher liefert jeder der sechs Läufe dasselbe Verdict, `progress`. Das gilt innerhalb eines Providers und sogar **über die Provider hinweg**. Vorher war das Verdict innerhalb eines Providers zwar gleich, zwischen den Providern aber verschieden (Claude `hold`, Mistral `recover`). Welches Verdict der Nutzer sah, hing also davon ab, welcher Provider zuoberst stand.

**Schwankt weiterhin, wie erlaubt:** Kartenwahl (Rep-Karten, Imbalance-Karten, keine Karten) und Formulierung.

**Wie oft das Modell danebenlag:** In 2 von 6 Läufen wählte das Modell ein anderes Verdict als die App. In 4 von 6 Läufen schlug es eine Imbalance-Karte für eine Muskelgruppe vor, die die App nicht kennt.

**Stabil heisst nicht fachlich richtig.** `person-a` trainiert an fünf Tagen pro Woche mit steigendem Volumen. Der Befund vom 19.09.2026 hielt `recover` für die vertretbarste Empfehlung, und Mistral wählt es weiterhin. Die App-Regel kommt auf `progress`, weil mindestens eine Übung ihre Fenster-Bestleistung in der jüngsten Session setzt (Stufe 4) und fünf Trainingstage unter der Ruhetag-Schwelle von sechs liegen (Stufe 0). Das ist die in [ADR-014](adr/ADR-014-verdict-regel-der-app.md) benannte Konsequenz: Vor US-18 (#241, #246) gibt es kein belastungsbasiertes `recover`. US-16 macht das Verdict reproduzierbar, nicht belastungsgerecht.

**Folgepunkte:**
- `imbalance: unknownMuscleGroup` in 4 von 6 Läufen: Das Modell nennt Muskelgruppen, die die App nicht zuordnen kann. Prompt oder Zuordnung prüfen; eigenes Issue.
- Die Gesamtzählung im Debug-Pfad sollte nach Provider trennen, sonst lässt sich die Trefferquote pro Modell nicht ablesen.
- Gemini und `plateau` bei Gelegenheit nachmessen.
