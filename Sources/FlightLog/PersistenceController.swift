import CryptoKit
import CoreData
import Darwin
import Foundation
import SQLite3
import SwiftData

enum FlightLogMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FlightLogSchemaV1.self, FlightLogSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .custom(
                fromVersion: FlightLogSchemaV1.self,
                toVersion: FlightLogSchemaV2.self,
                willMigrate: nil,
                didMigrate: { _ in }
            )
        ]
    }
}

enum ProfileStoreBootstrap {
    typealias Save = (ModelContext) throws -> Void

    static func repair(
        in context: ModelContext,
        save: Save = { try $0.save() }
    ) throws {
        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        var availableProfiles = profiles
        var hasChanges = false
        if availableProfiles.isEmpty {
            let defaultProfile = UserProfile(
                id: UserProfileDefaults.id,
                displayName: UserProfileDefaults.displayName,
                sortOrder: 0,
                comparisonColorRawValue:
                    UserProfileDefaults.comparisonColorRawValue
            )
            context.insert(defaultProfile)
            availableProfiles = [defaultProfile]
            hasChanges = true
        }
        let fallback = availableProfiles.first(where: {
            $0.id == UserProfileDefaults.id
        }) ?? availableProfiles.sorted(by: stableProfileOrder).first!
        let profileIDs = Set(availableProfiles.map(\.id))

        let records = try context.fetch(FetchDescriptor<FlightRecord>())
        for record in records {
            guard
                let ownerProfileID = record.ownerProfileID,
                profileIDs.contains(ownerProfileID)
            else {
                record.ownerProfileID = fallback.id
                hasChanges = true
                continue
            }
        }
        if hasChanges {
            try save(context)
        }
    }

    private static func stableProfileOrder(
        _ lhs: UserProfile,
        _ rhs: UserProfile
    ) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct PersistenceController {
    static let applicationDirectoryName = "FlightLog"
    static let storeFileName = "FlightLog.store"

    static var defaultStoreURL: URL {
        applicationSupportURL
            .appendingPathComponent(
                applicationDirectoryName,
                isDirectory: true
            )
            .appendingPathComponent(storeFileName)
    }

    static var defaultLegacyMigrationConfiguration:
        LegacyStoreMigrationConfiguration
    {
        let flightLogDirectory = defaultStoreURL.deletingLastPathComponent()
        return LegacyStoreMigrationConfiguration(
            sourceStoreURL: applicationSupportURL
                .appendingPathComponent("default.store"),
            backupDirectoryURL: flightLogDirectory
                .appendingPathComponent("LegacyBackups", isDirectory: true),
            markerURL: flightLogDirectory
                .appendingPathComponent(
                    ".legacy-default-store-imported-v1.json"
                )
        )
    }

    let container: ModelContainer
    let storeURL: URL

    init(
        storeURL: URL = Self.defaultStoreURL,
        bootstrapSave: @escaping ProfileStoreBootstrap.Save = {
            try $0.save()
        },
        migrationRestoreFault: @escaping V1MigrationRestoreFault = { _ in },
        migrationTransactionFault: @escaping V1MigrationTransactionFault = {
            _ in
        }
    ) throws {
        try self.init(
            storeURL: storeURL,
            allowsSave: true,
            bootstrapSave: bootstrapSave,
            migrationRestoreFault: migrationRestoreFault,
            migrationTransactionFault: migrationTransactionFault
        )
    }

    private init(
        storeURL: URL,
        allowsSave: Bool,
        bootstrapSave: @escaping ProfileStoreBootstrap.Save,
        migrationRestoreFault: @escaping V1MigrationRestoreFault,
        migrationTransactionFault: @escaping V1MigrationTransactionFault
    ) throws {
        self.storeURL = storeURL
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if allowsSave {
            try V1MigrationStoreBackup.recoverPendingIfNeeded(
                storeURL: storeURL,
                restoreFault: migrationRestoreFault,
                transactionFault: migrationTransactionFault
            )
        }
        let migrationBackup = allowsSave
            ? try V1MigrationStoreBackup.makeIfNeeded(storeURL: storeURL)
            : nil
        let schema = Schema(versionedSchema: FlightLogSchemaV2.self)
        let configuration = ModelConfiguration(
            "FlightLog",
            schema: schema,
            url: storeURL,
            allowsSave: allowsSave
        )
        var candidateContainer: ModelContainer?
        do {
            candidateContainer = try ModelContainer(
                for: schema,
                migrationPlan: FlightLogMigrationPlan.self,
                configurations: configuration
            )
            if allowsSave, let candidateContainer {
                try ProfileStoreBootstrap.repair(
                    in: ModelContext(candidateContainer),
                    save: bootstrapSave
                )
            }
            guard let candidateContainer else {
                throw CocoaError(.fileReadUnknown)
            }
            try migrationBackup?.commit(fault: migrationTransactionFault)
            container = candidateContainer
        } catch {
            candidateContainer = nil
            if let migrationBackup, migrationBackup.isActive {
                do {
                    try migrationBackup.restore(
                        fault: migrationRestoreFault,
                        transactionFault: migrationTransactionFault
                    )
                } catch let restoreError {
                    throw V1MigrationStoreBackupError.restoreFailed(
                        original: error.localizedDescription,
                        restore: restoreError.localizedDescription
                    )
                }
            }
            throw error
        }
    }

    static func readOnly(storeURL: URL) throws
        -> PersistenceController
    {
        try PersistenceController(
            storeURL: storeURL,
            allowsSave: false,
            bootstrapSave: { try $0.save() },
            migrationRestoreFault: { _ in },
            migrationTransactionFault: { _ in }
        )
    }

    private static var applicationSupportURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support",
                isDirectory: true
            )
    }
}

