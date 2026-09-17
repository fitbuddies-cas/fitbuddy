import Foundation
import OSLog
import SwiftData

/// Builds the app's single `ModelContainer` and applies the on-device
/// hardening ADR-001 requires — none of which is a SwiftData default.
///
/// Three measures, all driven by QA-1 (health data must not leave the device):
/// CloudKit sync off, the store file excluded from iCloud backups, and file
/// protection raised to `.complete` so the SQLite file is unreadable while the
/// device is locked.
enum ModelContainerFactory {
    /// Every `@Model` type the app stores, as the current schema version
    /// declares them (#141). Earlier additions — `AnalysisResult` (#97), its
    /// `id` and `sessionCount` — rode on SwiftData's implicit lightweight
    /// migration; from `FitBuddySchemaV2` on, versions are explicit and
    /// `FitBuddyMigrationPlan` says how a store moves between them.
    static let schema = Schema(versionedSchema: FitBuddySchemaV3.self)

    private static let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "ModelContainer")

    /// Creates the on-disk container used by the app.
    ///
    /// - Parameter storeURL: Overrides the default store location. Only tests
    ///   pass it, so they can exercise the hardening without touching — or
    ///   leaving behind — the host app's real store.
    static func makePersistent(storeURL: URL? = nil) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        }
        // SwiftData's default store lives in Application Support, which does
        // not exist in a fresh app container — create it before the store,
        // otherwise the first launch falls back to an in-memory cache that
        // silently loses the offline data (US-2 AC2).
        try FileManager.default.createDirectory(
            at: configuration.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // The plan is what lets a store written by the previous build open
        // under this one; the in-memory container below never has a previous
        // build to migrate from.
        let container = try ModelContainer(
            for: schema,
            migrationPlan: FitBuddyMigrationPlan.self,
            configurations: configuration
        )
        harden(storeURL: configuration.url)
        return container
    }

    /// Creates a throwaway in-memory container (tests, previews).
    static func makeInMemory() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// Creates the app container, degrading to an in-memory store if the disk
    /// store cannot be opened.
    ///
    /// A corrupted or unreadable store must not brick the app at launch: the
    /// user keeps a working session and only loses the offline cache, which the
    /// next sync refills.
    static func makeShared() -> ModelContainer {
        do {
            return try makePersistent()
        } catch {
            logger.error("Persistent store unavailable, falling back to in-memory: \(error, privacy: .public)")
            do {
                return try makeInMemory()
            } catch {
                // An in-memory store has no I/O left to fail on; if SwiftData
                // cannot build the schema itself, the app cannot run at all.
                fatalError("Unable to create a SwiftData container: \(error)")
            }
        }
    }

    /// Applies backup exclusion and file protection to the store, its SQLite
    /// sidecars, and the directory holding them.
    ///
    /// The directory is hardened first and on purpose: SQLite creates `-wal`
    /// and `-shm` lazily, *after* this runs on a fresh install, and those files
    /// hold recently written health data. Files inherit their directory's
    /// protection class, and excluding the directory excludes everything
    /// created inside it — so the sidecars are covered from the first write on.
    ///
    /// Failures are logged, not thrown: the app stays usable and the gap is
    /// visible in the log.
    private static func harden(storeURL: URL) {
        let fileManager = FileManager.default
        let directory = storeURL.deletingLastPathComponent()
        // SQLite names its sidecars with a suffix (`default.store-wal`), not a
        // path extension — `appendingPathExtension` would build a file that
        // never exists.
        let urls = [directory,
                    storeURL,
                    URL(fileURLWithPath: storeURL.path + "-wal"),
                    URL(fileURLWithPath: storeURL.path + "-shm")]

        for url in urls where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: url.path
                )
            } catch {
                logger.error("File protection not applied to \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            }

            var mutableURL = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            do {
                try mutableURL.setResourceValues(values)
            } catch {
                logger.error("Backup exclusion not applied to \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            }
        }
    }
}
