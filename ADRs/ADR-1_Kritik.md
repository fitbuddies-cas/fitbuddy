# ADR-1 — Kritischer Review

*Review zu `ADR-1_local-database.md` (SwiftData als lokale Persistenzschicht). Strukturiert entlang von vier Leitfragen. Priorisiert, nicht erschöpfend.*

---

## 1. Was nicht bedacht wurde

**Die grösste Lücke: iCloud-Backup ≠ iCloud-Sync.** Das ADR verspricht „kein iCloud-Sync, Daten verlassen das Gerät nie". Aber der SwiftData-Store liegt standardmässig in `Application Support` und wird damit **automatisch ins iCloud-Geräte-Backup aufgenommen** — solange nicht `isExcludedFromBackup` gesetzt ist. Gesundheitsdaten landen so doch auf Apple-Servern. Das widerspricht direkt dem Consent-Text (US-4 AC4) und ist eine echte nDSG-Lücke. CloudKit-Sync zu deaktivieren reicht nicht.

**Verschlüsselung ist schwächer als behauptet.** Der Default-Schutz für App-Dateien ist `NSFileProtectionCompleteUntilFirstUserAuthentication`, nicht `…Complete`. Heisst: nach dem ersten Entsperren seit Boot sind die Daten entschlüsselbar — auch bei wieder gesperrtem Gerät. SwiftData bringt **keine** App-Level-Verschlüsselung (kein SQLCipher) mit. Die Positiv-Konsequenz „verschlüsselt" überzeichnet QA-1.

**Dedup/Upsert fehlt komplett.** Wie werden Hevy-Workouts beim Re-Sync mit gecachten `Activity`-Objekten abgeglichen? `@Attribute(.unique)` für Upsert? Genau dieser Mechanismus war in SwiftData 17.x fehlerhaft. Das ist die Kern-Schreiboperation des Caches und wird nirgends adressiert.

**Concurrency-Modell.** `ModelContext` ist nicht `Sendable`. Netzwerk-Sync und AI-Engine schreiben aus Background-Tasks → man braucht `ModelActor`. Das ist die eigentliche Reliability-Herausforderung (QA-2), nicht die im ADR genannte Aggregations-Last (bei 360 Objekten irrelevant).

**Testbarkeit** der „Daten löschen"-Cascade und des Offline-Verhaltens — SwiftData ist schwerer isoliert zu testen als Core Data/GRDB. Kein Wort dazu, obwohl es ein DoD-relevantes Feature absichert.

## 2. Fehlende Alternativen

- **Codable-Snapshot in eine Datei** (nicht UserDefaults!). Der Cache ist *read-mostly* und wird bei jedem Sync komplett ersetzt — ein `Codable`-Blob auf Disk erfüllt QA-1/2/3 möglicherweise besser als jede DB. Das ADR wischt das in einer Zeile weg, statt die ehrliche Frage zu stellen: **Brauchen wir überhaupt eine Datenbank?** Bei ~360 Objekten ist das die stärkste ungeprüfte Option.
- **SQLCipher / verschlüsseltes SQLite (via GRDB).** Wenn Privacy QA-1 *ist*, ist die Option, die Verschlüsselung *unabhängig vom Lock-State* liefert, ausgerechnet nicht ernsthaft geprüft.
- **URLCache / HTTP-Caching** für einen reinen API-Cache — die leichteste Variante, gar nicht erwähnt.

## 3. Konsequenzen — vollständig & realistisch?

Teils überzeichnet, teils unvollständig:

- **Lock-in überschätzt.** „Wechsel zu Core Data nicht trivial" stimmt so nicht — SwiftData *ist* Core Data unter der Haube und teilt das Store-Format; beide können koexistierend denselben Store öffnen. Der Eskalationspfad ist deutlich sanfter als dargestellt.
- **„Daten verlassen das Gerät nie" / „verschlüsselt"** — beide nicht haltbar (siehe Frage 1).
- **Fehlende Negativ-Konsequenzen:** Concurrency-Komplexität, Testbarkeit, kleinere Community/weniger Doku bei Blockern.
- Die genannte Aggregations-/Main-Thread-Last ist bei dieser Datenmenge ein Scheinrisiko — sie füllt einen Negativ-Punkt, während die realen Risiken fehlen.

## 4. Grösstes Risiko

Zwei Kandidaten, beide klar benannt:

**Grösstes Produkt-Risiko (Hauptpunkt): Die Privacy-Versprechen-Lücke.** Privacy ist laut allen Docs *das* Produkt. Ein einziges vergessenes `isExcludedFromBackup`-Flag plus die überschätzte Verschlüsselung bedeuten, dass Gesundheitsdaten entgegen dem Consent-Text doch das Gerät verlassen. Das trifft nicht die Technik, sondern die zentrale Wertversprechung und die nDSG-Konformität — und das ADR macht es heute unsichtbar, weil es „Privacy by Default" als *erledigten Vorteil* verbucht.

**Grösstes Liefer-Risiko: die nicht hedgebare Doppel-Wette** aus iOS-17-Minimum *und* unreifem Migrations-Tooling. Trifft ein SwiftData-Blocker in Sprint 3, bleibt im 3-Monats-Fenster kaum Zeit, die Persistenzschicht neu zu schreiben — und SwiftData-Bugs sind schwer zu debuggen. Für einen TestFlight-PoC mit kleinen Datenmengen und kontrollierten Geräten ist diese Wette aber vertretbar; die Privacy-Lücke ist es nicht.

---

## Empfohlene Anpassungen am ADR

- iCloud-Backup-Exclusion (`isExcludedFromBackup`) + Verschlüsselungs-Realität in QA-1 korrigieren
- Dedup/Upsert und Concurrency (`ModelActor`) als offene Punkte ergänzen
- Codable-Snapshot und SQLCipher als ernsthafte Alternativen aufnehmen
- Lock-in-Konsequenz entschärfen (SwiftData/Core-Data teilen das Store-Format)
