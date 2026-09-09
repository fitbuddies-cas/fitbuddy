# ADR-6: `FitnessConnector`-Protocol als Abstraktion ab Sprint 1

**Status:** Accepted
**Datum:** 2026-06-03
**Treiber-QA:** Maintainability (QA-3)

---

## Kontext

Risiko R1 dokumentiert, dass die Hevy API keine Stabilitätsgarantie liefert; Strava hat 2020 die eigene API massiv eingeschränkt. Eine zweite Datenquelle (Strava in v1.0) ist daher nicht optional, sondern strategische Absicherung — sie steht in MoSCoW als Should (US-5). Wenn `HevyConnector`-Code direkt in Dashboard-Views und den Claude-Prompt-Builder verwächst, wird jeder neue Connector zum Refactor statt zum Feature.

Zusätzlich ist ungeklärt, ob Apple HealthKit (Schlaf, HRV, Ruheherzfrequenz) in den Scope kommt (offene Frage in CLAUDE.md). HealthKit hat ein fundamental anderes Zugriffsmodell als REST-APIs (Permissions per Data Type, `HKQuery` statt `URLSession`, kein API-Key) — das Protocol muss diese Heterogenität berücksichtigen oder bewusst ausschliessen.

---

## Entscheidung

Wir definieren das `FitnessConnector`-Protocol in Sprint 1 **vor** der ersten `HevyConnector`-Implementierung. Alle nachgelagerten Schichten (Dashboard, AI Analysis Engine, Cache) lesen ausschliesslich aus dem normalisierten `Activity`-Modell.

**Der Protocol-Vertrag umfasst:**

```swift
protocol FitnessConnector {
    func connect(credentials: ConnectorCredentials) async throws
    func validate() async throws -> Bool
    func fetchActivities(since: Date) async throws -> [Activity]
    func disconnect()
}
```

**`ConnectorError` ist Teil des Vertrags** und muss in Sprint 1 parallel zum Protocol definiert werden:

```swift
enum ConnectorError: Error {
    case unauthorized           // HTTP 401 → Keychain-Reset + Onboarding
    case rateLimited(retryAfter: TimeInterval?)  // HTTP 429 → Backoff
    case networkUnavailable     // Kein Netz → Offline-Mode
    case serviceUnavailable     // HTTP 5xx → Retry
    case invalidResponse        // Unerwartetes Response-Format
}
```

Ohne dieses Error-Enum können Dashboard und AI-Engine nicht zwischen Auth-Fehler (→ Keychain löschen) und Netzwerkfehler (→ Offline-Mode) unterscheiden — der HTTP-401-Reset-Flow aus [[ADR-3]] wäre nicht implementierbar.

Wir committen gleichzeitig einen **`MockConnector`** (konfigurierbares Test-Double mit einstellbaren Responses: leere Liste, n Activities, Fehler-Injection) und einen **`StravaConnectorStub`** (nur Compilation-Garant, wirft `.notImplemented` — separates Konzept vom MockConnector).

**Strava-API-Feldanalyse vor Sprint 1:** Bevor das `Activity`-Modell finalisiert wird, analysieren wir die Strava API auf Felder, die nicht ins aktuelle Modell passen (GPS-Route, Lap-Splits, Power, VO2max, HR Zones). Das Modell muss diese Felder als optionale Felder enthalten oder eine `metadata: [String: Any]`-Escape-Hatch vorsehen — sonst ist die Strava-Integration in v1.0 doch ein Refactor.

**HealthKit-Entscheid:** Das Protocol passt nicht auf HealthKit (`HKQuery`-basiert, keine `ConnectorCredentials`, permission-gated per Data Type). Wenn HealthKit IN den Scope kommt, braucht es ein separates `HealthDataProvider`-Protocol oder eine HealthKit-Adapterklasse ausserhalb des `FitnessConnector`-Vertrags. Dieser Entscheid muss vor Sprint 1 getroffen werden.

**Pagination:** `HevyConnector` paginiert intern transparent (alle Pages werden vor Return akkumuliert). Das Protocol gibt nach aussen `[Activity]` zurück. Bei sehr grossen Historien (1000+ Workouts) muss in v1.0 eine cursor-basierte API oder `AsyncStream` evaluiert werden — für den PoC mit 90-Tage-Fenster ist internes Paginieren akzeptabel.

**OAuth-Token-Refresh:** Strava verwendet OAuth 2.0 mit ablaufenden Tokens. `ConnectorCredentials` muss für Strava sowohl `access_token` als auch `refresh_token` + `expires_at` halten. Der `StravaConnector` ist für den Refresh verantwortlich — `validate()` prüft Token-Ablauf und refresht bei Bedarf. Hevy-API-Keys laufen nicht ab, `HevyConnector.validate()` macht nur einen API-Ping.

