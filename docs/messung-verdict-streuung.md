# Messung: Streuung des Verdicts vor und nach US-16

> **Status:** Vorlage — Messung ausstehend (#229). Sub-Issue von #224 (US-16), AC5.

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
  - `plateau` — liegt nach ADR-014 auf `hold` (Stufe 3); prüft, ob das Modell dort weiterhin `progress` vorschlägt.
- **Analyse-Profil:** jeweils dasselbe (Standard des Mock-Profils), in der Tabelle vermerkt.
- **Provider:** Claude (`claude-opus-5`), Mistral (`mistral-medium-3-5`), Gemini (`gemini-3.6-flash`). Jeder Provider einzeln — die übrigen Keys für die Messung entfernen, sonst greift die Fallback-Kette und verschleiert, wer geantwortet hat.
- **Läufe:** mindestens drei pro erreichbarem Provider und Mock-Profil, vorher und nachher.
- **Festhalten pro Lauf:** Verdict der App, Verdict des Modells (Protokoll: «Modell → App»), Kartentypen in Reihenfolge, Eingriffe des Validators (Gegenstand · Grund).

Nicht erreichbare Provider werden als solche vermerkt (Datum, HTTP-Status), nicht weggelassen.

## Ergebnisse

### `person-a`

| Provider | Stand | Lauf | Verdict App | Verdict Modell | Karten | Eingriffe |
|---|---|---|---|---|---|---|
| Claude | vorher | 1 | — | | | — |
| Claude | vorher | 2 | — | | | — |
| Claude | vorher | 3 | — | | | — |
| Claude | nachher | 1 | | | | |
| Claude | nachher | 2 | | | | |
| Claude | nachher | 3 | | | | |
| Mistral | vorher | 1 | — | | | — |
| Mistral | vorher | 2 | — | | | — |
| Mistral | vorher | 3 | — | | | — |
| Mistral | nachher | 1 | | | | |
| Mistral | nachher | 2 | | | | |
| Mistral | nachher | 3 | | | | |
| Gemini | vorher | 1 | — | | | — |
| Gemini | vorher | 2 | — | | | — |
| Gemini | vorher | 3 | — | | | — |
| Gemini | nachher | 1 | | | | |
| Gemini | nachher | 2 | | | | |
| Gemini | nachher | 3 | | | | |

*Vorher* gibt es weder ein App-Verdict noch ein Protokoll; die Spalte «Verdict Modell» ist dort das angezeigte Verdict.

### `plateau`

| Provider | Stand | Lauf | Verdict App | Verdict Modell | Karten | Eingriffe |
|---|---|---|---|---|---|---|
| Claude | nachher | 1 | | | | |
| Claude | nachher | 2 | | | | |
| Claude | nachher | 3 | | | | |
| Mistral | nachher | 1 | | | | |
| Mistral | nachher | 2 | | | | |
| Mistral | nachher | 3 | | | | |
| Gemini | nachher | 1 | | | | |
| Gemini | nachher | 2 | | | | |
| Gemini | nachher | 3 | | | | |

## Auswertung

*Folgt nach der Messung:* Was ist stabil, was schwankt noch; Trefferquote des Modells (Anteil Läufe mit «Modell = App», häufigste Eingriffsgründe aus der Gesamtzählung der Debug-Ansicht); nicht erreichbare Provider.
