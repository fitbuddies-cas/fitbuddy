# ADR-10: Strava-OAuth2 im BYO-App-Modell — Client-Credentials des Nutzers statt Backend

**Status:** Accepted — die Verwerfung von Polar ist durch [[ADR-11]] revidiert (Polar ist seit ADR-11 dritte Quelle nach demselben BYO-App-Modell); der übrige Text bleibt als Protokoll unverändert
**Datum:** 2026-09-10
**Treiber-QA:** Security / Privacy (QA-1), Maintainability (QA-3)

---

## Kontext

US-5 («Zweite Datenquelle verbinden») ist seit Sprint 1 architektonisch vorbereitet: das
`FitnessConnector`-Protocol ([[ADR-6]], Issue #33), der auf Konformität umgebaute
`HevyConnector` (#34) und der `StravaConnector`-Stub samt `ConnectorRegistry` (#35) sind
ausgeliefert. Das Modell kennt `ConnectorCredentials.oauth(accessToken:refreshToken:expiresAt:)`,
`ConnectorConnectionState.expired(since:)` und `ConnectorSource.renewalPrompt` — es fehlt
ausschliesslich der Flow, der eine Verbindung überhaupt entstehen lässt.

Blockiert war das bisher durch **W-6** in `ARCHITECTURE.md`: *«Strava OAuth-Secret ohne Backend
strukturell unlösbar. Secret in App einbetten ist nicht akzeptabel. Polar Accesslink (PKCE, kein
Secret) ist eine Backend-freie Alternative — Entscheid steht aus.»* Der Widerspruch ist echt:

- Strava tauscht den Authorization Code am Endpoint `POST /oauth/token` ausschliesslich gegen
  Vorlage von `client_id` **und** `client_secret` ein. PKCE (RFC 7636), das genau für
  Public Clients ohne Secret gedacht ist, unterstützt Strava am Token-Endpoint nicht.
- [[ADR-4]] schliesst einen Backend-Proxy für den PoC aus. Es gibt damit keinen Ort, an dem ein
  *vom Team betriebenes* Secret serverseitig liegen könnte.

Die Prämisse, an der W-6 scheitert, ist jedoch «das Secret gehört dem Team». FitBuddy ist
durchgängig eine BYO-Key-App: Der Hevy-API-Key, der Claude-Key und die Gemini-/Mistral-Keys
gehören dem Nutzer, liegen in seinem Keychain und werden auf seine Rechnung verwendet
([[ADR-3]], [[ADR-4]], [[ADR-7]]). Strava erlaubt jedem Account, unter
`strava.com/settings/api` eine eigene API-Application anzulegen. Damit gehört auch das
Client Secret dem Nutzer — und «Secret in der App einbetten» steht gar nicht zur Debatte.

---

## Geprüfte Alternativen

| Option | Aufwand | Einschätzung |
|---|---|---|
| **BYO-Strava-App: Nutzer hinterlegt eigene Client ID + Client Secret (gewählt)** | ~36–42 h (#136–#145) | Kein fremdes Secret im Binary, [[ADR-4]] bleibt unverändert gültig, konsistent zum bestehenden Key-Modell. Preis: ein zusätzlicher Einrichtungsschritt für den Nutzer. |
| **Team-Strava-App, Secret im Binary** | ~25 h | Einfachste UX (ein Knopf), aber das Secret ist in jedem TestFlight-Build per `strings` lesbar. Verstösst gegen W-6 und gegen die Key-Regeln aus [[ADR-3]]. **Verworfen.** |
| **Team-Strava-App, Secret in einem Backend-Proxy** | +2–3 Sprints | Die technisch saubere Lösung für v1.0+. Widerspricht [[ADR-4]] und ist im PoC-Zeitbudget nicht tragbar. **Auf v1.0 verschoben.** |
| **Polar Accesslink statt Strava (PKCE, kein Secret)** | ~30 h | Strukturell elegant, aber ein Quellenwechsel: Strava ist in `README.md`, US-5, R1 und R2 als zweite Quelle benannt, Polar hat im Zielbild keine Rolle. Das ist eine Produktentscheidung, kein Architekturproblem. **Verworfen.** |
| **Nur Dateiimport (GPX/TCX) statt OAuth** | ~12 h | Umgeht OAuth vollständig, erfüllt aber US-5 AC1 nicht («schliesst OAuth-Flow ab») und liefert keine Token-Ablauf-Situation für AC2. **Verworfen.** |

---

## Entscheidung

**W-6 ist aufgelöst:** Strava bleibt die zweite Datenquelle, und der OAuth2-Flow läuft ohne
Backend, weil die Client-Credentials dem Nutzer gehören.

**1 — Der Nutzer bringt seine eigene Strava-API-Application mit.** Die App führt ihn nach
`strava.com/settings/api`; er trägt Client ID und Client Secret in FitBuddy ein. Als
«Authorization Callback Domain» setzt er in seiner Strava-Application `localhost` — Strava prüft die `redirect_uri` über ihren *Host*, nicht über das Scheme, und `localhost` ist der Wert, den Stravas eigene Doku für Apps ohne Web-Domain vorsieht.

**2 — Fünf Keychain-Items statt eines.** [[ADR-3]] reserviert für Strava einen einzelnen Key
`fitbuddy.strava.token`. Das BYO-Modell braucht mehr, und dieser ADR löst die Reservierung ab:

| Item | Inhalt |
|---|---|
| `fitbuddy.strava.clientid` | Client ID der Strava-Application des Nutzers |
| `fitbuddy.strava.clientsecret` | Client Secret derselben Application |
| `fitbuddy.strava.accesstoken` | Access-Token (Lebensdauer 6 h) |
| `fitbuddy.strava.refreshtoken` | Refresh-Token (von Strava bei jedem Refresh rotiert) |
| `fitbuddy.strava.expiresat` | Ablaufzeitpunkt des Access-Tokens, ISO8601 |

Alle fünf tragen `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, liegen unter demselben
`kSecAttrService` wie die bestehenden Keys und werden über `KeychainKey.allCases` automatisch
von `DataResetService` und `FirstLaunchResetService` erfasst. `kSecAttrAccessGroup` bleibt
ungesetzt — unverändert zu [[ADR-3]].

**3 — `ASWebAuthenticationSession` mit Custom-Scheme `fitbuddy://localhost/strava`.** Der
Authorize-Aufruf geht an den Web-Endpoint `https://www.strava.com/oauth/authorize`; die Session
fängt den Redirect selbst ab, es braucht keinen `onOpenURL`-Pfad in der App. Universal Links
sind verworfen: sie verlangen eine gehostete `apple-app-site-association` und damit genau die
Server-Infrastruktur, die [[ADR-4]] ausschliesst. Der App-Switch-Endpoint
`/oauth/mobile/authorize` (springt in die installierte Strava-App) ist eine v1-Option und
erfordert zusätzlich `onOpenURL`.

Weil `ASWebAuthenticationSession` `@MainActor` verlangt und im Unit-Test nicht lauffähig ist,
liegt sie hinter der Naht `WebAuthenticating`; der `StravaOAuthService` bleibt ein `actor` und
ist damit testbar — die Service-Regel aus `CLAUDE.md` bleibt gewahrt.

**4 — Scope `activity:read_all`, sonst nichts.** Lesend, inklusive privater Aktivitäten. Kein
`profile:read_all`, kein Write-Scope. Jeder zusätzliche Scope erweitert den Consent-Text
(US-4 AC4) und vergrössert den Schaden bei Token-Kompromittierung.

**5 — Token-Refresh liegt im `StravaConnector`, die Ablauf-Buchführung in der
`ConnectorRegistry`.** `validate()` erneuert einen ablaufenden Access-Token über
`StravaOAuthorizing.refresh` und persistiert das Ergebnis — Strava rotiert das Refresh-Token bei
jedem Refresh, das neue muss gespeichert werden, sonst ist die Verbindung nach dem zweiten
Refresh tot. Der Nachtrag zu #35 in [[ADR-6]] (Punkt 2) bleibt dadurch unverändert gültig: die
Registry beantwortet `state(of:now:)` und `sourcesNeedingRenewal(now:)`, und ein abgelaufenes
*Refresh*-Token kann weiterhin nur der Nutzer erneuern.

**6 — Code-Ablage** nach den Regeln aus `CLAUDE.md`: `StravaOAuthService`, `StravaConnector`,
`StravaCredentialStore` und die DTOs unter `Core/Connector/data/`, die Fehler- und
Credential-Typen unter `Core/Connector/domain/`, die Web-Auth-Naht unter `Core/Networking/`,
die beiden Screens samt ViewModels unter `Features/Settings/`.

---

## Konsequenzen

### + Positiv

- **W-6 ist ohne Backend aufgelöst.** [[ADR-4]] bleibt unverändert; die Strava-Integration
  erzwingt keine Proxy-Migration vor der Zeit.
- **Kein Secret im Binary.** `strings` über das TestFlight-IPA liefert keine verwertbaren
  Strava-Credentials. Ein kompromittierter Build exponiert niemals die Nutzer *anderer* Geräte.
- **Rate-Limits sind pro Nutzer isoliert.** Strava begrenzt pro Application (200 Requests /
  15 min, 2 000 / Tag). Weil jeder Nutzer seine eigene Application betreibt, kann kein Tester
  die anderen aussperren — dasselbe Argument, mit dem [[ADR-4]] den Team-Key für externe Tester
  verbietet, wirkt hier zugunsten der Architektur.
- **Datenschutzrechtlich bleibt das Team aussen vor.** Der Nutzer akzeptiert die Strava-API-Terms
  selbst, sein Token gilt nur für seine eigenen Aktivitäten. Es entsteht kein
  Auftragsverarbeitungsverhältnis, das das Team zu tragen hätte — analog zur Argumentation in
  [[ADR-5]] für Anthropic.
- **Das `Activity`-Modell bleibt unverändert.** Strava-Aktivitäten bilden auf die bereits
  vorhandenen `ActivityExerciseSet.distanceMeters` / `.durationSeconds` ab. Damit ist die in
  [[ADR-6]] seit #33 offene «Strava-API-Feldanalyse» beantwortet: keine GPS-Route, keine
  Lap-Splits, kein Power, keine HR-Zonen im Modell — und kein `metadata`-Escape-Hatch.

### - Negativ

- **Einrichtungsfriktion.** Der Nutzer muss eine eigene API-Application anlegen, bevor er einen
  einzigen Lauf sieht — drei Schritte auf einer Website, die er vorher nie gesehen hat. Wer schon
  einen Hevy-API-Key beschafft hat, bewältigt das; für alle anderen ist es eine echte Hürde.
  **Mitigation:** Anleitung mit Direktlink im Screen, gleiche Machart wie der Hevy-Key-Screen;
  Strava bleibt optional, das Dashboard funktioniert vollständig ohne.
- **Client Secret auf dem Gerät ohne serverseitigen Kill-Switch.** Identische Lage wie beim
  Hevy- und beim LLM-Key ([[ADR-3]], [[ADR-4]]) — kein *neues* Risiko, aber ein weiteres Item
  in derselben Risikoklasse. Der Nutzer kann das Secret in seiner Strava-Application jederzeit
  selbst rotieren; das ist der Kill-Switch, den das Team nicht hat.
- **Fünf statt vier Hosts ohne Certificate Pinning.** `www.strava.com` tritt zu den in TD-4
  gelisteten Hosts hinzu. Die Pinning-Schuld aus [[ADR-4]] wird dadurch grösser, nicht kleiner.
- **Support-Last bei Fehlkonfiguration.** Eine falsch gesetzte «Authorization Callback Domain»
  ist der wahrscheinlichste Fehler und äussert sich im Web-Sheet, nicht in der App.
  **Mitigation:** `StravaOAuthError` unterscheidet `stateMismatch`, `accessDenied`,
  `missingScope` und `invalidClientCredentials`, damit das UI konkret statt generisch meldet.
- **Strava kann die Spielregeln ändern.** Die API ist 2020 bereits massiv eingeschränkt worden
  (Risiko R1). Eine Verschärfung der Terms für nutzereigene Applications würde genau dieses
  Modell treffen. Die Kapselung im Connector hält den Schaden auf eine Klasse begrenzt — das ist
  der Zweck von [[ADR-6]].
- **Cross-Source-Persistenz wird aufwendiger.** Der heutige Cache ersetzt das gesamte
  Zeitfenster; mit zwei Quellen braucht es `Activity.source`, eine SwiftData-Migration und einen
  quellenbezogenen Replace (#141). Das löst zugleich den offenen Punkt aus [[ADR-1]], kostet aber
  die erste echte `VersionedSchema`-Migration des Projekts.

---

## Offene Punkte

| Frage | Priorität | Fällig |
|---|---|---|
| **Strava-API-Doku bei der Implementierung gegenprüfen** (Endpoints, Scope-Namen, Rate-Limits, Pflichtfelder am Token-Endpoint) — dieser ADR ist gegen den Stand 09/2026 geschrieben | **Hoch** | **#138** |
| **Certificate Pinning inkl. `www.strava.com`** (TD-4, nun fünf Hosts) | Hoch | vor TestFlight mit externen Testern |
| Consent-Version anheben, sobald Strava als Empfänger in der Privacy-Notice steht | Hoch | #145 |
| `/oauth/mobile/authorize` + `onOpenURL` für den App-Switch in die Strava-App evaluieren | Niedrig | v1 |
| Athlete-ID aus der Token-Antwort persistieren, falls Multi-Account je relevant wird | Niedrig | offen |
