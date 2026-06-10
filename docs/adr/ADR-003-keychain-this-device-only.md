# ADR-3: API-Keys im iOS Keychain mit `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`

**Status:** Accepted
**Datum:** 2026-06-03

---

## Kontext

Auf der in [[ADR-2]] festgelegten iOS-Plattform speichert FitBuddy mindestens zwei sensible API-Keys: den Hevy-Key (Zugriff auf alle Trainingsdaten des Users) und den Claude-Key (kostenpflichtige Inferenz auf dessen Rechnung). Beide sind funktional gleichwertig zu Passwörtern und müssen vor iCloud-Backup-Exfiltration, Cross-Device-Sync und Zugriff bei gesperrtem Gerät geschützt sein. iOS bietet mehrere Keychain-Accessibility-Attribute mit unterschiedlichen Trade-offs — ein falsches Attribut bedeutet im Worst Case, dass die Keys eines Users in dessen iCloud-Backup landen und auf Geräten erscheinen, die wir nie autorisiert haben.

### Entscheidungstreiber — Top-3-QAs

| QA | Anforderung an die Key-Speicherung | Quelle |
|---|---|---|
| **QA-1 Security / Privacy** | API-Keys verlassen das Gerät nie; kein iCloud-Sync; kein Backup-Restore auf Fremdgerät; bei Sperre hardware-geschützt | REQUIREMENTS.md §5 QA-1 |
| **QA-2 Reliability** | Bei HTTP 401 ([[ADR-1]] / US-1 AC3) muss der Key atomar löschbar sein, damit kein stiller Weiterbetrieb mit invalidem Key auftritt | REQUIREMENTS.md §5 QA-2 |
| **QA-3 Maintainability** | Nutzung des Standard-`Security`-Frameworks; keine zusätzlichen Crypto-Libraries; klare Service-Keys für drei Connectoren ([[ADR-6]]) | REQUIREMENTS.md §5 QA-3 |

### Geprüfte Optionen

