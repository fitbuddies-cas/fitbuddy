# ADR-1: Lokale Datenbank / Persistenz-Technologie für den Activity-Cache

**Status:** Proposed
**Datum:** 2026-05-27
**Autor:** FitBuddy Team (CAS ADAI 2026, Modul 3)

---

## Kontext

FitBuddy speichert 90 Tage normalisierte Trainingsdaten (`Activity → Exercise → ExerciseSet`) lokal auf dem Gerät, damit das Dashboard auch ohne Hevy-API-Verbindung nutzbar bleibt (US-2 AC2) und die AI-Analyse (US-3) auf gecachten Daten aufsetzt. iOS bietet dafür mehrere Persistenz-Technologien an — SwiftData, Core Data, GRDB/SQLite (Drittanbieter) sowie UserDefaults/Dateisystem — die sich in Reife, Boilerplate, Query-Mächtigkeit und Mindest-iOS-Version unterscheiden. Die Wahl muss von einem 2–3-köpfigen Team in 3 Monaten umgesetzt und bis zur geplanten Strava-Integration (v1.1) tragfähig sein. Massgeblich sind die drei wichtigsten Quality Attributes aus `REQUIREMENTS_PO.md` §7.

### Entscheidungstreiber — Top-3-QAs

| QA | Anforderung an die Persistenzschicht | Quelle |
|---|---|---|
| **QA-1 Security / Privacy** | Gesundheitsdaten (nDSG Art. 5 lit. c) bleiben ausschliesslich auf dem Gerät, verschlüsselt, kein iCloud-Sync; vollständig löschbar («Daten löschen / Account zurücksetzen») | REQUIREMENTS_PO.md §6, §7 QA-1 |
| **QA-2 Reliability** | Cache überlebt App-Kills (Offline-Dashboard, US-2 AC2), relationales Modell statt UserDefaults, Schema-Evolution für Strava-Daten in v1.1, Queries ohne alles in-memory zu laden | REQUIREMENTS_PO.md §7 QA-2 |
| **QA-3 Maintainability** | Wenig Boilerplate für ein kleines Team in 3 Monaten; ein einziges Modell, das Dashboard und AI-Engine gemeinsam nutzen; saubere Basis für v1.1-Erweiterung | REQUIREMENTS_PO.md §7 QA-3 |

### Geprüfte Optionen

| Option | Einschätzung gegen die Top-3-QAs |
|---|---|
| **SwiftData** *(gewählt)* | Swift-nativ, minimaler Boilerplate (QA-3), SQLite-basierter On-Device-Store in der App-Sandbox (QA-1), relationale `@Model`-Objekte mit Schema-Migration (QA-2). Erfordert iOS 17+. |
| **Core Data** | Erfüllt QA-1/QA-2 ebenso, aber deutlich mehr Boilerplate (`NSManagedObjectContext`, `NSFetchRequest`) → schwächer bei QA-3 für ein kleines Team. |
| **GRDB.swift / SQLite** | Maximale Query-Kontrolle, aber Drittanbieter-Abhängigkeit (Wartungs-/Lizenzrisiko) → schwächer bei QA-3. |
| **UserDefaults / JSON-Dateien** | Kein Schema, keine Relationen, kein effizientes Query → verletzt QA-2 (REQUIREMENTS_PO.md §7 QA-2 schliesst UserDefaults explizit aus). Verworfen. |

---

## Entscheidung

**Wir verwenden SwiftData als lokale Persistenzschicht für den Activity-Cache und setzen das Minimum-Deployment-Target auf iOS 17.**