enum V1MigrationStoreBackupError: LocalizedError {
    case backupValidationFailed(String)
    case restoreFailed(original: String, restore: String)

    var errorDescription: String? {
        switch self {
        case .backupValidationFailed(let reason):
            "V1 迁移备份校验失败，未尝试迁移：\(reason)"
        case .restoreFailed(let original, let restore):
            "V1 迁移失败（\(original)），且原 store 恢复失败：\(restore)"
        }
    }
}

enum V1MigrationRestorePoint: String, CaseIterable, Sendable {
    case stagingCopy
    case stagingVerify
    case beforeReplaceMain
    case afterReplaceMain
    case replaceWAL
    case replaceSHM
    case quarantineExtraSidecar
    case finalVerify
    case cleanup
}

typealias V1MigrationRestoreFault = (V1MigrationRestorePoint) throws -> Void

enum V1MigrationTransactionPoint: String, Sendable {
    case beforeCommitRename
    case afterCommitRenameBeforeDelete
    case afterRecoveryRenameBeforeDelete
}

typealias V1MigrationTransactionFault =
    (V1MigrationTransactionPoint) throws -> Void

private final class V1MigrationStoreBackup {
    private struct Entry: Codable {
        let suffix: String
        let size: UInt64
        let modificationSeconds: Int64
        let modificationNanoseconds: Int64
        let sha256: String
    }

    private struct Manifest: Codable {
        let storeFileName: String
        let entries: [Entry]
    }

    private static let publishedV1Hash =
        Data(base64Encoded: "r8AG8DwtP4EIhUTj9H5Jr6rgexvXIF0q8Eo41nDFfDA=")!
    private static let suffixes = ["", "-wal", "-shm"]
    private static let manifestFileName = "manifest.json"

    private let storeURL: URL
    private let backupDirectory: URL
    private let entries: [Entry]

    var isActive: Bool {
        FileManager.default.fileExists(atPath: backupDirectory.path)
    }

