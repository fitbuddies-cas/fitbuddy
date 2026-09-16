# ADR-11: Polar AccessLink als dritte Datenquelle — BYO-App wie Strava

**Status:** Accepted
**Datum:** 2026-09-16
**Treiber-QA:** Maintainability (QA-3), Security / Privacy (QA-1)

---

## Kontext

Hevy (#34) und Strava ([[ADR-10]], #152) sind als reale Quellen hinter dem `FitnessConnector`-Protocol ([[ADR-6]]) umgesetzt. Polar AccessLink kommt als **dritte** Quelle hinzu. Das ist keine Wahl gegen Strava: Beide Quellen laufen nebeneinander, der Sync fragt alle verbundenen Quellen ab.

Drei Punkte sind für Polar zu klären:

1. **OAuth ohne Backend.** Polars Token-Endpoint verlangt, wie Strava, bei jedem Request HTTP Basic `client_id:client_secret`. PKCE wird von AccessLink v3 nicht unterstützt. Ein Team-Secret im Binary ist aus jedem TestFlight-Build extrahierbar, ein Backend schliesst [[ADR-4]] aus.
2. **API-Version.** Polar betreibt zwei getrennte, inkompatible Systeme: AccessLink **v3** (`flow.polar.com`, `polarremote.com`, `www.polaraccesslink.com`) und die API **v4** (`auth.polar.com`). Ein unter `admin.polaraccesslink.com` registrierter Client authentisiert sich nur gegen die v3-Hosts.
3. **Datenmodell.** Polar liefert Ausdauer-Kennzahlen (Herzfrequenz, Kalorien, Trainingsload), für die das krafttrainingsgeformte `Activity`-Modell (`exercises → sets`) keinen Platz hat.

---

## Entscheidung

**1. BYO-App wie Strava.** Jeder Nutzer registriert seine eigene AccessLink-Application unter `admin.polaraccesslink.com` und trägt Client-ID und Client-Secret im Screen `PolarCredentialsView` ein. Als Redirect-URI hinterlegt er `fitbuddy://polar/callback`. Die Begründung aus [[ADR-10]] gilt unverändert: Das Secret gehört dem Nutzer, nicht dem Team — kein Secret im Binary, kein Backend, [[ADR-4]] bleibt gültig.

**2. AccessLink v3.**
- Autorisierung: `https://flow.polar.com/oauth2/authorization`, Scope `accesslink.read_all`, Absicherung des Callbacks über den zufälligen `state`-Parameter
- Token: `https://polarremote.com/v2/oauth2/token`
- Daten: `POST /v3/users` (einmalige Registrierung, `409` = bereits registriert = ok), `GET /v3/exercises`

**3. Sechs Keychain-Items**, alle `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` ([[ADR-3]]):

| Item | Inhalt |
|---|---|
| `fitbuddy.polar.clientid` | Client-ID der Polar-Application des Nutzers |
| `fitbuddy.polar.clientsecret` | Client-Secret derselben Application |
| `fitbuddy.polar.accesstoken` | Access-Token (Lebensdauer ca. 1 Jahr) |
| `fitbuddy.polar.refreshtoken` | Refresh-Token — bei v3 leer |
| `fitbuddy.polar.tokenexpiry` | Ablaufzeitpunkt des Access-Tokens, ISO8601 |
| `fitbuddy.polar.memberid` | FitBuddys stabile ID des Nutzers bei AccessLink |

Der Hard-Logout (US-1 AC3) löscht alle sechs samt der gecachten Polar-Trainings, "Alle Daten löschen" erfasst sie über `KeychainKey.allCases`.

**4. Token-Lifecycle.** v3 liefert kein Refresh-Token. Ein abgelaufenes Paar wird lokal abgelehnt, die Verbindung erscheint in der `ConnectorRegistry` als abgelaufen, und der Nutzer verbindet neu. Liefert Polar künftig doch ein Refresh-Token, erneuert `PolarConnector` das Paar und persistiert es selbst. `WorkoutSyncService` übernimmt es wie bei Strava nur, wenn es neuer ist (`connectIfNewer`).

**5. Integration analog Strava.** `PolarConnector` implementiert `FitnessConnector` unverändert und ist in `DataSourceStack`/`ConnectorRegistry` registriert. `WorkoutSyncService` bezieht Polar in den Sync ein, `Activity.source = .polar` hält den Cache quellengetrennt. Settings bieten Verbinden, Status und Trennen (`PolarConnectionView`). Consent v2 und Privacy Policy nennen Polar als Datenempfänger.

**6. `Activity` wird additiv um `metrics: ActivityMetrics?` erweitert** (`averageHeartRate`, `maximumHeartRate`, `activeCalories`, `distanceMeters`, `durationSeconds`, `trainingLoad`, `sport`, alle optional). Hevy und Strava lassen den Block `nil`, Dashboard und Prompt-Builder bleiben ohne Änderung gültig.

**7. Schlaf-, HRV- und Recovery-Daten bleiben ausgeschlossen.** Sie sind tages-, nicht trainingsförmig und passen nicht in `Activity` — dasselbe Problem wie HealthKit (`W-5`, [[ADR-6]]).

**Code-Ablage:** `PolarConnector`, `PolarOAuthClient`, `PolarOAuthService`, `PolarAccessLinkClient`, `PolarCredentialStore`, `PolarClientConfiguration` und die DTOs unter `Core/Connector/data/Polar/`; Credential-, Fehler- und Protocol-Typen sowie `ActivityMetrics` unter `Core/Connector/domain/`; Screens samt ViewModels unter `Features/Settings/`. Die Web-Auth-Naht `WebAuthenticating` wird mit Strava geteilt.

---

## Konsequenzen

### + Positiv

- **Kein Secret im Binary, kein Backend** — dieselben Eigenschaften wie Strava ([[ADR-10]]), inklusive pro Nutzer isolierter Rate-Limits und ohne Auftragsverarbeitung durch das Team.
- **Kein Protocol-Drift.** Drei Conformer auf dem unveränderten `FitnessConnector`, geteilte OAuth-Infrastruktur mit Strava.
- **Ausdauer-Kennzahlen im Modell** über den additiven Eingriff `Activity.metrics`.

### – Negativ

- **Zusätzlicher Einrichtungsschritt** für den Nutzer (eigene AccessLink-Application), wie bei Strava.
- **Keine rückwirkende Historie.** `GET /v3/exercises` liefert nur Trainings, die *nach* der Registrierung zu Flow hochgeladen wurden, und nur die der letzten 30 Tage (*"Only exercises that have been uploaded to Flow after the user is registered with your client will be returned."*). Ein frisch verbundenes Konto zeigt deshalb zunächst `0` Trainings — für die Demo braucht es ein nach dem Verbinden aufgezeichnetes Training.
- **`trainingLoad` ist providerspezifisch skaliert** — nur als Trend innerhalb von Polar interpretierbar.
- **`metrics` wird noch nicht persistiert.** Das SwiftData-Schema kennt die Ausdauer-Kennzahlen nicht; im Cache fehlen sie.
- **v3 wird mittelfristig abgelöst.** Die Migration auf v4 bedeutet neue Hosts, neue Client-Registrierung und ein neues DTO.
- **Drei weitere Hosts für das Certificate-Pinning** (TD-4).

---

## Offene Punkte

| Frage | Priorität | Fällig |
|---|---|---|
| SwiftData-Persistenz von `Activity.metrics` | Hoch | v1 |
| Migration auf v4 `GET /training-sessions` — prüfen, ob v4 auch Trainings vor der Autorisierung liefert | Mittel | v1 |
| Import bestehender Polar-Historie (Flow-Datenexport als JSON bzw. FIT/TCX) | Niedrig | v1 |