Wir annotieren das normalisierte Datenmodell (`Activity`, `Exercise`, `ExerciseSet`) mit `@Model` und lassen SwiftData den darunterliegenden SQLite-Store in der App-Sandbox verwalten. Wir konfigurieren einen einzigen `ModelContainer` beim App-Start und reichen den `modelContext` über die SwiftUI-Umgebung an Dashboard und AI-Engine durch. Wir führen keine Drittanbieter-Abhängigkeit ein und deaktivieren iCloud-Sync explizit, sodass die Daten das Gerät nicht verlassen. Den Sync-Zeitstempel (US-2 AC2) halten wir leichtgewichtig in UserDefaults. Wir richten SwiftData vor Sprint 2 (US-2) ein, damit US-3 ohne Refactor auf demselben Modell aufbaut.

---

## Konsequenzen

### + Positiv

- **(QA-1) Privacy by Default:** Der SQLite-Store liegt in der App-Sandbox, ist durch iOS-Dateisystemschutz verschlüsselt und wird ohne iCloud-Sync konfiguriert — Gesundheitsdaten verlassen das Gerät nie, und das «Daten löschen»-Feature wird zu einem einzigen `ModelContext`-Delete.
- **(QA-2) Verlässlicher Offline-Cache mit Migrationspfad:** Ein echter relationaler Store überlebt App-Kills, sodass das Dashboard offline lädt (US-2 AC2); `@Relationship` bildet `Activity → Exercise → ExerciseSet` sauber ab, und das `VersionedSchema`-Modell trägt die Strava-Erweiterung in v1.1 ohne Datenverlust.
- **(QA-3) Minimaler Wartungsaufwand:** `@Model`, `@Query` und `modelContext.insert()` ersetzen den umfangreichen Core-Data-Stack — für ein 2–3-Personen-Team in 3 Monaten direkt produktivitätsrelevant, ohne Drittanbieter-Abhängigkeit im `Package.resolved`.
- **Performance ausreichend:** ~360 `Activity`- und ~3 600 `Exercise`-Objekte (90 Tage) liegen weit unter jeder SwiftData/SQLite-Grenze.

### - Negativ

- **(QA-3-Risiko) iOS 17 als Mindestanforderung:** SwiftData verlangt iOS 17+; ältere Geräte (z. B. iPhone 8) fallen weg. Für TestFlight-Distribution an eine technikaffine PoC-Zielgruppe vertretbar, muss aber als Produktanforderung dokumentiert werden.
- **(QA-2-Risiko) Junges Framework, Migrations-Tooling weniger erprobt:** SwiftData hatte in iOS 17.0–17.2 Bugs (u. a. Relationship-Cascades); das `VersionedSchema`-Migrations-Tooling ist weniger erprobt als Core Data — genau dort, wo die Strava-v1.1-Migration ansetzt. Mitigation: iCloud-Sync ausgeschlossen (umgeht die kritischsten Bugs), Migration in v1.1 frühzeitig testen.
- **(QA-2-Risiko) Weniger Query-Kontrolle als rohes SQL:** Aggregationen (z. B. Gesamtvolumen pro Muskelgruppe über 90 Tage) lassen sich nicht als SQL formulieren und müssen in Swift aggregiert werden — bei Unachtsamkeit Hauptthread-Last. Mitigation: Aggregation in einen `Task` auslagern.
- **Lock-in / Migrationskosten:** Erweist sich SwiftData später als Blocker, ist der Wechsel zu Core Data nicht trivial (andere Modell-Definitionen, anderer Stack). Für den 3-Monats-PoC kein reales Risiko.

---

## Offene Punkte

| Frage | Priorität | Fällig |
|---|---|---|
| Datenschutz-Review: Reicht die Sandbox-Verschlüsselung für nDSG, oder brauchen wir explizit `NSFileProtectionComplete`? | Hoch | vor Sprint 2 |
| Sync-Zeitstempel in UserDefaults vs. eigenes `@Model` | Niedrig | Sprint 2 |
| Cascade-Delete der Relationen testen (Feature «Daten löschen / Account zurücksetzen») | Mittel | Sprint 2 / 4 |
| SwiftData-`VersionedSchema`-Migration vor Strava-Integration durchspielen | Mittel | vor v1.1 |