    static func recoverPendingIfNeeded(
        storeURL: URL,
        restoreFault: V1MigrationRestoreFault,
        transactionFault: V1MigrationTransactionFault
    ) throws {
        let parent = storeURL.deletingLastPathComponent()
        let prefix = ".\(storeURL.lastPathComponent).migration-backup-"
        let candidates = try FileManager.default.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix(prefix)
                && $0.hasDirectoryPath
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for directory in candidates {
            let manifestURL = directory.appendingPathComponent(
                manifestFileName
            )
            guard FileManager.default.fileExists(atPath: manifestURL.path) else {
                try FileManager.default.removeItem(at: directory)
                continue
            }
            let manifest = try JSONDecoder().decode(
                Manifest.self,
                from: Data(contentsOf: manifestURL)
            )
            guard manifest.storeFileName == storeURL.lastPathComponent else {
                throw V1MigrationStoreBackupError.backupValidationFailed(
                    "manifest store 名称不匹配"
                )
            }
            let backup = V1MigrationStoreBackup(
                storeURL: storeURL,
                backupDirectory: directory,
                entries: manifest.entries
            )
            try backup.validateOriginalBackup()
            try backup.restore(
                fault: restoreFault,
                transactionFault: transactionFault
            )
        }
        cleanupTombstones(storeURL: storeURL)
    }

