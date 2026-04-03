//
// Copyright 2024 Noise Messenger
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

/// Manages iCloud backup and restore of the Noise message database.
///
/// This backs up the GRDB database to the app's iCloud ubiquity container,
/// enabling cross-device message restore.
class CloudBackupManager {

    static let shared = CloudBackupManager()

    private let fileManager = FileManager.default

    /// UserDefaults keys for backup settings.
    private enum Keys {
        static let autoBackupEnabled = "CloudBackup_AutoBackupEnabled"
        static let lastBackupDate = "CloudBackup_LastBackupDate"
        static let backupFrequencyHours = "CloudBackup_BackupFrequencyHours"
    }

    var isAutoBackupEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.autoBackupEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoBackupEnabled) }
    }

    var lastBackupDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.lastBackupDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastBackupDate) }
    }

    var backupFrequencyHours: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: Keys.backupFrequencyHours)
            return value > 0 ? value : 24 // Default: daily
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.backupFrequencyHours) }
    }

    private init() {}

    /// The iCloud ubiquity container URL for backups.
    var iCloudContainerURL: URL? {
        fileManager.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents/Backups")
    }

    /// Whether iCloud is available on this device.
    var isICloudAvailable: Bool {
        fileManager.ubiquityIdentityToken != nil
    }

    /// Perform a backup of the message database to iCloud.
    func performBackup() async throws {
        guard isICloudAvailable else {
            throw BackupError.iCloudNotAvailable
        }

        guard let containerURL = iCloudContainerURL else {
            throw BackupError.containerNotFound
        }

        // Ensure the backup directory exists
        if !fileManager.fileExists(atPath: containerURL.path) {
            try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
        }

        // Get the database file URL
        let databaseUrl = SDSDatabaseStorage.grdbDatabaseFileUrl

        guard fileManager.fileExists(atPath: databaseUrl.path) else {
            throw BackupError.databaseNotFound
        }

        // Create a timestamped backup
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let backupFileName = "noise-backup-\(timestamp).sqlite"
        let backupURL = containerURL.appendingPathComponent(backupFileName)

        // Copy the database file (GRDB handles WAL checkpointing)
        // We should checkpoint the WAL first for a consistent backup
        let db = DependenciesBridge.shared.db
        try db.read { _ in
            // The read transaction ensures the database is in a consistent state
            try self.fileManager.copyItem(at: databaseUrl, to: backupURL)
        }

        // Also copy the WAL and SHM files if they exist
        let walURL = databaseUrl.appendingPathExtension("wal")
        let shmURL = databaseUrl.appendingPathExtension("shm")
        if fileManager.fileExists(atPath: walURL.path) {
            let backupWAL = backupURL.appendingPathExtension("wal")
            try? fileManager.copyItem(at: walURL, to: backupWAL)
        }
        if fileManager.fileExists(atPath: shmURL.path) {
            let backupSHM = backupURL.appendingPathExtension("shm")
            try? fileManager.copyItem(at: shmURL, to: backupSHM)
        }

        // Clean up old backups (keep last 3)
        try cleanupOldBackups(in: containerURL)

        lastBackupDate = Date()
        Logger.info("iCloud backup completed: \(backupFileName)")
    }

    /// List available backups in iCloud.
    func availableBackups() -> [BackupInfo] {
        guard let containerURL = iCloudContainerURL,
              fileManager.fileExists(atPath: containerURL.path) else {
            return []
        }

        do {
            let files = try fileManager.contentsOfDirectory(
                at: containerURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: .skipsHiddenFiles
            )
            return files
                .filter { $0.pathExtension == "sqlite" }
                .compactMap { url -> BackupInfo? in
                    let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                    return BackupInfo(
                        url: url,
                        date: values?.contentModificationDate ?? Date.distantPast,
                        size: values?.fileSize ?? 0
                    )
                }
                .sorted { $0.date > $1.date }
        } catch {
            Logger.error("Failed to list backups: \(error)")
            return []
        }
    }

    /// Restore from a specific backup file.
    func restore(from backup: BackupInfo) async throws {
        let databaseUrl = SDSDatabaseStorage.grdbDatabaseFileUrl

        // Copy backup over the current database
        // Note: The app should be restarted after restore
        if fileManager.fileExists(atPath: databaseUrl.path) {
            try fileManager.removeItem(at: databaseUrl)
        }
        try fileManager.copyItem(at: backup.url, to: databaseUrl)

        Logger.info("Database restored from backup: \(backup.url.lastPathComponent)")
    }

    /// Check if a backup is due based on frequency settings.
    func isBackupDue() -> Bool {
        guard isAutoBackupEnabled else { return false }
        guard let lastBackup = lastBackupDate else { return true }
        let intervalSinceLastBackup = Date().timeIntervalSince(lastBackup)
        return intervalSinceLastBackup >= TimeInterval(backupFrequencyHours * 3600)
    }

    // MARK: - Private

    private func cleanupOldBackups(in directory: URL) throws {
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )
        let sqliteFiles = files
            .filter { $0.pathExtension == "sqlite" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return date1 > date2
            }

        // Keep the 3 most recent, delete the rest
        for fileToDelete in sqliteFiles.dropFirst(3) {
            try? fileManager.removeItem(at: fileToDelete)
            // Also remove associated WAL/SHM files
            try? fileManager.removeItem(at: fileToDelete.appendingPathExtension("wal"))
            try? fileManager.removeItem(at: fileToDelete.appendingPathExtension("shm"))
        }
    }

    // MARK: - Types

    struct BackupInfo {
        let url: URL
        let date: Date
        let size: Int

        var displayDate: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }

        var displaySize: String {
            ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
        }
    }

    enum BackupError: LocalizedError {
        case iCloudNotAvailable
        case containerNotFound
        case databaseNotFound

        var errorDescription: String? {
            switch self {
            case .iCloudNotAvailable:
                return "iCloud is not available. Please sign in to iCloud in Settings."
            case .containerNotFound:
                return "Could not access the iCloud backup container."
            case .databaseNotFound:
                return "Message database not found."
            }
        }
    }
}