| Option | Einschätzung gegen die Top-3-QAs |
|---|---|
| **`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`** *(gewählt)* | Kein iCloud-Sync, kein Backup-Restore, hardware-geschützt bei Sperre (QA-1). Atomar löschbar via `SecItemDelete` (QA-2). |
| **`kSecAttrAccessibleWhenUnlocked`** | Erlaubt iCloud-Keychain-Sync → verletzt QA-1 unmittelbar. Verworfen. |
| **`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`** | Background-Zugriff nach Reboot möglich. Im PoC ohne Background-Calls (US-11 ist Won't) unnötig. Erst bei v1.2-Push-Notifications relevant. |
| **`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`** | Strenger als gewählte Option; verhindert Nutzung ohne Geräte-Passcode. Wer Gesundheitsdaten und kostenpflichtige API-Keys verwaltet und kein Passcode hat, akzeptiert aktiv schwächere Sicherheit — die Option ist daher vertretbarer als zunächst bewertet. Für PoC verworfen (Demo-Tester ohne Passcode möglich), für v1.0 empfohlen. |
| **`SecAccessControl` mit Biometrie-Gate (`.biometryAny`)** | Zusätzliche Auth bei jedem Read — sinnvoll für das Bedrohungsmodell „entsperrtes, verlorenes Gerät mit Claude-Key". Für PoC verworfenen (~10 LOC Mehraufwand wäre vertretbar), für v1.0 zwingend. |

---

## Entscheidung

**Wir speichern alle FitBuddy-API-Keys im iOS Keychain mit dem Accessibility-Attribut `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.**

Wir verwenden die definierten Service-Keys `fitbuddy.hevy.apikey`, `fitbuddy.claude.apikey` und (v1.0) `fitbuddy.strava.token`. Keys werden nie geloggt, nie in Crash-Reports gesendet und nie in SwiftData oder UserDefaults gespiegelt — der Keychain ist die einzige Persistenzschicht für Key-Material. Bei HTTP 401 ([[ADR-1]] / US-1 AC3) löscht die App den betroffenen Key atomar und zwingt User zurück ins Onboarding (US-4).

Die `kSecAttrAccessGroup` wird ab Sprint 1 explizit gesetzt (auch ohne Watch/Widget im PoC-Scope), um eine spätere Watch-Extension oder ein Widget ohne Migrations-Zwang zu ermöglichen.

---

## Konsequenzen

### + Positiv

- **(QA-1) Kein iCloud-Sync, kein Backup-Restore:** `ThisDeviceOnly` schliesst beide Pfade aus — die Aussage „dein Key verlässt das Gerät nie" ist technisch belastbar.
- **(QA-1) Hardware-geschützt bei Sperre:** `WhenUnlocked` macht Keys bei gesperrtem Gerät auch dem OS unzugänglich; verhindert forensisches Auslesen bei verlorenem, gesperrtem Gerät.
- **(QA-2) Atomarer Reset-Pfad:** `SecItemDelete` ist eine Operation — bei HTTP 401 wird der Key entfernt, der Onboarding-Flow startet, kein stilles Weiterlaufen mit invalidem Key.
- **(QA-3) Apple-Standard, keine Drittlibraries:** Kein KeychainAccess/SwiftKeychainWrapper im `Package.resolved` nötig.

### - Negativ

- **(QA-1-Risiko) Silent Downgrade:** Ein Dev ändert während Debugging das Attribut zu `WhenUnlocked` und vergisst Rückbau → Keys landen unbemerkt in iCloud-Backup. Kein Test fängt das ab. **Mitigation:** SwiftLint-Custom-Rule, die `kSecAttrAccessible*` ohne `ThisDeviceOnly` als Fehler markiert; Code-Review-Checkliste.
- **(QA-1-Risiko) Debug-Logging exponiert Keys:** `URLSession`-Standardkonfiguration loggt Anfrage-Header (inkl. `Authorization: Bearer <key>`) in Instruments und OSLog. Im CAS-Kursraum-WLAN mit aktiven Proxy-Tools (Charles, mitmproxy) ist ein Key-Leak durch Debugging realistisch. **Mitigation:** `URLSession` mit `.ephemeral`-Konfiguration; OSLog-Privacy-Annotationen (`%{private}@`) für alle Key-nahen Log-Statements; URLSession-Logging in Debug-Builds explizit deaktivieren.
- **(QA-1-Risiko) Background-App-Snapshot:** iOS nimmt bei App-Wechsel einen Screen-Snapshot. Ist ein Key in einer sichtbaren TextField-Ansicht, erscheint er im App Switcher. **Mitigation:** `UIApplication.shared.ignoreSnapshotOnNextApplicationLaunch` oder Privacy-Screen beim `sceneDidEnterBackground`-Event.
- **(QA-2-Risiko) Keychain-Items überleben App-Deinstallation:** iOS löscht Keychain-Einträge bei Deinstallation standardmässig nicht. Eine Neuinstallation findet alte Keys vor — der Onboarding-Flow muss via `SecItemCopyMatching` prüfen, ob bereits ein Key vorhanden ist, und den User informieren. Ohne diese Prüfung startet Onboarding und der User gibt einen Key ein, der schon im Keychain liegt → `errSecDuplicateItem` bei `SecItemAdd`.
- **(QA-2-Risiko) `errSecDuplicateItem` bei Key-Update:** `SecItemAdd` schlägt still fehl, wenn ein Key bereits vorhanden ist. Key-Updates müssen mit `SecItemUpdate` implementiert werden (oder Delete + Add). Falsch implementiert → der alte Key bleibt aktiv, der User denkt er hat einen neuen gesetzt.
- **(QA-2-Risiko) Recovery-Loch bei Gerätewechsel:** Restore aus iCloud-Backup bringt Keys bewusst NICHT mit — User muss sie erneut eingeben. Der Onboarding-Text muss explizit kommunizieren: «Deine API-Keys werden nicht auf andere Geräte übertragen. Bei einem Gerätewechsel gibst du sie einmalig neu ein.»
- **(QA-3) Push-Notifications (US-11, v1.2) inkompatibel:** Hintergrund-LLM-Calls bei gesperrtem Gerät unmöglich — bei v1.2-Priorisierung muss das Attribut für den Claude-Key revisitiert werden.
- **Kein Server-Side-Kill-Switch:** Bei Key-Kompromittierung muss der User selbst im Hevy/Anthropic-Portal revoken — wir können nichts erzwingen (Konsequenz aus [[ADR-4]]).

---

## Offene Punkte

| Frage | Priorität | Fällig |
|---|---|---|
| **SwiftLint-Custom-Rule für `ThisDeviceOnly`-Enforcement schreiben** | **Hoch** | **Sprint 1** |
| **`kSecAttrAccessGroup` festlegen und in alle `SecItem*`-Calls integrieren (auch ohne Watch-Scope)** | **Hoch** | **Sprint 1** |
| **`SecItemCopyMatching`-Check im Onboarding-Flow implementieren (Key existiert bereits?)** | **Hoch** | **Sprint 1 / US-4** |
| **`SecItemUpdate` für Key-Rotation implementieren (statt blindem `SecItemAdd`)** | **Hoch** | **Sprint 1 / US-1** |
| **URLSession-Debug-Logging-Schutz: `.ephemeral`-Config + OSLog `%{private}@`-Annotationen** | **Hoch** | **Sprint 1** |
| **Privacy-Screen bei `sceneDidEnterBackground` (Background-Snapshot-Schutz)** | Mittel | Sprint 2 |
| Onboarding-Text «Keys werden nicht synchronisiert, bei Gerätewechsel neu eingeben» | Mittel | Sprint 4 |
| Biometrie-Gate (`SecAccessControl` mit `.biometryAny`) für v1.0 — für PoC verworfen, aber empfohlen | Niedrig | vor v1.0 |
| `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` für v1.0 evaluieren | Niedrig | vor v1.0 |