    static func makeIfNeeded(storeURL: URL) throws
        -> V1MigrationStoreBackup?
    {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return nil
        }
        let metadata = try readMetadataWithoutSideEffects(storeURL)
        guard
            let hashes = metadata[
                NSStoreModelVersionHashesKey
            ] as? [String: Data],
            hashes.count == 1,
            hashes["FlightRecord"] == publishedV1Hash
        else {
            return nil
        }
        return try V1MigrationStoreBackup(storeURL: storeURL)
    }

    private static func readMetadataWithoutSideEffects(
        _ storeURL: URL
    ) throws -> [String: Any] {
        var database: OpaquePointer?
        let uri = "file:\(storeURL.path)?immutable=1"
        let openResult = sqlite3_open_v2(
            uri,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_URI,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            defer { sqlite3_close(database) }
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                database,
                "SELECT Z_PLIST FROM Z_METADATA LIMIT 1",
                -1,
                &statement,
                nil
            ) == SQLITE_OK,
            let statement
        else {
            sqlite3_finalize(statement)
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let data = Data(bytes: bytes, count: count)
        guard
            let metadata = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return metadata
    }

    private init(storeURL: URL) throws {
        self.storeURL = storeURL
        backupDirectory = storeURL.deletingLastPathComponent()
            .appendingPathComponent(
                ".\(storeURL.lastPathComponent).migration-backup-\(UUID())",
                isDirectory: true
            )
        do {
            try FileManager.default.createDirectory(
                at: backupDirectory,
                withIntermediateDirectories: false
            )
            var captured: [Entry] = []
            for suffix in Self.suffixes {
                let source = URL(fileURLWithPath: storeURL.path + suffix)
                guard FileManager.default.fileExists(atPath: source.path) else {
                    continue
                }
                let attributes = try FileManager.default.attributesOfItem(
                    atPath: source.path
                )
                let modificationTime = try Self.modificationTime(source)
                let entry = Entry(
                    suffix: suffix,
                    size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
                    modificationSeconds: Int64(modificationTime.tv_sec),
                    modificationNanoseconds: Int64(modificationTime.tv_nsec),
                    sha256: try Self.sha256(source)
                )
                let destination = backupDirectory.appendingPathComponent(
                    storeURL.lastPathComponent + suffix
                )
                try FileManager.default.copyItem(
                    at: source,
                    to: destination
                )
                guard
                    try Self.sha256(destination) == entry.sha256,
                    Self.fileSize(destination) == entry.size
                else {
                    throw V1MigrationStoreBackupError
                        .backupValidationFailed(source.lastPathComponent)
                }
                captured.append(entry)
            }
            guard captured.contains(where: { $0.suffix.isEmpty }) else {
                throw V1MigrationStoreBackupError
                    .backupValidationFailed("缺少主 store")
            }
            entries = captured
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(
                Manifest(
                    storeFileName: storeURL.lastPathComponent,
                    entries: captured
                )
            ).write(
                to: backupDirectory.appendingPathComponent(
                    Self.manifestFileName
                ),
                options: .atomic
            )
        } catch {
            try? FileManager.default.removeItem(at: backupDirectory)
            throw error
        }
    }

    private init(
        storeURL: URL,
        backupDirectory: URL,
        entries: [Entry]
    ) {
        self.storeURL = storeURL
        self.backupDirectory = backupDirectory
        self.entries = entries
    }

    func commit(fault: V1MigrationTransactionFault) throws {
        try fault(.beforeCommitRename)
        let tombstone = tombstoneURL(kind: "committed")
        try Self.atomicRename(from: backupDirectory, to: tombstone)
        try fault(.afterCommitRenameBeforeDelete)
        try? FileManager.default.removeItem(at: tombstone)
    }

    func restore(
        fault: V1MigrationRestoreFault,
        transactionFault: V1MigrationTransactionFault
    ) throws {
        let fileManager = FileManager.default
        let originalSuffixes = Set(entries.map(\.suffix))
        try validateOriginalBackup()
        let stagingDirectory = backupDirectory.appendingPathComponent(
            "staging",
            isDirectory: true
        )
        if fileManager.fileExists(atPath: stagingDirectory.path) {
            try fileManager.removeItem(at: stagingDirectory)
        }
        try fileManager.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: false
        )

        for entry in entries {
            try fault(.stagingCopy)
            let backup = backupDirectory.appendingPathComponent(
                storeURL.lastPathComponent + entry.suffix
            )
            let staging = stagingDirectory.appendingPathComponent(
                storeURL.lastPathComponent + entry.suffix
            )
            try fileManager.copyItem(at: backup, to: staging)
            try Self.setModificationTime(
                staging,
                seconds: entry.modificationSeconds,
                nanoseconds: entry.modificationNanoseconds
            )
        }
        try fault(.stagingVerify)
        for entry in entries {
            let staging = stagingDirectory.appendingPathComponent(
                storeURL.lastPathComponent + entry.suffix
            )
            guard
                try Self.sha256(staging) == entry.sha256,
                Self.fileSize(staging) == entry.size
            else {
                throw V1MigrationStoreBackupError
                    .backupValidationFailed(
                        "恢复 staging 校验失败：\(entry.suffix)"
                    )
            }
        }

        let extraSuffixes = Self.suffixes.filter {
            !originalSuffixes.contains($0)
                && fileManager.fileExists(
                    atPath: URL(fileURLWithPath: storeURL.path + $0).path
                )
        }
        if !extraSuffixes.isEmpty {
            try fault(.quarantineExtraSidecar)
            let quarantineDirectory = backupDirectory.appendingPathComponent(
                "quarantine",
                isDirectory: true
            )
            try fileManager.createDirectory(
                at: quarantineDirectory,
                withIntermediateDirectories: true
            )
            for suffix in extraSuffixes {
                let live = URL(fileURLWithPath: storeURL.path + suffix)
                let quarantined = quarantineDirectory.appendingPathComponent(
                    "\(storeURL.lastPathComponent)\(suffix)-\(UUID())"
                )
                try Self.atomicRename(from: live, to: quarantined)
                guard !fileManager.fileExists(atPath: live.path) else {
                    throw V1MigrationStoreBackupError
                        .backupValidationFailed("额外 sidecar 隔离失败：\(suffix)")
                }
            }
        }

        for entry in entries {
            switch entry.suffix {
            case "":
                try fault(.beforeReplaceMain)
            case "-wal":
                try fault(.replaceWAL)
            case "-shm":
                try fault(.replaceSHM)
            default:
                break
            }
            let staging = stagingDirectory.appendingPathComponent(
                storeURL.lastPathComponent + entry.suffix
            )
            let live = URL(fileURLWithPath: storeURL.path + entry.suffix)
            try Self.atomicRename(from: staging, to: live)
            guard
                try Self.sha256(live) == entry.sha256,
                Self.fileSize(live) == entry.size
            else {
                throw V1MigrationStoreBackupError
                    .backupValidationFailed("atomic replace 校验失败：\(entry.suffix)")
            }
            if entry.suffix.isEmpty {
                try fault(.afterReplaceMain)
            }
        }

        try fault(.finalVerify)
        try verifyLiveExactSet()
        try fault(.cleanup)
        let tombstone = tombstoneURL(kind: "recovered")
        try Self.atomicRename(from: backupDirectory, to: tombstone)
        try transactionFault(.afterRecoveryRenameBeforeDelete)
        try? fileManager.removeItem(at: tombstone)
    }

    private func tombstoneURL(kind: String) -> URL {
        let baseName = storeURL.deletingPathExtension().lastPathComponent
        return storeURL.deletingLastPathComponent().appendingPathComponent(
            ".\(baseName)-migration-\(kind)-\(UUID())",
            isDirectory: true
        )
    }

    private static func cleanupTombstones(storeURL: URL) {
        let baseName = storeURL.deletingPathExtension().lastPathComponent
        let prefixes = [
            ".\(baseName)-migration-committed-",
            ".\(baseName)-migration-recovered-",
        ]
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: storeURL.deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            )
        else {
            return
        }
        for tombstone in contents where prefixes.contains(where: {
            tombstone.lastPathComponent.hasPrefix($0)
        }) {
            try? FileManager.default.removeItem(at: tombstone)
        }
    }

    private func validateOriginalBackup() throws {
        for entry in entries {
            let backup = backupDirectory.appendingPathComponent(
                storeURL.lastPathComponent + entry.suffix
            )
            guard
                try Self.sha256(backup) == entry.sha256,
                Self.fileSize(backup) == entry.size
            else {
                throw V1MigrationStoreBackupError
                    .backupValidationFailed("原始备份校验失败：\(entry.suffix)")
            }
        }
    }

    private func verifyLiveExactSet() throws {
        let fileManager = FileManager.default
        let originals = Set(entries.map(\.suffix))
        for suffix in Self.suffixes {
            let live = URL(fileURLWithPath: storeURL.path + suffix)
            let exists = fileManager.fileExists(atPath: live.path)
            guard exists == originals.contains(suffix) else {
                throw V1MigrationStoreBackupError
                    .backupValidationFailed("最终 file set 不一致：\(suffix)")
            }
        }
        for entry in entries {
            let live = URL(fileURLWithPath: storeURL.path + entry.suffix)
            let modification = try Self.modificationTime(live)
            guard
                try Self.sha256(live) == entry.sha256,
                Self.fileSize(live) == entry.size,
                Int64(modification.tv_sec) == entry.modificationSeconds,
                Int64(modification.tv_nsec) == entry.modificationNanoseconds
            else {
                throw V1MigrationStoreBackupError
                    .backupValidationFailed("最终 live 校验失败：\(entry.suffix)")
            }
        }
    }

    private static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()
    }

    private static func fileSize(_ url: URL) -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
        )
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private static func modificationTime(_ url: URL) throws -> timespec {
        var value = stat()
        guard lstat(url.path, &value) == 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        return value.st_mtimespec
    }

    private static func setModificationTime(
        _ url: URL,
        seconds: Int64,
        nanoseconds: Int64
    ) throws {
        var times = [
            timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)),
            timespec(
                tv_sec: Int(seconds),
                tv_nsec: Int(nanoseconds)
            ),
        ]
        let result = url.path.withCString { path in
            utimensat(AT_FDCWD, path, &times, 0)
        }
        guard result == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private static func atomicRename(from source: URL, to destination: URL)
        throws
    {
        let result = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard result == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

enum LegacyStoreRecordReader {
    static func read(from storeURL: URL) throws -> [FlightRecordBackupDTO] {
        do {
            let schema = Schema([FlightRecord.self])
            let container = try readOnlyContainer(
                schema: schema,
                storeURL: storeURL
            )
            return try ModelContext(container)
                .fetch(FetchDescriptor<FlightRecord>())
                .map(FlightRecordBackupDTO.init)
        } catch {
            do {
                let schema = Schema(versionedSchema: FlightLogSchemaV2.self)
                let container = try readOnlyContainer(
                    schema: schema,
                    storeURL: storeURL
                )
                return try ModelContext(container)
                    .fetch(FetchDescriptor<FlightRecord>())
                    .map(FlightRecordBackupDTO.init)
            } catch {
                let schema = Schema(versionedSchema: FlightLogSchemaV1.self)
                let container = try readOnlyContainer(
                    schema: schema,
                    storeURL: storeURL
                )
                return try ModelContext(container)
                    .fetch(FetchDescriptor<FlightLogSchemaV1.FlightRecord>())
                    .map(FlightRecordBackupDTO.init)
            }
        }
    }

    private static func readOnlyContainer(
        schema: Schema,
        storeURL: URL
    ) throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(
                "LegacyFlightLogReadOnly",
                schema: schema,
                url: storeURL,
                allowsSave: false
            )
        )
    }
}

