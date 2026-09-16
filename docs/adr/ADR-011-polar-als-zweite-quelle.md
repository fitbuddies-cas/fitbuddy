# ADR-11: Polar AccessLink als zweite Datenquelle (vor Strava)

**Status:** Accepted
**Datum:** 2026-09-10
**Treiber-QA:** Maintainability (QA-3), Portability

---

## Kontext

US-5 verlangt eine zweite Trainingsdatenquelle neben Hevy. Das `FitnessConnector`-Protocol (ADR-6) ist verankert, `HevyConnector` (#34) und der `StravaConnector`-Stub plus `ConnectorRegistry` (#35) sind auf `develop`. Offen war bisher, **welche** zweite Quelle real angebunden wird — die Weakness `W-6` in `ARCHITECTURE.md` hält das seit Modul 5 fest.

Für die CAS-Präsentation soll die zweite Quelle nicht nur als Stub, sondern als funktionsfähiger Connector vorliegen. Die Wahl steht zwischen Strava und Polar:

| Kriterium | Strava | Polar AccessLink |
|---|---|---|
| OAuth-Flow | Authorization Code **mit Client Secret** | Authorization Code **mit PKCE**, Public Client ohne Secret |
| Backend nötig | Ja — Secret darf nicht in die App | **Nein** — PKCE ersetzt das Secret |
| Passt zu ADR-4 (kein Backend im PoC) | Nein | **Ja** |
| Datenprofil | Ausdauer, GPS, Power, Segmente | Ausdauer, Herzfrequenz, Trainingsload, Kalorien |
| Token | `access` + `refresh`, ~6 h | `access` + `refresh`, ~12 h |

Strava ist ohne Backend strukturell nicht lösbar (`W-6`), Polar dagegen schon. Damit ist Polar die einzige Quelle, die im PoC-Rahmen (ADR-4: kein Server-Tier) tatsächlich implementierbar ist.

Zweite Frage: Polars Ausdauer-Kennzahlen (Ø/Max-Herzfrequenz, Kalorien, Trainingsload) haben im bisherigen `Activity`-Modell keinen Platz. Das Modell ist krafttrainingsgeformt (`exercises → sets` mit `weightKg`/`reps`/`rpe`). Nachtrag Punkt 2 in ADR-6 hat genau diesen additiven Eingriff vorgesehen.

---

## Entscheidung

**1. Polar AccessLink wird die zweite reale Datenquelle.** Strava bleibt als Stub (`StravaConnector`, `.notImplemented`) erhalten, bis ein Backend existiert — dann eigener ADR.

**2. `PolarConnector` implementiert `FitnessConnector` unverändert.** Kein Eingriff in den Protocol-Vertrag. Aufbau analog `HevyConnector`:

- `PolarConnector` (`Core/Connector/data/Polar/`) — reines Provider-I/O, kennt nur HTTP, Token-Lifecycle und die DTO→`Activity`-Abbildung.
- `PolarOAuthClient` — Authorization-URL, Code-Exchange, Refresh. Der interaktive Teil (`ASWebAuthenticationSession`) liegt darüber in einem ViewModel (v1).
- `PolarAccessLinkClient` — `POST /v3/users` (Registrierung, `409` = bereits registriert = ok), `GET /v3/exercises`.
- `PolarPKCE` — Verifier/Challenge (S256, RFC 7636).
- `PolarHTTP` — gemeinsames Fehler-Mapping HTTP-Status → `ConnectorError` (`401/403/400 → unauthorized`, `429 → rateLimited`, `5xx → serviceUnavailable`).

**3. Credential-Handling wie bei Hevy (ADR-6, #34-Nachtrag Punkt 1):** Der Connector hält die Tokens nur im Speicher und refresht einen abgelaufenen Access-Token proaktiv (`freshAccessToken()`, 60 s Leeway). Er schreibt **nicht** in die Keychain — der Keychain-`KeychainKey`-Satz (`polarAccessToken`, `polarRefreshToken`, `polarTokenExpiry`, `polarMemberID`) und das Zurückschreiben nach `currentCredentials()` gehören der Sync-/Onboarding-Schicht.

**4. `Activity` wird additiv um `metrics: ActivityMetrics?` erweitert.** `ActivityMetrics` (`Core/Connector/domain/`) trägt `averageHeartRate`, `maximumHeartRate`, `activeCalories`, `distanceMeters`, `durationSeconds`, `trainingLoad`, `sport` — jedes Feld optional. Ein Hevy-Workout lässt den Block `nil`; ein Polar-Lauf füllt ihn. Dashboard und Prompt-Builder bleiben ohne Änderung gültig.

**5. `ConnectorSource.polar` wird ergänzt.** Damit ist `PolarConnector` über die `ConnectorRegistry` registrier-, validier- und (via `sourcesNeedingRenewal`) für den US-5-AC2-Prompt testbar.

**6. AccessLink v3 (`GET /v3/exercises`), nicht v4.** Das v3-Schema ist stabil und vollständig dokumentiert; die v4-Ressource `training-sessions` ist zum Entscheidzeitpunkt nicht verlässlich spezifiziert. Migration auf v4 ist ein offener Punkt.

**7. v0-Scope-Grenze:** Ausgeliefert wird der Connector plus Unit-Tests. **Nicht** in v0: die OAuth-Consent-UI, die Einbindung in den Onboarding-Flow, die SwiftData-Persistenz der Cardio-Aktivitäten und die Dashboard-Darstellung. Das ist v1.

**8. Schlaf-, HRV- und Recovery-Daten von Polar bleiben ausgeschlossen.** Sie sind session-, nicht workout-förmig und passen strukturell nicht in `Activity` — dasselbe Problem wie HealthKit (`W-5`, ADR-6). Falls gewünscht: eigenes `HealthDataProvider`-Protocol, nicht `FitnessConnector`.

---

## Konsequenzen

### + Positiv

- **`W-6` ist aufgelöst.** Die zweite Quelle ist entschieden und ohne Backend umgesetzt — ADR-4 bleibt unangetastet.
- **Kein Protocol-Drift.** `PolarConnector` konform zum eingefrorenen `FitnessConnector`; jede Protocol-Änderung bricht ab jetzt drei Conformer statt zwei.
- **`Activity.metrics` ist der von ADR-6 vorgesehene additive Eingriff** — Strava-Feldanalyse bleibt davon unberührt offen.
- **Endurance-Daten für die AI-Empfehlung verfügbar:** Herzfrequenz-Trend und Trainingsload fliessen ohne weitere Modelländerung in den Prompt.
- **PKCE-Baustein wiederverwendbar** für jeden künftigen Public-Client-OAuth-Connector.

### – Negativ

- **Polar-Partner-Registrierung nötig** (`admin.polaraccesslink.com`): `clientID` + Redirect-URI sind Team-Credentials, kein Default im Binary. Ohne echte Registrierung läuft der Connector nur gegen Testfixtures.
- **`ActivityMetrics.trainingLoad` ist providerspezifisch skaliert** — nur als Trend einer Quelle interpretierbar, nie als quellenübergreifender Absolutwert.
- **v3 wird mittelfristig abgelöst.** Der `PolarExerciseDTO`↔v3-Vertrag muss bei der v4-Migration neu geschrieben werden (analog zur Strava-Feldanalyse ein additiver, kein struktureller Eingriff).
- **`GET /v3/exercises` liefert nur ein rollendes Fenster** der jüngsten Sessions. Für das 90-Tage-Fenster reicht das im PoC; v1 muss die transaktionsbasierte Historie (`exercise-transactions`) evaluieren.
- **Doppelter `member-id`-Lebenszyklus:** FitBuddy vergibt und speichert eine eigene stabile ID pro Nutzer — ein Zustand mehr in der Keychain.

---

## Offene Punkte

| Frage | Priorität | Fällig |
|---|---|---|
| OAuth-Consent-UI (`ASWebAuthenticationSession`) + Onboarding-Einbindung | Hoch | v1 |
| SwiftData-Persistenz für `Activity` mit `metrics` (Cardio-Sessions im Cache) | Hoch | v1 |
| Migration `GET /v3/exercises` → v4 `training-sessions` | Mittel | vor v1-Release |
| Historie über 90 Tage: `exercise-transactions` statt Fenster-Endpoint | Niedrig | v1 |
| Confidential-Client-Variante (`clientSecret` + Basic Auth) — nur falls je ein Backend kommt | Niedrig | offen |

---

## Nachtrag (2026-09-16): Polar verlangt zwingend ein Client Secret

**Die zentrale Prämisse dieses ADRs — Polar als PKCE-Public-Client ohne Secret, deshalb ohne Backend lösbar (Zeilen 17–19, 23) — ist falsch.** Bei der tatsächlichen Registrierung unter `admin.polaraccesslink.com` zeigt sich: Polar erzeugt für jeden Client ein Secret, und laut offizieller AccessLink-Doku (sowohl v3 `polarremote.com` als auch v4 `auth.polar.com`) authentisiert **jeder** Token-Request per HTTP Basic `client_id:client_secret` — PKCE wird nirgends als Ersatz dafür dokumentiert oder akzeptiert.

**Konsequenz:** Der Vergleich in der Kontext-Tabelle stimmt nicht mehr — Polar braucht, wie Strava, ein Secret, das ohne Backend nirgends sicher unterzubringen ist. Ein Secret im App-Binary ist aus jedem verteilten Build (TestFlight) extrahierbar; das gilt für ein Team-Secret genauso wie für ein persönliches.

**Für die CAS-Abschlusspräsentation (v0-Demo-Scope):** Das Team-Secret wird ausschliesslich lokal in der gitignoreten `PolarTeamConfig.plist` gehalten (issue #155) und nur in einem Build verwendet, der auf dem Gerät des Vortragenden bleibt — nie über TestFlight oder sonst wie verteilt. Das ist dieselbe Art pragmatischer, dokumentierter PoC-Abwägung wie die BYO-Key-Entscheidung in `CLAUDE.md`, aber **ausdrücklich nicht v1-tauglich.**

**Für v1 braucht es eine echte Lösung, analog zur Wahl bei Strava (ADR-10):**
1. **Backend-Proxy** — das Secret wandert auf einen Server, die App spricht nur noch mit dem eigenen Backend. Bricht ADR-4 (kein Server-Tier im PoC), ist aber der sauberste Weg für ein Produkt mit echten Nutzern.
2. **BYO-App wie Strava** — jeder Nutzer registriert eine eigene Polar-App und trägt Client-ID + Secret in einem eigenen Credentials-Screen ein (analog `StravaCredentialsView`, #139); das Secret liegt dann im Keychain des jeweiligen Nutzers, nie im Binary. Verliert den heutigen Vorteil "kein Setup pro Nutzer", ist aber ohne Backend umsetzbar.

Diese Entscheidung ist für v1 offen und nicht Teil des aktuellen PoC-Umfangs.
