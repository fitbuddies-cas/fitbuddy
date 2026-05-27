# ADR-3: API-Keys im iOS Keychain mit `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`

**Status:** Proposed
**Datum:** 2026-05-27
**Autor:** FitBuddy Team (CAS ADAI 2026, Modul 3)

---

## Kontext

Auf der in [[ADR-2]] festgelegten iOS-Plattform speichert FitBuddy mindestens zwei sensible API-Keys: den Hevy-Key (Zugriff auf alle Trainingsdaten des Users) und den Claude-Key (kostenpflichtige Inferenz auf dessen Rechnung). Beide sind funktional gleichwertig zu Passwörtern und müssen vor iCloud-Backup-Exfiltration, Cross-Device-Sync und Zugriff bei gesperrtem Gerät geschützt sein. iOS bietet mehrere Keychain-Accessibility-Attribute mit unterschiedlichen Trade-offs — ein falsches Attribut bedeutet im Worst Case, dass die Keys eines Users in dessen iCloud-Backup landen und auf Geräten erscheinen, die wir nie autorisiert haben.

### Entscheidungstreiber — Top-3-QAs

| QA | Anforderung an die Key-Speicherung | Quelle |
|---|---|---|
| **QA-1 Security / Privacy** | API-Keys verlassen das Gerät nie; kein iCloud-Sync; kein Backup-Restore auf Fremdgerät; bei Sperre hardware-geschützt | REQUIREMENTS_PO.md §6, §7 QA-1 |
| **QA-2 Reliability** | Bei HTTP 401 ([[ADR-1]] / US-1 AC3) muss der Key atomar löschbar sein, damit kein stiller Weiterbetrieb mit invalidem Key auftritt | REQUIREMENTS_PO.md §7 QA-2 |
| **QA-3 Maintainability** | Nutzung des Standard-`Security`-Frameworks; keine zusätzlichen Crypto-Libraries; klare Service-Keys für drei Connectoren ([[ADR-6]]) | REQUIREMENTS_PO.md §7 QA-3 |

### Geprüfte Optionen

| Option | Einschätzung gegen die Top-3-QAs |
|---|---|
| **`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`** *(gewählt)* | Kein iCloud-Sync, kein Backup-Restore, hardware-geschützt bei Sperre (QA-1). Atomar löschbar via `SecItemDelete` (QA-2). |
| **`kSecAttrAccessibleWhenUnlocked`** | Erlaubt iCloud-Keychain-Sync → verletzt QA-1 unmittelbar. Verworfen. |
| **`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`** | Background-Zugriff nach Reboot möglich. Im PoC ohne Background-Calls (US-11 ist Won't) unnötig. Erst bei v1.2-Push-Notifications relevant. |
| **`kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly`** | Strenger; blockiert User ohne Geräte-Passcode komplett. UX-Hürde nicht gerechtfertigt für PoC. |
| **`SecAccessControl` mit Biometrie-Gate (`.biometryAny`)** | Zusätzliche Auth bei jedem Read — sinnvoll, wenn Bedrohungsmodell „verlorenes entsperrtes Gerät" enthält. Für PoC zu invasiv, für v1.0 erwägen. |

---

## Entscheidung

**Wir speichern alle FitBuddy-API-Keys im iOS Keychain mit dem Accessibility-Attribut `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.**

Wir verwenden die definierten Service-Keys `fitbuddy.hevy.apikey`, `fitbuddy.claude.apikey` und (v1.1) `fitbuddy.strava.token`. Keys werden nie geloggt, nie in Crash-Reports gesendet und nie in SwiftData oder UserDefaults gespiegelt — der Keychain ist die einzige Persistenzschicht für Key-Material. Bei HTTP 401 ([[ADR-1]] / US-1 AC3) löscht die App den betroffenen Key atomar und zwingt User zurück ins Onboarding (US-4).

---

## Konsequenzen

### + Positiv

- **(QA-1) Kein iCloud-Sync, kein Backup-Restore:** `ThisDeviceOnly` schliesst beide Pfade aus — die Aussage „dein Key verlässt das Gerät nie" ist technisch belastbar.
- **(QA-1) Hardware-geschützt bei Sperre:** `WhenUnlocked` macht Keys bei gesperrtem Gerät auch dem OS unzugänglich; verhindert forensisches Auslesen bei verlorenem, gesperrtem Gerät.
- **(QA-2) Atomarer Reset-Pfad:** `SecItemDelete` ist eine Operation — bei HTTP 401 wird der Key entfernt, der Onboarding-Flow startet, kein stilles Weiterlaufen mit invalidem Key.
- **(QA-3) Apple-Standard, keine Drittlibraries:** Kein KeychainAccess/SwiftKeychainWrapper im `Package.resolved` nötig.

### - Negativ

- **(QA-1-Risiko) Silent Downgrade:** Ein Dev ändert während Debugging das Attribut zu `WhenUnlocked` und vergisst Rückbau → Keys landen unbemerkt in iCloud-Backup. Kein Test fängt das ab. **Mitigation:** SwiftLint-Custom-Rule, die `kSecAttrAccessible*` ohne `ThisDeviceOnly` als Fehler markiert; Code-Review-Checkliste.
- **(QA-2-Risiko) Recovery-Loch bei Gerätewechsel:** Restore aus iCloud-Backup bringt Keys bewusst NICHT mit — User muss sie erneut eingeben. Muss im Onboarding ([[ADR-1]] / US-4) explizit kommuniziert werden.
- **(QA-3) Push-Notifications (US-11, v1.2) inkompatibel:** Hintergrund-LLM-Calls bei gesperrtem Gerät unmöglich — bei v1.2-Priorisierung muss das Attribut für den Claude-Key revisitiert werden.
- **Kein Server-Side-Kill-Switch:** Bei Key-Kompromittierung muss der User selbst im Hevy/Anthropic-Portal revoken — wir können nichts erzwingen (Konsequenz aus [[ADR-4]]).

---

## Offene Punkte

| Frage | Priorität | Fällig |
|---|---|---|
| SwiftLint-Custom-Rule für `ThisDeviceOnly`-Enforcement schreiben | Hoch | Sprint 1 |
| Onboarding-Text «Keys werden nicht synchronisiert, bei Gerätewechsel neu eingeben» | Mittel | Sprint 4 |
| Biometrie-Gate (`SecAccessControl`) für v1.0 erwägen | Niedrig | vor v1.0 |
| Access Group für ggf. Watch-App in v2.X — separates ADR | Niedrig | v2 Planung |