struct PersistenceRecoveryContent {
    let title = "无法打开航班日志"
    let message: String
    let recoverySuggestion: String

    init(error: Error) {
        message = "数据存储无法创建或打开：\(error.localizedDescription)"
        recoverySuggestion = "请确认磁盘空间和文件权限后重新启动应用；原数据不会被自动删除。"
    }
}

enum FlightLogWindowPolicy {
    static let usesSingleWindow = true
}

struct LegacyImportPresentation {
    let title = "发现旧版 FlightLog 数据"
    let message: String

    init(recordCount: Int) {
        message = "已先备份旧数据库，并识别到 \(recordCount) 条 FlightLog 航班记录。可以去重导入专属数据库；无论是否导入，原数据库都会保留。"
    }
}

struct LegacyStoreMigrationConfiguration: Sendable {
    let sourceStoreURL: URL
    let backupDirectoryURL: URL
    let markerURL: URL
}

struct LegacyFlightImportCandidate: Sendable {
    let sourceStoreURL: URL
    let backupStoreURL: URL
    let sourceFingerprint: String
    let records: [FlightRecordBackupDTO]
    let normalizedFlightDateCount: Int
    let sourceMetadata: LegacyStoreMetadata
}

struct LegacyStoreMetadata: Codable, Equatable, Sendable {
    struct File: Codable, Equatable, Sendable {
        let suffix: String
        let size: UInt64
        let modificationTime: TimeInterval
        let inode: UInt64
    }
    let files: [File]
}