### Nachtrag: Abweichungen aus der Umsetzung (Issue #33, PR #81)

Die Umsetzung des Protocols weicht an vier Stellen bewusst von der obigen Entscheidung ab. Sie sind hier festgehalten, damit spätere Arbeiten (#34 `HevyConnector`, #35 Strava-Stub) den tatsächlich geltenden Vertrag lesen und nicht den ursprünglich skizzierten:

1. **`disconnect()` ist `async`.** Jeder Conformer ist ein `actor` (analog `HevyKeyValidator`/`KeychainService`); ein Actor kann eine Protocol-Anforderung von aussen nur erfüllen, wenn diese selbst `async` ist. Die synchrone Signatur oben ist damit überholt.
2. **Keine Strava-Feldanalyse vor der Finalisierung, keine `metadata`-Escape-Hatch.** Das `Activity`-Modell enthält bewusst keine spekulativen Strava-only-Felder (GPS-Route, Lap-Splits, Power, HR Zones). Die Feldanalyse wird nach #35 gezogen; bis dahin gilt die Konsequenz *"Strava-Integration ist eine neue Connector-Klasse"* nur unter dem Vorbehalt, dass `Activity` dann noch um optionale Felder erweitert werden muss — ein additiver, kein struktureller Eingriff.
3. **Kein `StravaConnectorStub` in Sprint 1.** Der Stub ist nach #35 verschoben; ausgeliefert wird vorerst nur der `MockConnector`.
4. **Identität der Kind-Objekte ist die Quell-Reihenfolge, nicht eine generierte UUID.** `ActivityExercise.id` und `ActivityExerciseSet.id` sind der jeweilige `index`. Eine pro Mapping neu erzeugte `UUID()` würde ein inhaltlich unverändertes Workout beim Re-Sync `!=` zur gecachten Kopie machen und SwiftUI zwingen, jede `ForEach`-Zeile neu aufzubauen. `SetType` liegt aus demselben Grund im Connector-Domain-Layer (`Core/Connector/domain/`) und nicht in der Persistence-Schicht — die Konsequenz *"Dashboard und AI-Engine sehen nie Hevy-spezifische Typen"* gilt sonst nicht.

### Nachtrag: Abweichungen aus der Umsetzung (Issue #34, `HevyConnector`)

Die Implementierung des ersten Connectors weicht an fünf Stellen von der obigen Skizze ab:

1. **Der Connector ist reines Provider-I/O, die Sync-Orchestrierung liegt darüber.** `HevyConnector` kennt nur HTTP, Pagination und die DTO→`Activity`-Abbildung; Keychain-Lesen, Cache-Write, Sync-Timestamp und der Hard-Logout aus [[ADR-3]] liegen in `WorkoutSyncService`. Grund: `ConnectorError` beschreibt ausschliesslich Provider-Fehler — für "Keychain gesperrt" und "Cache-Write fehlgeschlagen" gibt es dort bewusst keine Cases, und beide muss das Dashboard unterscheiden können. Ein Connector, der die Keychain leert, wäre ausserdem nicht mehr austauschbar: das Löschen der Session ist eine App-Entscheidung, keine des Providers.
2. **`WorkoutSyncError` ist das Fehler-Vokabular der Sync-Schicht.** Es hebt jeden `ConnectorError`-Case 1:1 an und ergänzt `missingAPIKey`, `keychainUnavailable` und `persistenceFailed`. `ConnectorError` selbst bleibt damit eingefroren, wie unter "Negativ" gefordert.
3. **HTTP 403 wird als `invalidResponse` gemeldet, nicht als `unauthorized`.** `ConnectorError` hat keinen Case für "unerwarteter Status", und 403 trifft auch gültige Keys (WAF, Geo) — als Auth-Fehler gemeldet würde der Aufrufer einen funktionierenden Key löschen. Der Statuscode geht ins Log.
4. **`Activity` wurde additiv erweitert** um `notes`, `updatedAt` (Workout-Ebene) sowie `templateID` und `supersetID` (Übungsebene). Ohne diese Felder verliert der Weg Hevy → `Activity` → Cache Daten, die die App bereits anzeigt (die Session-Beschreibung in der Detailansicht) oder für US-9 braucht (die stabile Identität der Übung). Das ist der additive Eingriff, den Nachtrag Punkt 2 der ersten Umsetzung vorgesehen hat — die Strava-Feldanalyse bleibt davon unberührt offen.
5. **`HevyKeyValidator` bleibt vorerst neben `HevyConnector.validate()` bestehen.** Onboarding und Settings prüfen den Key über `HevyKeyValidating` mit eigenem Fehlertyp; die Doppelspurigkeit ist bekannt und bewusst nicht Teil von #34, weil sie den Onboarding-Fehlerpfad mit umbauen würde. Zusammenlegen ist ein eigener Task.

Die Konsequenz *"Dashboard und AI-Engine sehen nie Hevy-spezifische Typen"* gilt seit #34 tatsächlich: die Hevy-DTOs liegen in `Core/Connector/data/` und werden ausserhalb nur noch von `MockWorkoutLoader` genannt — einem DEBUG-only-Fixture-Loader, der aufgezeichnete Hevy-Payloads dekodiert und genau deshalb den echten Decoding-Pfad nehmen muss.

---

## Konsequenzen

### + Positiv

- **Strava-Integration in v1.0 ist eine neue Connector-Klasse** — sofern das `Activity`-Modell vorab die nötigen optionalen Felder enthält (s. Strava-Feldanalyse und Nachtrag Punkt 2). Dashboard und AI-Prompt-Builder bleiben unverändert.
- **`MockConnector` als Test-Double** ermöglicht Unit-Tests ohne echte Hevy-API: Fehler-Injection, leere Response, zeitgesteuerte Activities — CI-freundlich und Rate-Limit-unabhängig.
- **`ConnectorError`-Enum erzwingt einheitliches Fehlerhandling:** Alle Schichten reagieren auf denselben Fehlertyp — kein `catch`-Block mit `as? URLError`-Typ-Casting gegen connectorspezifische Implementierungsdetails.
- **Strikte Schichttrennung:** Dashboard und AI-Engine sehen nie Hevy-spezifische Typen — nur `Activity`. Protocol-Drift zwischen Sprint 1 und v1.0 wird durch Compilation erzwungen.

### - Negativ

- **Protocol-Evolution ist destruktiv:** Neue required methods brechen alle Implementierungen. Neue Methoden müssen via `extension` mit Default-Implementation hinzugefügt werden (nur für non-critical Paths) oder als optionales Sub-Protocol. **Mitigation:** Protocol einfrieren nach Sprint 1; Erweiterungen via `FitnessConnectorExtended`-Sub-Protocol.
- **Initialer Overhead in Sprint 1:** Protocol-Design + `ConnectorError`-Enum + `MockConnector` + Strava-Feldanalyse + `Activity`-Modell-Review kostet ca. 1.5 Personentage (nicht 1, wie ursprünglich geschätzt).
- **Internes Paginieren ist Memory-intensiv** bei grossen Historien: 1000+ Workouts akkumuliert als `[Activity]` im Heap. Im PoC mit 90-Tage-Fenster (~360 Objekte) unkritisch; in v1.0 mit voller Strava-Historie zu revisitieren.
- **Hevy-spezifische Features (Routinen-Metadaten) passen nicht ins Protocol:** Entweder Hevy-only-Sub-Interface (`HevySpecificConnector`) oder bewusster Verzicht — Entscheid in Sprint 1.
- **HealthKit passt strukturell nicht ins Protocol** (s. o.) — erfordert separates Design-Dokument wenn IN Scope.

---

## Offene Punkte

| Frage | Priorität | Fällig |
|---|---|---|
| **HealthKit IN oder OUT of Scope? — Bei IN: separates `HealthDataProvider`-Protocol designen** | **Kritisch** | **vor Sprint 1** |
| **Strava-API-Feldanalyse: GPS, Lap-Splits, Power, VO2max, HR Zones — `Activity`-Modell um optionale Felder erweitern** | **Hoch** | **Sprint 1, vor HevyConnector-Implementierung** |
| **`ConnectorError`-Enum finalisieren und in alle `throws`-Signaturen einsetzen** | **Hoch** | **Sprint 1** |
| **`MockConnector` mit Fehler-Injection und konfigurierbaren Responses implementieren** | **Hoch** | **Sprint 1** |
| **`kSecAttrAccessGroup` + `ConnectorCredentials`-Struktur für OAuth-Token (Strava) vs. API-Key (Hevy) definieren** | Hoch | Sprint 1 |
| Pagination-Strategie für v1.0 evaluieren: `AsyncStream<Activity>` vs. Cursor-Modell | Mittel | vor v1.0 |
| Hevy-spezifische Features (Routinen-Metadaten): Sub-Interface oder Verzicht? | Niedrig | Sprint 2 |
| Protocol-Extension-Strategie für zukünftige Methoden festlegen (Sub-Protocol vs. `extension`-Default) | Niedrig | vor v1.0 |
