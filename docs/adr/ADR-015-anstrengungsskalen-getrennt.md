# ADR-015: Anstrengungsskalen getrennt halten — Verrechnungsverbot, Benennung im Prompt und was in v0 nicht geholt wird

**Status:** Accepted
**Datum:** 2026-09-26
**Treiber-QA:** Reliability (QA-2), Maintainability (QA-3)

---

## Kontext

US-18 (#241) soll die Anstrengung in die Analyse bringen. Die Verdict-Regel aus [ADR-014](ADR-014-verdict-regel-der-app.md) stützt sich heute auf Trainingstage und e1RM-Verläufe — beides sagt nichts darüber, wie hart eine Einheit war. Die Anstrengungswerte liegen teilweise schon im Cache, werden aber nirgends gelesen (`CardioMetrics.perceivedEffort`, `CardioMetrics.trainingLoad`), oder sie werden noch gar nicht dekodiert (Polar `training_load_pro`, Strava `perceived_exertion`).

Bevor diese Werte in Prompt (#245) und Verdict-Regel (#246) wandern, muss feststehen, was mit ihnen **nicht** passieren darf. Die Quellen liefern vier verschiedene Arten von Zahlen:

| Quelle | Wert | Art | Verankert an |
|---|---|---|---|
| Hevy | RPE 1–10 pro Satz | subjektiv | Selbsteinschätzung |
| Strava | Relative Effort (`suffer_score`) | objektiv, HF-basiert | persönliche HF-Zonen, Strava-eigene Formel ohne Offenlegung |
| Polar | Cardio Load (`cardio-load`) | objektiv, TRIMP | Ruhe-HF, Max-HF, Dauer, Polar-eigene Kalibrierung |
| Polar | Perceived Load (`perceived-load`) / `user-rpe` | subjektiv | Selbsteinschätzung; `user-rpe` als 10-stufiges Enum |

Dazu kommen Polars Muscle Load (`muscle-load`, ebenfalls in `training_load_pro`) und das Legacy-Feld `training_load` der Exercise-Ressource, das `CardioMetrics.trainingLoad` heute hält.

Zwischen diesen Skalen gibt es **keine dokumentierte Umrechnung**. Das stärkste Argument liefert Polar selbst: Es führt `cardio-load` und `perceived-load` als zwei getrennte Zahlen mit je eigener Interpretation — der Hersteller, der beide berechnet, verschmilzt sie bewusst nicht. Strava veröffentlicht keine Brücke zwischen `suffer_score` und `perceived_exertion`; beide sind dort alternative Eingänge in dieselbe Auswertung, keine ineinander umrechenbaren Grössen. Und Hevy ist Krafttraining — eine herzfrequenzbasierte Last trägt dort fachlich nicht.

Das Feld, das heute Stravas `suffer_score` hält, heisst ausgerechnet `perceivedEffort`. Sobald es im Prompt steht, liest sich «perceived effort: 82» wie eine RPE-Angabe, die um den Faktor acht danebenliegt.

---

## Entscheidung

### 1. Verrechnungsverbot

Anstrengungswerte werden **nie summiert, nie gemittelt und nie quellenübergreifend verglichen**. Jeder Wert gilt ausschliesslich als **Trend innerhalb seiner eigenen Skala**.

- **Die Einheit ist die Skala, nicht der Anbieter.** Polar Cardio Load und Polar Perceived Load kommen aus derselben Quelle und werden trotzdem nicht zusammengezogen — so wie Polar selbst es nicht tut. Wo [ADR-014](ADR-014-verdict-regel-der-app.md) §3 «je Quelle» sagt, ist in diesem Sinn «je Skala» gemeint; Polar kann also mehrere getrennte Reihen beitragen.
- **Innerhalb einer Skala** ist Aggregation erlaubt, soweit sie die Regel ausdrücklich vorsieht: der Mittelwert der Hevy-RPE über die Sätze einer Woche (`RecoveryMetrics.averageRPE`), das 7-Tage-Mittel gegen das Mittel der Vorwochen in ADR-014 §3.4.
- **Kein Vergleich über Skalen**, auch nicht indirekt: kein «Strava sagt hart, Hevy sagt leicht», keine Rangfolge, keine Normierung auf 0–1, kein Z-Score, kein gemeinsamer «Anstrengungsindex».
- **Keine Umrechnung.** Kein Wert wird auf die Skala eines anderen abgebildet — insbesondere nicht auf Hevys 1–10 (siehe Entscheidung 5).

`CardioMetrics` sagt das im Doc-Kommentar bereits («trend within one source, never as a cross-source absolute»); dieser ADR macht es verbindlich für Prompt, Evidence und Verdict-Regel.

### 2. Benennung im Prompt

Jeder Anstrengungswert steht im Prompt **mit seinem Quell-Label**, nie als nackte Zahl (#241 AC1). Die Labels sind englisch, weil der Prompt englisch ist, und genau diese:

| Label | Wert | Quelle |
|---|---|---|
| `RPE` | RPE pro Satz bzw. dessen Wochenmittel | Hevy |
| `Strava Relative Effort` | `suffer_score` | Strava |
| `Polar Cardio Load` | `training_load_pro.cardio-load` | Polar |
| `Polar Perceived Load` | `training_load_pro.perceived-load` | Polar |
| `Polar Muscle Load` | `training_load_pro.muscle-load` | Polar |
| `Polar RPE` | `training_load_pro.user-rpe`, als Stufenname, nie als Zahl | Polar |

`RPE` ohne Präfix ist Hevy vorbehalten — der Prompt führt es heute schon so («mean RPE» in der Kraft-Sektion), und das bleibt. Weitere Labels für Anstrengung gibt es nicht; ein neues braucht eine Änderung dieses ADR. Das Legacy-Feld `training_load` erhält **kein** Label und geht in v0 nicht in den Prompt — insbesondere wird es nicht als «Polar Cardio Load» ausgegeben, wenn `cardio-load` fehlt, solange nicht belegt ist, dass beide dieselbe Grösse sind.

**Fehlende Werte werden weggelassen** — nie als `0`, nie als «—», nie als Platzhalter. Dieselbe Regel wie bei `RecoveryMetrics.averageRPE` und bei Regel 7 des System-Prompts («unrecorded, not zero»).

Der System-Prompt erhält eine Regel, die das Verrechnungsverbot dem Modell gegenüber ausspricht: Werte verschiedener Labels sind nicht vergleichbar und werden nicht addiert, gemittelt oder gegeneinander gestellt. Sie ergänzt Regel 7, die bereits verbietet, Ausdauer in Kilogramm umzurechnen. Den Wortlaut legt #245 fest.

### 3. Strava `perceived_exertion` wird in v0 nicht geholt

`perceived_exertion` ist die einzige Strava-Zahl auf derselben nominalen 1–10-Skala wie Hevy-RPE. Sie wird trotzdem **nicht** geholt.

- Sie steht nur auf `GET /activities/{id}`, nicht auf `GET /athlete/activities`, die der Connector heute abfragt. Das wäre **ein zusätzlicher Request pro Aktivität** gegen ein API mit Standardlimits pro 15 Minuten und pro Tag — im BYO-App-Modell ([ADR-010](ADR-010-strava-oauth-byo-app.md)) auf dem Kontingent der App des Nutzers, das auch der normale Sync braucht.
- Der Wert ist eine **User-Eingabe** in der Strava-App und in der Praxis oft leer. Die Kosten fallen für jede Aktivität an, der Nutzen nur für die wenigen, bei denen jemand etwas eingetragen hat.
- Auch geholt, bliebe sie eine eigene Skala: «nominal 1–10» heisst nicht «dieselbe Zahl wie Hevy-RPE». Sie würde nicht mit Hevy-RPE verrechnet (Entscheidung 1), der Gewinn wäre also nur eine weitere, meist leere Strava-Reihe.

**In v1 neu bewerten**, etwa mit Detail-Abruf nur für neue Aktivitäten und Cache.

### 4. Polars Tages-Ressource `/v3/users/cardio-load` wird in v0 nicht genutzt

Die Ressource liefert `strain` (7-Tage-Schnitt), `tolerance` (28-Tage-Schnitt) und einen fertigen `cardio_load_status` (u.a. `OVERREACHING`, `PRODUCTIVE`, `DETRAINING`). Sie wird **nicht** genutzt.

- **Eigener Endpoint**, eigene Abfrage, eigene Persistenz — zusätzlicher Umfang für eine Quelle, die nur einen Teil der Nutzer betrifft.
- **Nur Polar.** Die Aussage deckt ausschliesslich Polar-Sessions ab; Hevy und Strava fliessen nicht ein. Als Tagesaussage über «die Belastung» würde sie ein quellenübergreifendes Urteil vortäuschen, das sie nicht ist.
- **Ein fertiges Urteil des Herstellers umginge die Regel der App.** `cardio_load_status` ist genau die Aussage, die das Verdict treffen will — aber von Polar gerechnet, nach einem Modell, das die App nicht einsehen kann. Das widerspricht [ADR-014](ADR-014-verdict-regel-der-app.md) (Verdict aus eigenen, belegbaren Kennzahlen; §8: kein veröffentlichtes Belastungsmodell, Polars `cardio_load_status` wird nicht übernommen) sowie Regel 2 (kein Massstab von aussen) und Regel 7 (keine abgeleiteten Zonen und Normen) des System-Prompts.

**Als Option für v1 festgehalten** — dann mit der Frage, ob `strain`/`tolerance` als Polar-interne Reihe (nicht der Status) etwas zur eigenen Regel beitragen.

### 5. Polar `user-rpe` bleibt ein Enum ohne Zahl

`user-rpe` wird als **geordnetes Enum** geführt (`RPE_NONE` … `RPE_EXTREME`, mit `unknown`-Fallback für unbekannte Werte), **ohne numerische Zuordnung**. Polar dokumentiert keine; `RPE_BRISK = 5` wäre geraten. Kein Wert wird je auf Hevys 1–10 abgebildet. Belegt sind nur `RPE_NONE`, `RPE_BRISK` und `RPE_EXTREME`; die übrigen Stufennamen sind gegen AccessLink ungeprüft, und ein unbekannter Wert fällt auf `unknown` zurück und wird weggelassen.

Daraus folgt: `Polar RPE` wird nicht gemittelt und fliesst in v0 nicht in die Trendrechnung aus [ADR-014](ADR-014-verdict-regel-der-app.md) §3 ein — ein Mittel über ein Enum ohne Zahlen gibt es nicht. Im Prompt steht der Stufenname pro Session. Soll später doch eine Zahl her, ist das eine Änderung dieses ADR, keine stille Setzung im Code.

### 6. `perceivedEffort` heisst künftig `relativeEffort`

Das Feld, das Stravas `suffer_score` hält, wird von `CardioMetrics.perceivedEffort` in **`relativeEffort`** umbenannt (#243). `suffer_score` ist ein objektiver, aus der Herzfrequenz abgeleiteter Score, keine Selbsteinschätzung. Der Name richtet sich nach Stravas eigener Bezeichnung und nach dem Prompt-Label.

### 7. Risiken, die der Code tragen muss

**Undokumentierte Strava-Felder.** `suffer_score`, `perceived_exertion` und die Herzfrequenzfelder (`average_heartrate`, `max_heartrate`) stehen **nicht** in Stravas offizieller API-Spezifikation. Sie werden geliefert, sind aber nicht zugesichert und können ohne Ankündigung verschwinden. `suffer_score` ist ausserdem berichtet als nur für Abonnenten befüllt — das ist **nicht verifiziert**. `suffer_score` ist zudem `null`, wenn keine Herzfrequenz aufgezeichnet wurde.

**Gerätegebundenes Polar Training Load Pro.** `training_load_pro` liefern nur Uhren, die Training Load Pro unterstützen. Bei älteren Geräten fehlt der Block ganz; dann gibt es höchstens das Legacy-`training_load`.

Für beides gilt:

- **Jedes Anstrengungsfeld ist optional**, im DTO, in `CardioMetrics`, in der Persistenz und in der Evidence.
- **Ein fehlendes Feld ist kein Fehler.** Ein fehlender Block `training_load_pro` bricht das Decoding der Session nicht ab.
- **Eine dauerhaft leere Spalte darf die Analyse nicht ausfallen lassen.** Hat eine Skala nie einen Wert, entfällt sie; die Regel läuft ohne sie weiter (ADR-014 §3 Stufe 5 entfällt, §4 kein Ersatzwert). Der Pfad ohne Anstrengungsdaten ist der Normalfall, nicht der Sonderfall.

### 8. Kein Anspruch auf wissenschaftliche Validierung

Keine der Skalen wird in diesem ADR, im Code oder in der UI als wissenschaftlich validiert bezeichnet. Die App gibt die Werte als das wieder, was sie sind: Zahlen der jeweiligen Quelle, auf deren eigener Skala. Das gilt auch für Formulierungen wie «clinically proven», «validated metric» oder «accurate measure of effort» in UI-Texten und Prompt.

---

## Herkunft

Die Beschreibung der Polar-Werte (`training_load_pro` mit `cardio-load`, `muscle-load`, `perceived-load`, `user-rpe` und den Interpretationsfeldern, die Tages-Ressource `/v3/users/cardio-load` mit `strain`, `tolerance` und `cardio_load_status`) stammt aus der Dokumentation von Polar AccessLink v3; dass Training Load Pro gerätegebunden ist, sagt Polar selbst. Die Aussagen zu Strava beruhen auf der offiziellen API-Referenz (welche Felder auf der Liste bzw. nur auf der Detail-Ressource stehen, Rate-Limits) und auf dem tatsächlichen Antwortverhalten: Die Anstrengungs- und Herzfrequenzfelder kommen in den Responses an, stehen aber nicht im Schema. Die Abo-Bindung von `suffer_score` ist ein Bericht, keine geprüfte Aussage. Zu Hevy gilt, was die API pro Satz liefert: ein optionales RPE-Feld. Die Abwägung selbst — dass Umfang keine Anstrengung misst und die Skalen nicht zusammengehören — kommt aus der Diskussion zu #224 und ist in #241 festgehalten.

---

## Konsequenzen

### + Positiv

- **Keine erfundene Messung.** Es gibt keine Stelle, an der zwei Skalen zu einer Zahl werden, die keine Quelle gemessen hat — weder im Code noch, soweit der Prompt es verhindern kann, im Modelltext.
- **Das Modell sieht die Herkunft jeder Zahl.** Mit festen Labels liest es «Strava Relative Effort 82» und «RPE 7.5» als zwei verschiedene Dinge statt als dieselbe Grösse.
- **Kein zusätzlicher API-Druck.** v0 holt keinen Wert, der einen Request pro Aktivität oder einen neuen Endpoint kostet.
- **Das Verdict bleibt eine Aussage der App.** Kein Hersteller-Urteil wird durchgereicht; [ADR-014](ADR-014-verdict-regel-der-app.md) bleibt die einzige Stelle, an der entschieden wird.
- **Brüche bei Strava oder alte Polar-Uhren kosten Genauigkeit, keine Funktion.**

### – Negativ

- **Strava liefert in v0 keine subjektive Anstrengung.** Wer seine Läufe nur in Strava bewertet, hat für die Regel keine Selbsteinschätzung — nur den HF-basierten Relative Effort, und den nur mit Brustgurt bzw. Uhr-HF.
- **`Polar RPE` trägt nichts zur Trendrechnung bei.** Ohne Zahl gibt es kein Mittel; die Stufe erscheint nur als Text im Prompt.
- **Ältere Polar-Uhren liefern in v0 keine Anstrengung für den Prompt.** Das Legacy-`training_load` bleibt ungenutzt, bis geklärt ist, was es im Verhältnis zu `cardio-load` ist.
- **Mehr Reihen, dünnere Reihen.** Weil jede Skala für sich steht, erreicht jede einzelne die Qualifikationsschwelle aus ADR-014 §3.3 (3 Wochen, letzte 7 Tage) seltener als eine zusammengelegte es täte. Das ist gewollt: eine zusammengelegte Reihe wäre dichter, aber falsch.
- **Die Strava-Felder können jederzeit wegfallen.** Dann entfällt Strava Relative Effort still — der Code trägt das, aber die Analyse wird ohne Hinweis gröber.
- **Die Prompt-Regel ist eine Bitte ans Modell.** Dass es zwei Labels nicht doch im Text vergleicht, kann die App nicht erzwingen; sie kann es nur nicht selbst tun und das Verdict unabhängig vom Modelltext setzen.

### Verhältnis zu ADR-014

[ADR-014](ADR-014-verdict-regel-der-app.md) §3/§4/§5 verweist auf «das Verrechnungsverbot aus #242» — das ist dieser ADR. Die Regel dort ist mit ihm vereinbar, weil sie **nur die Richtung innerhalb einer Skala** liest («steigt diese Reihe gegen sich selbst»), nie ein Niveau und nie einen Vergleich zweier Reihen. Steigt eine Skala, deckelt sie `progress` auf `hold`; die anderen werden nicht dagegen aufgerechnet. Dieser ADR präzisiert nur, dass «je Quelle» dort «je Skala» heisst und dass `Polar RPE` mangels Zahl nicht in diese Rechnung eingeht.

### Was die Folge-Tasks umsetzen müssen

| Task | Muss |
|---|---|
| #243 | `CardioMetrics.perceivedEffort` → `relativeEffort`, Persistenzspalte mitziehen, Doc-Kommentar: objektiver, Strava-spezifischer Score, keine Selbsteinschätzung. Kommentar in `RecoveryMetrics` anpassen: kein Mittel mit RPE bleibt richtig, «wird nicht gelesen» nicht mehr. |
| #244 | `training_load_pro` dekodieren (Bindestrich-Schlüssel innerhalb, Unterstrich aussen), vier Werte optional in `CardioMetrics`, `user-rpe` als Enum mit `unknown`-Fallback und ohne Zahl. Fehlender Block ist kein Fehler, per Test. Legacy-`training_load` bleibt unverändert. |
| #245 | Werte nur mit den Labels aus Entscheidung 2 in den Prompt, fehlende weglassen, Prompt-Regel gegen das Verrechnen ergänzen, kein `training_load` im Prompt. Kein UI- oder Prompt-Text behauptet Validierung. |
| #246 | Evidence führt Anstrengung **je Skala** getrennt, nie ein gemeinsames Feld. Die Regel liest nur die Richtung innerhalb einer Skala (ADR-014 §3), kein Ersatzwert (§4), `Polar RPE` nicht in der Trendrechnung. Der Pfad ohne jede Anstrengung ist getestet. |

---

## Offene Punkte

| Frage | Priorität | Fällig |
|---|---|---|
| Strava `perceived_exertion` über den Detail-Abruf holen — nur für neue Aktivitäten, mit Cache, gegen das Rate-Limit gerechnet | Niedrig | v1 |
| Polar `/v3/users/cardio-load` (`strain`, `tolerance`) als Polar-interne Reihe nutzen, ohne `cardio_load_status` zu übernehmen | Niedrig | v1 |
| Verhältnis von Legacy-`training_load` zu `cardio-load` klären, damit ältere Polar-Uhren eine Anstrengungsreihe beitragen können | Mittel | v1 |
| Ob Strava `suffer_score` tatsächlich nur für Abonnenten befüllt wird — am echten Konto prüfen | Niedrig | mit #245 |