protocol LegacyStoreFileAccess: Sendable {
    func metadata(for storeURL: URL) throws -> LegacyStoreMetadata
    func contentFingerprint(for storeURL: URL) throws -> String
}

struct SystemLegacyStoreFileAccess: LegacyStoreFileAccess {
    func metadata(for storeURL: URL) throws -> LegacyStoreMetadata {
        let fileManager = FileManager.default
        let files: [LegacyStoreMetadata.File] = try ["", "-wal"].compactMap {
            suffix -> LegacyStoreMetadata.File? in
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return LegacyStoreMetadata.File(
                suffix: suffix,
                size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
                modificationTime:
                    (attributes[.modificationDate] as? Date)?
                    .timeIntervalSince1970 ?? 0,
                inode:
                    (attributes[.systemFileNumber] as? NSNumber)?
                    .uint64Value ?? 0
            )
        }
        return LegacyStoreMetadata(files: files)
    }

    func contentFingerprint(for storeURL: URL) throws -> String {
        var hasher = SHA256()
        for suffix in ["", "-wal"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            guard FileManager.default.fileExists(atPath: url.path) else {
                continue
            }
            hasher.update(data: Data(suffix.utf8))
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            while true {
                let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
        }
        return hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()
    }
}

enum LegacyStoreStatus: String, Codable, Equatable, Sendable {
    case noData
    case incompatible
    case deferred
    case migrated
    case failed
}

struct LegacyStoreInspectionState: Codable, Equatable, Sendable {
    let sourceFingerprint: String
    let status: LegacyStoreStatus
    let backupStorePath: String?
    let message: String?
    let updatedAt: Date
    let sourceMetadata: LegacyStoreMetadata?
}

enum LegacyStoreMigrationError: LocalizedError {
    case markerWriteFailed(String)
    case rollbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .markerWriteFailed(let reason):
            "旧数据导入标记写入失败，已撤销本次导入：\(reason)"
        case .rollbackFailed(let reason):
            "旧数据导入失败，且无法恢复导入前状态：\(reason)"
        }
    }
}

struct LegacyStoreInspectionCoordinator: Sendable {
    let fileAccess: any LegacyStoreFileAccess

    init(
        fileAccess: any LegacyStoreFileAccess = SystemLegacyStoreFileAccess()
    ) {
        self.fileAccess = fileAccess
    }

    func inspect(
        _ configuration: LegacyStoreMigrationConfiguration,
        forceRetry: Bool = false
    ) async throws -> LegacyFlightImportCandidate? {
        let access = fileAccess
        return try await Task.detached(priority: .utility) {
            let metadata = try access.metadata(
                for: configuration.sourceStoreURL
            )
            if
                !forceRetry,
                try LegacyStoreMigrationService.currentState(configuration)?
                    .sourceMetadata == metadata
            {
                return nil
            }
            return try LegacyStoreMigrationService.inspect(
                configuration,
                forceRetry: forceRetry,
                fileAccess: access,
                knownMetadata: metadata
            )
        }.value
    }
}

enum LegacyStoreMigrationService {
    static func inspect(
        _ configuration: LegacyStoreMigrationConfiguration,
        fileManager: FileManager = .default,
        forceRetry: Bool = false,
        fileAccess: any LegacyStoreFileAccess = SystemLegacyStoreFileAccess(),
        knownMetadata: LegacyStoreMetadata? = nil
    ) throws -> LegacyFlightImportCandidate? {
        guard
            fileManager.fileExists(
                atPath: configuration.sourceStoreURL.path
            )
        else {
            return nil
        }
        let metadata = try knownMetadata
            ?? fileAccess.metadata(for: configuration.sourceStoreURL)
        if
            !forceRetry,
            try currentState(configuration)?.sourceMetadata == metadata
        {
            return nil
        }
        let fingerprint = try fileAccess.contentFingerprint(
            for: configuration.sourceStoreURL
        )
        if
            !forceRetry,
            let state = try currentState(configuration),
            state.sourceFingerprint == fingerprint
        {
            return nil
        }

        let backupStoreURL: URL
        do {
            backupStoreURL = try backupStoreFiles(
                configuration,
                fileManager: fileManager
            )
        } catch {
            try? writeState(
                status: .failed,
                fingerprint: fingerprint,
                backupStoreURL: nil,
                message: "旧数据库备份失败：\(error.localizedDescription)",
                configuration: configuration,
                sourceMetadata: metadata
            )
            throw error
        }
        do {
            var recordDTOs = try LegacyStoreRecordReader.read(
                from: backupStoreURL
            )
            guard !recordDTOs.isEmpty else {
                try writeState(
                    status: .noData,
                    fingerprint: fingerprint,
                    backupStoreURL: backupStoreURL,
                    message: "旧数据库中没有可导入的 FlightLog 航班记录。",
                    configuration: configuration,
                    sourceMetadata: metadata
                )
                return nil
            }

            var normalizedFlightDateCount = 0
            for index in recordDTOs.indices {
                let localDeparture = HistoricalLocalTime.wallClockDate(
                    snapshot: recordDTOs[index].departureLocalDateTime,
                    absoluteDate: recordDTOs[index].departureDate,
                    timeZoneID: recordDTOs[index].departureTimeZoneID
                )
                let canonical = FlightDateNormalization.canonicalDate(
                    localDeparture
                )
                if recordDTOs[index].flightDate != canonical {
                    recordDTOs[index].flightDate = canonical
                    normalizedFlightDateCount += 1
                }
            }
            let validationData = try BackupService.encodeLegacyV1JSON(
                recordSnapshots: recordDTOs
            )
            _ = try BackupService.prepareLegacyV1Import(
                validationData,
                existingRecordSnapshots: [],
                targetProfileID: UserProfileDefaults.id,
                mode: .merge
            )
            try writeState(
                status: .deferred,
                fingerprint: fingerprint,
                backupStoreURL: backupStoreURL,
                message: "已识别旧数据，等待用户确认导入。",
                configuration: configuration,
                sourceMetadata: metadata
            )
            return LegacyFlightImportCandidate(
                sourceStoreURL: configuration.sourceStoreURL,
                backupStoreURL: backupStoreURL,
                sourceFingerprint: fingerprint,
                records: recordDTOs,
                normalizedFlightDateCount: normalizedFlightDateCount,
                sourceMetadata: metadata
            )
        } catch {
            try writeState(
                status: .incompatible,
                fingerprint: fingerprint,
                backupStoreURL: backupStoreURL,
                message: "旧数据库不兼容，已保留备份；可改用旧版 JSON 导入。",
                configuration: configuration,
                sourceMetadata: metadata
            )
            return nil
        }
    }

    static func currentState(
        _ configuration: LegacyStoreMigrationConfiguration
    ) throws -> LegacyStoreInspectionState? {
        guard FileManager.default.fileExists(
            atPath: configuration.markerURL.path
        ) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            LegacyStoreInspectionState.self,
            from: Data(contentsOf: configuration.markerURL)
        )
    }

    @MainActor
    static func importCandidate(
        _ candidate: LegacyFlightImportCandidate,
        to context: ModelContext,
        targetProfileID: UUID,
        configuration: LegacyStoreMigrationConfiguration,
        markerWriter: (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) throws -> FlightImportReport {
        let allRecords = try context.fetch(FetchDescriptor<FlightRecord>())
        let currentRecords = allRecords.filter {
            $0.ownerProfileID == targetProfileID
        }
        let data = try BackupService.encodeLegacyV1JSON(
            recordSnapshots: candidate.records
        )
        let preparation = try BackupService.prepareLegacyV1Import(
            data,
            existingRecordSnapshots: currentRecords.map(
                FlightRecordBackupDTO.init
            ),
            targetProfileID: targetProfileID,
            mode: .merge
        )
        let existingIDs = Set(allRecords.map(\.id))

        try BackupService.apply(
            preparation,
            to: context,
            targetProfileID: targetProfileID
        )

        do {
            try FileManager.default.createDirectory(
                at: configuration.markerURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let marker = LegacyStoreInspectionState(
                sourceFingerprint: candidate.sourceFingerprint,
                status: .migrated,
                backupStorePath: candidate.backupStoreURL.path,
                message: "旧数据已完成去重导入。",
                updatedAt: .now,
                sourceMetadata: candidate.sourceMetadata
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try markerWriter(
                encoder.encode(marker),
                configuration.markerURL
            )
        } catch {
            do {
                let records = try context.fetch(
                    FetchDescriptor<FlightRecord>()
                )
                for record in records where !existingIDs.contains(record.id) {
                    context.delete(record)
                }
                try context.save()
            } catch {
                context.rollback()
                throw LegacyStoreMigrationError.rollbackFailed(
                    error.localizedDescription
                )
            }
            throw LegacyStoreMigrationError.markerWriteFailed(
                error.localizedDescription
            )
        }

        return preparation.report
    }

    private static func backupStoreFiles(
        _ configuration: LegacyStoreMigrationConfiguration,
        fileManager: FileManager
    ) throws -> URL {
        try fileManager.createDirectory(
            at: configuration.backupDirectoryURL,
            withIntermediateDirectories: true
        )
        let backupSetURL = configuration.backupDirectoryURL
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(
            at: backupSetURL,
            withIntermediateDirectories: true
        )

        let sourceStoreURL = configuration.sourceStoreURL
        let backupStoreURL = backupSetURL.appendingPathComponent(
            sourceStoreURL.lastPathComponent
        )
        try fileManager.copyItem(
            at: sourceStoreURL,
            to: backupStoreURL
        )
        for suffix in ["-wal", "-shm"] {
            let source = URL(
                fileURLWithPath: sourceStoreURL.path + suffix
            )
            guard fileManager.fileExists(atPath: source.path) else {
                continue
            }
            try fileManager.copyItem(
                at: source,
                to: URL(
                    fileURLWithPath: backupStoreURL.path + suffix
                )
            )
        }
        return backupStoreURL
    }

    private static func writeState(
        status: LegacyStoreStatus,
        fingerprint: String,
        backupStoreURL: URL?,
        message: String?,
        configuration: LegacyStoreMigrationConfiguration,
        sourceMetadata: LegacyStoreMetadata
    ) throws {
        try FileManager.default.createDirectory(
            at: configuration.markerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(
            LegacyStoreInspectionState(
                sourceFingerprint: fingerprint,
                status: status,
                backupStorePath: backupStoreURL?.path,
                message: message,
                updatedAt: .now,
                sourceMetadata: sourceMetadata
            )
        ).write(to: configuration.markerURL, options: .atomic)
    }

}
