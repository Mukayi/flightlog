import CryptoKit
import Foundation
import SwiftData

enum BackupService {
    static let currentSchemaVersion = 2

    static let csvHeaders = [
        "flightNumber",
        "flightDate",
        "airlineCode",
        "airlineName",
        "departureIATA",
        "departureLocalDateTime",
        "arrivalIATA",
        "arrivalLocalDateTime",
        "aircraftType",
        "cabinClass",
        "seat",
        "notes",
    ]

    private static let requiredCSVHeaders = [
        "flightNumber",
        "flightDate",
        "departureIATA",
        "departureLocalDateTime",
        "arrivalIATA",
        "arrivalLocalDateTime",
    ]

    static func exportJSON(
        records: [FlightRecord],
        exportedAt: Date = .now,
        limits: BackupLimits = .standard
    ) throws -> Data {
        try exportJSON(
            recordSnapshots: records.map(FlightRecordBackupDTO.init),
            exportedAt: exportedAt,
            limits: limits
        )
    }

    static func exportJSON(
        recordSnapshots: [FlightRecordBackupDTO],
        exportedAt: Date = .now,
        limits: BackupLimits = .standard
    ) throws -> Data {
        let ownerIDs = Set(recordSnapshots.compactMap(\.ownerProfileID))
        guard ownerIDs.count == Set(recordSnapshots.map(\.ownerProfileID)).count
            || recordSnapshots.isEmpty
        else {
            throw BackupServiceError.legacyTargetRequired
        }
        let profiles = ownerIDs.sorted { $0.uuidString < $1.uuidString }
            .enumerated()
            .map { index, id in
                UserProfileBackupDTO(
                    id: id,
                    displayName: id == UserProfileDefaults.id
                        ? UserProfileDefaults.displayName
                        : "用户 \(index + 1)",
                    createdAt: Date(timeIntervalSince1970: 0),
                    sortOrder: index,
                    color: id == UserProfileDefaults.id
                        ? UserProfileDefaults.comparisonColorRawValue
                        : "blue"
                )
            }
        guard recordSnapshots.count <= limits.maximumRowCount else {
            throw BackupServiceError.tooManyJSONRecords(
                maximum: limits.maximumRowCount
            )
        }
        let backup = FlightBackupDTO(
            schemaVersion: currentSchemaVersion,
            exportedAt: exportedAt,
            scope: profiles.count <= 1 ? .singleProfile : .fullArchive,
            profiles: profiles,
            records: stableRecordSnapshots(recordSnapshots)
        )
        return try encodeJSON(backup, limits: limits)
    }

    static func exportCurrent(
        profile: UserProfile,
        records: [FlightRecord],
        exportedAt: Date = .now,
        limits: BackupLimits = .standard
    ) throws -> Data {
        try exportCurrent(
            profileSnapshot: UserProfileBackupDTO(profile: profile),
            recordSnapshots: records.map(FlightRecordBackupDTO.init),
            exportedAt: exportedAt,
            limits: limits
        )
    }

    static func exportCurrent(
        profileSnapshot: UserProfileBackupDTO,
        recordSnapshots snapshots: [FlightRecordBackupDTO],
        exportedAt: Date = .now,
        limits: BackupLimits = .standard
    ) throws -> Data {
        guard snapshots.allSatisfy({
            $0.ownerProfileID == profileSnapshot.id
        }) else {
            let orphan = snapshots.first {
                $0.ownerProfileID != profileSnapshot.id
            }!
            throw BackupServiceError.orphanRecord(
                orphan.id,
                orphan.ownerProfileID ?? profileSnapshot.id
            )
        }
        return try encodeJSON(
            FlightBackupDTO(
                schemaVersion: currentSchemaVersion,
                exportedAt: exportedAt,
                scope: .singleProfile,
                profiles: [profileSnapshot],
                records: stableRecordSnapshots(snapshots)
            ),
            limits: limits
        )
    }

    static func exportAll(
        profiles: [UserProfile],
        records: [FlightRecord],
        exportedAt: Date = .now,
        limits: BackupLimits = .standard
    ) throws -> Data {
        try exportAll(
            profileSnapshots: profiles.map(UserProfileBackupDTO.init),
            recordSnapshots: records.map(FlightRecordBackupDTO.init),
            exportedAt: exportedAt,
            limits: limits
        )
    }

    static func exportAll(
        profileSnapshots: [UserProfileBackupDTO],
        recordSnapshots: [FlightRecordBackupDTO],
        exportedAt: Date = .now,
        limits: BackupLimits = .standard
    ) throws -> Data {
        let profileIDs = Set(profileSnapshots.map(\.id))
        for (index, snapshot) in recordSnapshots.enumerated() {
            try cancellationCheckpoint(index)
            guard let owner = snapshot.ownerProfileID,
                  profileIDs.contains(owner)
            else {
                throw BackupServiceError.orphanRecord(
                    snapshot.id,
                    snapshot.ownerProfileID ?? UserProfileDefaults.id
                )
            }
        }
        return try encodeJSON(
            FlightBackupDTO(
                schemaVersion: currentSchemaVersion,
                exportedAt: exportedAt,
                scope: .fullArchive,
                profiles: stableProfiles(profileSnapshots),
                records: stableRecordSnapshots(recordSnapshots)
            ),
            limits: limits
        )
    }

    static func encodeJSON(
        _ backup: FlightBackupDTO,
        limits: BackupLimits = .standard
    ) throws -> Data {
        try validateEnvelope(backup)
        guard backup.records.count <= limits.maximumRowCount else {
            throw BackupServiceError.tooManyJSONRecords(
                maximum: limits.maximumRowCount
            )
        }
        let encoder = makeJSONEncoder()
        let data: Data
        do {
            data = try encoder.encode(backup)
        } catch {
            throw BackupServiceError.invalidJSON
        }
        guard data.count <= limits.maximumFileSize else {
            throw BackupServiceError.exportedFileTooLarge(
                maximum: limits.maximumFileSize
            )
        }
        return data
    }

    static func encodeLegacyV1JSON(
        recordSnapshots: [FlightRecordBackupDTO],
        exportedAt: Date = .now,
        limits: BackupLimits = .standard
    ) throws -> Data {
        struct LegacyEnvelope: Encodable {
            let schemaVersion: Int
            let exportedAt: Date
            let records: [FlightRecordBackupDTO]
        }
        guard recordSnapshots.count <= limits.maximumRowCount else {
            throw BackupServiceError.tooManyJSONRecords(
                maximum: limits.maximumRowCount
            )
        }
        var legacyRecords: [FlightRecordBackupDTO] = []
        legacyRecords.reserveCapacity(recordSnapshots.count)
        for (index, value) in stableRecordSnapshots(recordSnapshots).enumerated() {
            try cancellationCheckpoint(index)
            var value = value
            value.ownerProfileID = nil
            legacyRecords.append(value)
        }
        let data = try makeJSONEncoder().encode(
            LegacyEnvelope(
                schemaVersion: 1,
                exportedAt: exportedAt,
                records: legacyRecords
            )
        )
        guard data.count <= limits.maximumFileSize else {
            throw BackupServiceError.exportedFileTooLarge(
                maximum: limits.maximumFileSize
            )
        }
        return data
    }

    static func prepareLegacyV1Import(
        _ data: Data,
        existingRecordSnapshots: [FlightRecordBackupDTO],
        targetProfileID: UUID,
        mode: BackupRestoreMode,
        limits: BackupLimits = .standard
    ) throws -> PreparedFlightImport {
        let backup = try decodeJSON(data, limits: limits)
        guard backup.schemaVersion == 1 else {
            throw BackupServiceError.invalidJSON
        }
        return try prepareJSONImport(
            data,
            existingRecordSnapshots: existingRecordSnapshots,
            targetProfileID: targetProfileID,
            mode: mode,
            limits: limits
        )
    }

    static func decodeJSON(
        _ data: Data,
        limits: BackupLimits = .standard
    ) throws -> FlightBackupDTO {
        try validateInputData(data, limits: limits)
        guard let text = String(data: data, encoding: .utf8) else {
            throw BackupServiceError.invalidUTF8
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackupServiceError.emptyFile
        }

        struct SchemaEnvelope: Decodable {
            let schemaVersion: Int
        }

        let decoder = makeJSONDecoder()
        let schemaVersion: Int
        do {
            schemaVersion = try decoder
                .decode(SchemaEnvelope.self, from: data)
                .schemaVersion
        } catch {
            throw BackupServiceError.invalidJSON
        }
        guard schemaVersion == 1 || schemaVersion == currentSchemaVersion else {
            throw BackupServiceError.unsupportedSchemaVersion(schemaVersion)
        }

        let backup: FlightBackupDTO
        do {
            backup = try decoder.decode(FlightBackupDTO.self, from: data)
        } catch {
            throw BackupServiceError.invalidJSON
        }
        guard backup.records.count <= limits.maximumRowCount else {
            throw BackupServiceError.tooManyJSONRecords(
                maximum: limits.maximumRowCount
            )
        }
        try validateDecodedEnvelope(backup)
        if schemaVersion == currentSchemaVersion {
            guard backup.scope != nil, !backup.profiles.isEmpty else {
                throw BackupServiceError.invalidJSON
            }
            if backup.scope == .singleProfile, backup.profiles.count != 1 {
                throw BackupServiceError.invalidJSON
            }
            let profileIDs = Set(backup.profiles.map(\.id))
            guard profileIDs.count == backup.profiles.count else {
                var seen = Set<UUID>()
                let duplicate = backup.profiles.first { !seen.insert($0.id).inserted }
                throw BackupServiceError.duplicateBackupProfileID(
                    duplicate?.id ?? UserProfileDefaults.id
                )
            }
            var names = Set<String>()
            for (index, profile) in backup.profiles.enumerated() {
                try cancellationCheckpoint(index)
                let normalized = UserProfileNameValidator.normalize(
                    profile.displayName
                )
                guard (1 ... 30).contains(normalized.count),
                      names.insert(normalized.lowercased()).inserted,
                      !profile.color.isEmpty,
                      profile.createdAt.timeIntervalSinceReferenceDate.isFinite
                else {
                    throw BackupServiceError.invalidJSON
                }
            }
            for (index, record) in backup.records.enumerated() {
                try cancellationCheckpoint(index)
                guard let owner = record.ownerProfileID,
                      profileIDs.contains(owner)
                else {
                    throw BackupServiceError.orphanRecord(
                        record.id,
                        record.ownerProfileID ?? UserProfileDefaults.id
                    )
                }
            }
        }
        return backup
    }

    private static func validateEnvelope(
        _ backup: FlightBackupDTO
    ) throws {
        guard backup.schemaVersion == currentSchemaVersion else {
            throw BackupServiceError.unsupportedSchemaVersion(
                backup.schemaVersion
            )
        }
        try validateV2Envelope(backup)
    }

    private static func validateDecodedEnvelope(
        _ backup: FlightBackupDTO
    ) throws {
        if backup.schemaVersion == 1 {
            guard !backup.containsScopeField,
                  !backup.containsProfilesField,
                  backup.scope == nil,
                  backup.profiles.isEmpty
            else {
                throw BackupServiceError.invalidJSON
            }
            for (index, record) in backup.records.enumerated() {
                try cancellationCheckpoint(index)
                guard !record.containsOwnerProfileIDField,
                      record.ownerProfileID == nil
                else {
                    throw BackupServiceError.invalidBackupRecord(
                        index: index + 1,
                        reason: "schemaVersion 1 不能包含 ownerProfileID。"
                    )
                }
            }
            return
        }
        guard backup.schemaVersion == currentSchemaVersion else {
            throw BackupServiceError.unsupportedSchemaVersion(
                backup.schemaVersion
            )
        }
        try validateV2Envelope(backup)
    }

    private static func validateV2Envelope(
        _ backup: FlightBackupDTO
    ) throws {
        guard backup.schemaVersion == currentSchemaVersion,
              let scope = backup.scope,
              !backup.profiles.isEmpty
        else {
            throw BackupServiceError.invalidJSON
        }
        if scope == .singleProfile, backup.profiles.count != 1 {
            throw BackupServiceError.invalidJSON
        }
        let profileIDs = Set(backup.profiles.map(\.id))
        guard profileIDs.count == backup.profiles.count else {
            throw BackupServiceError.invalidJSON
        }
        var profileNames = Set<String>()
        for (index, profile) in backup.profiles.enumerated() {
            try cancellationCheckpoint(index)
            let name = UserProfileNameValidator.normalize(
                profile.displayName
            ).lowercased()
            guard (1 ... 30).contains(name.count),
                  profileNames.insert(name).inserted,
                  ProfileComparisonColor(rawValue: profile.color) != nil,
                  profile.createdAt.timeIntervalSinceReferenceDate.isFinite
            else {
                throw BackupServiceError.invalidJSON
            }
        }
        for (index, record) in backup.records.enumerated() {
            try cancellationCheckpoint(index)
            guard let owner = record.ownerProfileID,
                  profileIDs.contains(owner)
            else {
                throw BackupServiceError.invalidBackupRecord(
                    index: index + 1,
                    reason: "ownerProfileID 缺失或不在用户清单中。"
                )
            }
        }
    }

    static func prepareJSONImport(
        _ data: Data,
        existingRecordSnapshots: [FlightRecordBackupDTO],
        mode: BackupRestoreMode,
        limits: BackupLimits = .standard
    ) throws -> PreparedFlightImport {
        let backup = try decodeJSON(data, limits: limits)
        guard !backup.legacySingleProfile else {
            throw BackupServiceError.legacyTargetRequired
        }
        guard backup.profiles.count == 1, let source = backup.profiles.first else {
            throw BackupServiceError.invalidProfileMapping(
                "多用户备份必须逐一确认映射。"
            )
        }
        return try prepareJSONImport(
            data,
            existingRecordSnapshots: existingRecordSnapshots,
            mappingPlan: ProfileImportMappingPlan(entries: [
                .init(
                    sourceProfileID: source.id,
                    destination: .existing(source.id)
                ),
            ]),
            mode: mode,
            limits: limits
        )
    }

    static func prepareJSONImport(
        _ data: Data,
        existingRecords: [FlightRecord],
        targetProfileID: UUID,
        mode: BackupRestoreMode,
        limits: BackupLimits = .standard
    ) throws -> PreparedFlightImport {
        try prepareJSONImport(
            data,
            existingRecordSnapshots:
                existingRecords
                    .filter { $0.ownerProfileID == targetProfileID }
                    .map(FlightRecordBackupDTO.init),
            targetProfileID: targetProfileID,
            mode: mode,
            limits: limits
        )
    }

    static func prepareJSONImport(
        _ data: Data,
        existingRecordSnapshots: [FlightRecordBackupDTO],
        targetProfileID: UUID,
        mode: BackupRestoreMode,
        limits: BackupLimits = .standard
    ) throws -> PreparedFlightImport {
        let backup = try decodeJSON(data, limits: limits)
        let sourceProfileID: UUID
        if backup.legacySingleProfile {
            sourceProfileID = ProfileImportMappingPlan.legacySourceProfileID
        } else {
            guard backup.profiles.count == 1, let source = backup.profiles.first else {
                throw BackupServiceError.invalidProfileMapping(
                    "多用户备份必须逐一确认映射。"
                )
            }
            sourceProfileID = source.id
        }
        return try prepareDecodedJSONImport(
            backup,
            existingRecordSnapshots: existingRecordSnapshots,
            mappingPlan: ProfileImportMappingPlan(entries: [
                .init(
                    sourceProfileID: sourceProfileID,
                    destination: .existing(targetProfileID)
                ),
            ]),
            mode: mode,
            limits: limits
        )
    }

    static func prepareJSONImport(
        _ data: Data,
        existingRecordSnapshots: [FlightRecordBackupDTO],
        mappingPlan: ProfileImportMappingPlan,
        mode: BackupRestoreMode,
        limits: BackupLimits = .standard
    ) throws -> PreparedFlightImport {
        let backup = try decodeJSON(data, limits: limits)
        return try prepareDecodedJSONImport(
            backup,
            existingRecordSnapshots: existingRecordSnapshots,
            mappingPlan: mappingPlan,
            mode: mode,
            limits: limits
        )
    }

    private static func prepareDecodedJSONImport(
        _ backup: FlightBackupDTO,
        existingRecordSnapshots: [FlightRecordBackupDTO],
        mappingPlan: ProfileImportMappingPlan,
        mode: BackupRestoreMode,
        limits: BackupLimits
    ) throws -> PreparedFlightImport {
        if mode == .fullRestore {
            guard backup.schemaVersion == currentSchemaVersion,
                  backup.scope == .fullArchive
            else {
                throw BackupServiceError.fullRestoreRequiresV2FullArchive
            }
            guard !backup.profiles.isEmpty else {
                throw BackupServiceError.fullRestoreRequiresProfile
            }
        }

        // Validate the entire document before constructing or mutating any
        // SwiftData model. JSON restore therefore has a single failure point.
        for (offset, dto) in backup.records.enumerated() {
            try cancellationCheckpoint(offset)
            if let reason = validate(dto, limits: limits) {
                throw BackupServiceError.invalidBackupRecord(
                    index: offset + 1,
                    reason: reason
                )
            }
        }

        var seenIDs = Set<UUID>()
        for (index, dto) in backup.records.enumerated() {
            try cancellationCheckpoint(index)
            guard seenIDs.insert(dto.id).inserted else {
                throw BackupServiceError.duplicateBackupID(dto.id)
            }
        }

        var existingKeysByTarget: [UUID: Set<FlightBusinessKey>] = [:]
        for (index, snapshot) in existingRecordSnapshots.enumerated() {
            try cancellationCheckpoint(index)
            if let owner = snapshot.ownerProfileID {
                existingKeysByTarget[owner, default: []].insert(
                    FlightBusinessKey(snapshot)
                )
            }
        }
        var acceptedKeys: [UUID: [FlightBusinessKey: Int]] = [:]
        var accepted: [FlightRecordBackupDTO] = []
        var report = FlightImportReport(format: .json)

        for (offset, dto) in backup.records.enumerated() {
            try cancellationCheckpoint(offset)
            let itemNumber = offset + 1
            let key = FlightBusinessKey(dto)
            let sourceOwner = dto.ownerProfileID
                ?? ProfileImportMappingPlan.legacySourceProfileID
            guard let target = mappingPlan.localProfileID(for: sourceOwner) else {
                throw BackupServiceError.invalidProfileMapping(
                    "第 \(itemNumber) 条航班没有目标用户。"
                )
            }

            let existingKeys: Set<FlightBusinessKey>
            if existingKeysByTarget[target] != nil {
                existingKeys = existingKeysByTarget[target]!
            } else if existingRecordSnapshots.allSatisfy({
                $0.ownerProfileID == nil
            }), mappingPlan.entries.count == 1 {
                existingKeys = Set(existingRecordSnapshots.map(FlightBusinessKey.init))
            } else {
                existingKeys = []
            }
            if mode == .merge, existingKeys.contains(key) {
                report.duplicateCount += 1
                report.issues.append(
                    FlightImportIssue(
                        rowNumber: itemNumber,
                        kind: .duplicate,
                        reason: "与现有记录重复，已跳过。"
                    )
                )
                continue
            }
            if let firstItem = acceptedKeys[target]?[key] {
                report.duplicateCount += 1
                report.issues.append(
                    FlightImportIssue(
                        rowNumber: itemNumber,
                        kind: .duplicate,
                        reason: "与文件内第 \(firstItem) 条记录重复，已跳过。"
                    )
                )
                continue
            }

            acceptedKeys[target, default: [:]][key] = itemNumber
            accepted.append(dto)
            report.successCount += 1
        }

        return PreparedFlightImport(
            records: accepted,
            report: report,
            mode: mode,
            mappingPlan: mappingPlan,
            sourceSchemaVersion: backup.schemaVersion,
            sourceScope: backup.scope,
            sourceProfiles: backup.profiles,
            existingDatasetFingerprint: FlightDatasetFingerprint(
                recordSnapshots: existingRecordSnapshots
            )
        )
    }

    @MainActor
    static func restoreJSON(
        _ data: Data,
        to context: ModelContext,
        existingRecords: [FlightRecord],
        targetProfileID: UUID,
        mode: BackupRestoreMode,
        limits: BackupLimits = .standard
    ) throws -> FlightImportReport {
        let preparation = try prepareJSONImport(
            data,
            existingRecords: existingRecords,
            targetProfileID: targetProfileID,
            mode: mode,
            limits: limits
        )
        try apply(
            preparation,
            to: context,
            targetProfileID: targetProfileID
        )
        return preparation.report
    }

    static func exportCSV(
        records: [FlightRecord],
        limits: BackupLimits = .standard
    ) throws -> Data {
        try exportCSV(
            recordSnapshots: records.map(FlightRecordBackupDTO.init),
            limits: limits
        )
    }

    static func exportCSV(
        recordSnapshots: [FlightRecordBackupDTO],
        limits: BackupLimits = .standard
    ) throws -> Data {
        guard recordSnapshots.count + 1 <= limits.maximumRowCount else {
            throw BackupServiceError.tooManyRows(
                maximum: limits.maximumRowCount
            )
        }

        var lines = [csvHeaders.joined(separator: ",")]
        for (offset, record) in stableRecordSnapshots(
            recordSnapshots
        ).enumerated() {
            try cancellationCheckpoint(offset)
            let values = [
                record.flightNumber,
                formatDate(record.flightDate),
                record.airlineCode,
                record.airlineName,
                record.departureAirportIATA,
                HistoricalLocalTime.csvText(
                    snapshot: record.departureLocalDateTime,
                    absoluteDate: record.departureDate,
                    timeZoneID: record.departureTimeZoneID
                ),
                record.arrivalAirportIATA,
                HistoricalLocalTime.csvText(
                    snapshot: record.arrivalLocalDateTime,
                    absoluteDate: record.arrivalDate,
                    timeZoneID: record.arrivalTimeZoneID
                ),
                record.aircraftType ?? "",
                record.cabinClass ?? "",
                record.seat ?? "",
                record.notes ?? "",
            ]
            for value in values where value.count > limits.maximumFieldLength {
                throw BackupServiceError.fieldTooLong(
                    line: offset + 2,
                    maximum: limits.maximumFieldLength
                )
            }
            lines.append(values.map(csvEscape).joined(separator: ","))
        }

        let data = Data(lines.joined(separator: "\n").utf8)
        guard data.count <= limits.maximumFileSize else {
            throw BackupServiceError.exportedFileTooLarge(
                maximum: limits.maximumFileSize
            )
        }
        return data
    }

    static func prepareCSVImport(
        _ data: Data,
        repository: AirportRepository,
        existingRecords: [FlightRecord],
        targetProfileID: UUID,
        now: Date = .now,
        limits: BackupLimits = .standard
    ) throws -> PreparedFlightImport {
        try prepareCSVImport(
            data,
            repository: repository,
            existingRecordSnapshots:
                existingRecords
                    .filter { $0.ownerProfileID == targetProfileID }
                    .map(FlightRecordBackupDTO.init),
            targetProfileID: targetProfileID,
            now: now,
            limits: limits
        )
    }

    static func prepareCSVImport(
        _ data: Data,
        repository: AirportRepository,
        existingRecordSnapshots: [FlightRecordBackupDTO],
        targetProfileID: UUID,
        now: Date = .now,
        limits: BackupLimits = .standard
    ) throws -> PreparedFlightImport {
        let rows = try CSVDocumentParser.parse(data, limits: limits)
        guard let headerRow = rows.first else {
            throw BackupServiceError.emptyFile
        }

        let headers = headerRow.fields.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var headerIndex: [String: Int] = [:]
        for (index, header) in headers.enumerated() {
            try cancellationCheckpoint(index)
            guard headerIndex[header] == nil else {
                throw BackupServiceError.duplicateCSVHeader(header)
            }
            headerIndex[header] = index
        }
        let missingHeaders = requiredCSVHeaders.filter {
            headerIndex[$0] == nil
        }
        guard missingHeaders.isEmpty else {
            throw BackupServiceError.missingCSVHeaders(missingHeaders)
        }

        let existingKeys = Set(
            existingRecordSnapshots.map(FlightBusinessKey.init)
        )
        var acceptedKeys: [FlightBusinessKey: Int] = [:]
        var accepted: [FlightRecordBackupDTO] = []
        var report = FlightImportReport(format: .csv)

        for (offset, row) in rows.dropFirst().enumerated() {
            try cancellationCheckpoint(offset)
            if row.fields.allSatisfy({
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                continue
            }
            guard row.fields.count <= headers.count else {
                appendCSVFailure(
                    "字段数量超过表头列数。",
                    row: row.lineNumber,
                    report: &report
                )
                continue
            }

            do {
                let draft = try makeDraft(
                    row: row,
                    headerIndex: headerIndex,
                    repository: repository
                )
                var record: FlightRecordBackupDTO
                do {
                    record = try FlightRecordWriter.makeBackupSnapshot(
                        from: draft,
                        repository: repository,
                        ownerProfileID: targetProfileID,
                        now: now
                    )
                    record.ownerProfileID =
                        ProfileImportMappingPlan.legacySourceProfileID
                } catch FlightRecordWriteError.validation(let errors) {
                    throw CSVRowError(
                        reason: orderedValidationReasons(errors)
                    )
                }

                let key = FlightBusinessKey(record)
                if existingKeys.contains(key) {
                    report.duplicateCount += 1
                    report.issues.append(
                        FlightImportIssue(
                            rowNumber: row.lineNumber,
                            kind: .duplicate,
                            reason: "与现有记录重复，已跳过。"
                        )
                    )
                    continue
                }
                if let firstLine = acceptedKeys[key] {
                    report.duplicateCount += 1
                    report.issues.append(
                        FlightImportIssue(
                            rowNumber: row.lineNumber,
                            kind: .duplicate,
                            reason: "与文件内第 \(firstLine) 行重复，已跳过。"
                        )
                    )
                    continue
                }

                acceptedKeys[key] = row.lineNumber
                accepted.append(record)
                report.successCount += 1
            } catch let error as CSVRowError {
                appendCSVFailure(
                    error.reason,
                    row: row.lineNumber,
                    report: &report
                )
            } catch {
                appendCSVFailure(
                    "记录无效：\(error.localizedDescription)",
                    row: row.lineNumber,
                    report: &report
                )
            }
        }

        return PreparedFlightImport(
            records: accepted,
            report: report,
            mode: .merge,
            targetProfileID: targetProfileID,
            existingDatasetFingerprint: FlightDatasetFingerprint(
                recordSnapshots: existingRecordSnapshots
            )
        )
    }

    @MainActor
    @discardableResult
    static func apply(
        _ preparation: PreparedFlightImport,
        to context: ModelContext,
        targetProfileID: UUID
    ) throws -> FlightImportReport {
        guard let derivedTarget = preparation.targetProfileID else {
            throw BackupServiceError.invalidProfileMapping(
                "兼容 target 参数仅支持单一目标映射。"
            )
        }
        guard derivedTarget == targetProfileID else {
            throw BackupServiceError.targetProfileMismatch(
                expected: derivedTarget,
                actual: targetProfileID
            )
        }
        return try apply(preparation, to: context)
    }

    @MainActor
    @discardableResult
    static func apply(
        _ preparation: PreparedFlightImport,
        to context: ModelContext
    ) throws -> FlightImportReport {
        let transactionContext = ModelContext(context.container)
        transactionContext.autosaveEnabled = false
        let localProfiles: [UserProfile]
        let allRecords: [FlightRecord]
        do {
            localProfiles = try transactionContext.fetch(
                FetchDescriptor<UserProfile>()
            )
            allRecords = try transactionContext.fetch(
                FetchDescriptor<FlightRecord>()
            )
        } catch {
            throw BackupServiceError.persistenceFailed(
                error.localizedDescription
            )
        }
        if preparation.mode == .fullRestore {
            guard preparation.sourceSchemaVersion == currentSchemaVersion,
                  preparation.sourceScope == .fullArchive
            else {
                throw BackupServiceError.fullRestoreRequiresV2FullArchive
            }
            guard !preparation.sourceProfiles.isEmpty else {
                throw BackupServiceError.fullRestoreRequiresProfile
            }
        }
        let localProfileSnapshots = localProfiles.map(UserProfileBackupDTO.init)
        let localIDs = Set(localProfiles.map(\.id))
        let targetIDs = Set(
            preparation.mappingPlan.entries.map(\.destination.localProfileID)
        )
        for entry in preparation.mappingPlan.entries {
            if case .existing(let id) = entry.destination,
               !localIDs.contains(id),
               preparation.mode != .fullRestore
            {
                throw BackupServiceError.targetProfileMissing(id)
            }
        }
        if preparation.mode != .fullRestore {
            let sourceProfiles = preparation.sourceProfiles.isEmpty
                ? preparation.mappingPlan.entries.map {
                    UserProfileBackupDTO(
                        id: $0.sourceProfileID,
                        displayName: "旧版/CSV 来源",
                        createdAt: Date(timeIntervalSince1970: 0),
                        sortOrder: 0,
                        color: "blue"
                    )
                }
                : preparation.sourceProfiles
            _ = try preparation.mappingPlan.validated(
                sourceProfiles: sourceProfiles,
                localProfiles: localProfileSnapshots
            )
        }

        let scopedProfiles = preparation.fingerprintScope.profileIDs.map { ids in
            localProfileSnapshots.filter { ids.contains($0.id) }
        } ?? localProfileSnapshots
        let allRecordSnapshots = allRecords.map(FlightRecordBackupDTO.init)
        let scopedRecords = preparation.fingerprintScope.recordOwnerIDs.map { ids in
            allRecordSnapshots.filter {
                guard let owner = $0.ownerProfileID else { return false }
                return ids.contains(owner)
            }
        } ?? allRecordSnapshots
        guard FlightDatasetFingerprint(
            profiles: scopedProfiles,
            recordSnapshots: scopedRecords
        ) == preparation.existingDatasetFingerprint else {
            throw BackupServiceError.staleImportPlan
        }

        var report = preparation.report
        do {
            if preparation.mode == .fullRestore {
                guard preparation.sourceSchemaVersion == currentSchemaVersion,
                      preparation.sourceScope == .fullArchive
                else {
                    throw BackupServiceError.fullRestoreRequiresV2FullArchive
                }
                guard !preparation.sourceProfiles.isEmpty else {
                    throw BackupServiceError.fullRestoreRequiresProfile
                }
                for record in allRecords {
                    transactionContext.delete(record)
                }
                for profile in localProfiles {
                    transactionContext.delete(profile)
                }
                for profile in stableProfiles(preparation.sourceProfiles) {
                    transactionContext.insert(profile.makeProfile())
                }
            } else {
                for entry in preparation.mappingPlan.entries {
                    if case let .create(id, displayName, color) = entry.destination {
                        let normalized = try UserProfileNameValidator.validatedName(
                            displayName,
                            existingNames: localProfiles.map(\.displayName)
                                + preparation.mappingPlan.entries.compactMap {
                                    guard case let .create(otherID, otherName, _) =
                                        $0.destination,
                                        otherID != id
                                    else {
                                        return nil
                                    }
                                    return otherName
                                }
                        )
                        transactionContext.insert(
                            UserProfile(
                                id: id,
                                displayName: normalized,
                                sortOrder: (localProfiles.map(\.sortOrder).max() ?? -1) + 1,
                                comparisonColorRawValue: color
                            )
                        )
                    }
                }
                if preparation.mode == .replace {
                    for record in allRecords where record.ownerProfileID.map(
                        targetIDs.contains
                    ) == true {
                        transactionContext.delete(record)
                    }
                }
            }
            let deletedIDs: Set<UUID> = preparation.mode == .fullRestore
                ? Set(allRecords.map(\.id))
                : preparation.mode == .replace
                    ? Set(
                        allRecords
                            .filter {
                                $0.ownerProfileID.map(targetIDs.contains) == true
                            }
                            .map(\.id)
                    )
                    : []
            var recordsByID = Dictionary(
                uniqueKeysWithValues: allRecords
                    .filter { !deletedIDs.contains($0.id) }
                    .map { ($0.id, $0) }
            )
            for (index, snapshot) in preparation.records.enumerated() {
                try cancellationCheckpoint(index)
                let sourceOwner = snapshot.ownerProfileID
                    ?? ProfileImportMappingPlan.legacySourceProfileID
                let target: UUID
                if preparation.mode == .fullRestore {
                    guard let owner = snapshot.ownerProfileID else {
                        throw BackupServiceError.fullRestoreRequiresV2FullArchive
                    }
                    target = owner
                } else {
                    guard let mapped = preparation.mappingPlan.localProfileID(
                        for: sourceOwner
                    ) else {
                        throw BackupServiceError.invalidProfileMapping(
                            "航班缺少目标用户。"
                        )
                    }
                    target = mapped
                }
                var recordID = snapshot.id
                if let occupied = recordsByID[recordID] {
                    if occupied.ownerProfileID == target,
                       FlightBusinessKey(occupied) == FlightBusinessKey(snapshot)
                    {
                        report.successCount = max(0, report.successCount - 1)
                        report.duplicateCount += 1
                        continue
                    }
                    var attempt = 0
                    repeat {
                        recordID = stableRemappedRecordID(
                            sourceID: snapshot.id,
                            targetProfileID: target,
                            attempt: attempt
                        )
                        attempt += 1
                    } while recordsByID[recordID] != nil
                    report.remappedUUIDCount += 1
                    report.issues.append(
                        FlightImportIssue(
                            rowNumber: nil,
                            kind: .duplicate,
                            reason: "记录 UUID 与其他用户冲突，已稳定重映射。"
                        )
                    )
                }
                let record = snapshot.makeRecord(
                    ownerProfileID: target,
                    recordID: recordID
                )
                recordsByID[recordID] = record
                transactionContext.insert(
                    record
                )
            }
            try transactionContext.save()
        } catch let error as BackupServiceError {
            transactionContext.rollback()
            throw error
        } catch {
            transactionContext.rollback()
            throw BackupServiceError.persistenceFailed(
                error.localizedDescription
            )
        }
        return report
    }

    static func stableRemappedRecordID(
        sourceID: UUID,
        targetProfileID: UUID,
        attempt: Int
    ) -> UUID {
        let digest = SHA256.hash(
            data: Data(
                "FlightLog/ProfileBackup/v2/\(sourceID.uuidString)/\(targetProfileID.uuidString)/\(attempt)"
                    .utf8
            )
        )
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func makeDraft(
        row: CSVParsedRow,
        headerIndex: [String: Int],
        repository: AirportRepository
    ) throws -> FlightDraft {
        func value(_ header: String) -> String {
            guard
                let index = headerIndex[header],
                index < row.fields.count
            else {
                return ""
            }
            return row.fields[index]
        }

        for header in requiredCSVHeaders {
            guard
                !value(header)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            else {
                throw CSVRowError(reason: "缺少必需字段 \(header)。")
            }
        }

        let flightDateText = value("flightDate")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let flightDate = parseDate(flightDateText) else {
            throw CSVRowError(
                reason: "飞行日期无效：\(flightDateText)，应使用 yyyy-MM-dd。"
            )
        }

        let departureCode = FlightRecordNormalization.code(
            value("departureIATA")
        )
        guard let departureAirport = repository.airport(iata: departureCode) else {
            throw CSVRowError(reason: "未在机场库中找到机场：\(departureCode)。")
        }
        let arrivalCode = FlightRecordNormalization.code(value("arrivalIATA"))
        guard let arrivalAirport = repository.airport(iata: arrivalCode) else {
            throw CSVRowError(reason: "未在机场库中找到机场：\(arrivalCode)。")
        }

        let departureTimeText = value("departureLocalDateTime")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let departureLocalDate = parseLocalDateTime(departureTimeText) else {
            throw CSVRowError(
                reason: "当地起飞时间无效：\(departureTimeText)，应使用 yyyy-MM-dd HH:mm。"
            )
        }
        let arrivalTimeText = value("arrivalLocalDateTime")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let arrivalLocalDate = parseLocalDateTime(arrivalTimeText) else {
            throw CSVRowError(
                reason: "当地到达时间无效：\(arrivalTimeText)，应使用 yyyy-MM-dd HH:mm。"
            )
        }

        return FlightDraft(
            flightDate: flightDate,
            flightNumber: value("flightNumber"),
            airlineCode: value("airlineCode"),
            airlineName: value("airlineName"),
            departureAirport: departureAirport,
            arrivalAirport: arrivalAirport,
            departureLocalDate: departureLocalDate,
            arrivalLocalDate: arrivalLocalDate,
            aircraftType: value("aircraftType"),
            cabinClass: value("cabinClass"),
            seat: value("seat"),
            notes: value("notes")
        )
    }

    private static func appendCSVFailure(
        _ reason: String,
        row: Int,
        report: inout FlightImportReport
    ) {
        report.failureCount += 1
        report.issues.append(
            FlightImportIssue(
                rowNumber: row,
                kind: .failure,
                reason: reason
            )
        )
    }

    private static func orderedValidationReasons(
        _ errors: [FlightDraftField: String]
    ) -> String {
        let order: [FlightDraftField] = [
            .flightNumber,
            .airlineCode,
            .airlineName,
            .departureAirport,
            .departureLocalDate,
            .arrivalAirport,
            .arrivalLocalDate,
            .aircraftType,
            .cabinClass,
            .seat,
            .notes,
        ]
        return order.compactMap { errors[$0] }.joined(separator: " ")
    }

    private static func validate(
        _ dto: FlightRecordBackupDTO,
        limits: BackupLimits
    ) -> String? {
        let requiredStrings: [(String, String)] = [
            ("航班号", dto.flightNumber),
            ("出发机场 IATA", dto.departureAirportIATA),
            ("出发机场时区", dto.departureTimeZoneID),
            ("出发机场名称", dto.departureAirportName),
            ("到达机场 IATA", dto.arrivalAirportIATA),
            ("到达机场时区", dto.arrivalTimeZoneID),
            ("到达机场名称", dto.arrivalAirportName),
        ]
        for (label, value) in requiredStrings
        where value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(label)不能为空。"
        }
        guard
            !FlightRecordNormalization.code(dto.flightNumber).isEmpty
        else {
            return "航班号必须包含字母或数字。"
        }

        let allStrings = [
            dto.flightNumber,
            dto.airlineCode,
            dto.airlineName,
            dto.departureAirportIATA,
            dto.departureTimeZoneID,
            dto.departureAirportName,
            dto.departureCity,
            dto.departureCountry,
            dto.departureCountryCode,
            dto.arrivalAirportIATA,
            dto.arrivalTimeZoneID,
            dto.arrivalAirportName,
            dto.arrivalCity,
            dto.arrivalCountry,
            dto.arrivalCountryCode,
            dto.aircraftType ?? "",
            dto.cabinClass ?? "",
            dto.seat ?? "",
            dto.notes ?? "",
        ]
        if allStrings.contains(where: { $0.count > limits.maximumFieldLength }) {
            return "字段长度超过 \(limits.maximumFieldLength) 个字符。"
        }
        guard dto.flightNumber.count <= 20 else {
            return "航班号不能超过 20 个字符。"
        }
        guard dto.airlineCode.count <= 10 else {
            return "航司代码不能超过 10 个字符。"
        }
        guard dto.airlineName.count <= 120 else {
            return "航司名称不能超过 120 个字符。"
        }
        guard (dto.aircraftType?.count ?? 0) <= 80 else {
            return "机型不能超过 80 个字符。"
        }
        guard (dto.cabinClass?.count ?? 0) <= 40 else {
            return "舱位不能超过 40 个字符。"
        }
        guard (dto.seat?.count ?? 0) <= 20 else {
            return "座位不能超过 20 个字符。"
        }
        guard (dto.notes?.count ?? 0) <= 2_000 else {
            return "备注不能超过 2000 个字符。"
        }

        guard
            canonicalIATA(dto.departureAirportIATA),
            canonicalIATA(dto.arrivalAirportIATA)
        else {
            return "机场 IATA 必须是规范的 3 位 ASCII 大写字母 A-Z。"
        }
        let departureIATA = dto.departureAirportIATA
        let arrivalIATA = dto.arrivalAirportIATA
        guard departureIATA != arrivalIATA else {
            return "到达机场不能与出发机场相同。"
        }
        guard TimeZone(identifier: dto.departureTimeZoneID) != nil else {
            return "出发机场时区无效。"
        }
        guard TimeZone(identifier: dto.arrivalTimeZoneID) != nil else {
            return "到达机场时区无效。"
        }
        let departureWallClock = HistoricalLocalTime.wallClockDate(
            snapshot: dto.departureLocalDateTime,
            absoluteDate: dto.departureDate,
            timeZoneID: dto.departureTimeZoneID
        )
        guard FlightDateNormalization.isSameDate(
            dto.flightDate,
            departureWallClock
        ) else {
            return "flightDate 必须等于保存的出发当地日期。"
        }
        guard dto.arrivalDate > dto.departureDate else {
            return "到达时间必须晚于起飞时间。"
        }
        guard
            validLatitude(dto.departureLatitude),
            validLongitude(dto.departureLongitude),
            validLatitude(dto.arrivalLatitude),
            validLongitude(dto.arrivalLongitude)
        else {
            return "机场坐标无效。"
        }
        let dates = [
            dto.flightDate,
            dto.departureDate,
            dto.arrivalDate,
            dto.createdAt,
            dto.updatedAt,
        ]
        guard dates.allSatisfy({
            $0.timeIntervalSinceReferenceDate.isFinite
        }) else {
            return "日期或时间戳无效。"
        }
        guard dto.updatedAt >= dto.createdAt else {
            return "更新时间不能早于创建时间。"
        }
        return nil
    }

    private static func stableRecordSnapshots(
        _ records: [FlightRecordBackupDTO]
    ) -> [FlightRecordBackupDTO] {
        records.sorted {
            let lhs = (
                $0.flightDate,
                $0.flightNumber,
                $0.departureAirportIATA,
                $0.arrivalAirportIATA,
                $0.id.uuidString
            )
            let rhs = (
                $1.flightDate,
                $1.flightNumber,
                $1.departureAirportIATA,
                $1.arrivalAirportIATA,
                $1.id.uuidString
            )
            return lhs < rhs
        }
    }

    private static func stableProfiles(
        _ profiles: [UserProfileBackupDTO]
    ) -> [UserProfileBackupDTO] {
        profiles.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            if $0.displayName != $1.displayName {
                return $0.displayName < $1.displayName
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func csvEscape(_ value: String) -> String {
        guard
            value.contains(",")
                || value.contains("\"")
                || value.contains("\n")
                || value.contains("\r")
        else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func formatDate(_ date: Date) -> String {
        makeDateFormatter("yyyy-MM-dd").string(from: date)
    }

    private static func formatLocalDateTime(_ date: Date) -> String {
        makeDateFormatter("yyyy-MM-dd HH:mm").string(from: date)
    }

    private static func parseDate(_ value: String) -> Date? {
        parseExact(value, format: "yyyy-MM-dd")
    }

    private static func parseLocalDateTime(_ value: String) -> Date? {
        parseExact(value, format: "yyyy-MM-dd HH:mm")
    }

    private static func parseExact(
        _ value: String,
        format: String
    ) -> Date? {
        let formatter = makeDateFormatter(format)
        guard
            let date = formatter.date(from: value),
            formatter.string(from: date) == value
        else {
            return nil
        }
        return date
    }

    private static func makeDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }

    private static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    private static func validateInputData(
        _ data: Data,
        limits: BackupLimits
    ) throws {
        guard !data.isEmpty else {
            throw BackupServiceError.emptyFile
        }
        guard data.count <= limits.maximumFileSize else {
            throw BackupServiceError.fileTooLarge(
                maximum: limits.maximumFileSize
            )
        }
    }

    private static func validLatitude(_ value: Double) -> Bool {
        value.isFinite && (-90 ... 90).contains(value)
    }

    private static func validLongitude(_ value: Double) -> Bool {
        value.isFinite && (-180 ... 180).contains(value)
    }

    private static func canonicalIATA(_ value: String) -> Bool {
        guard value.count == 3 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (65 ... 90).contains(value)
        }
    }

    private static func cancellationCheckpoint(_ index: Int) throws {
        if index.isMultiple(of: 256) {
            try Task.checkCancellation()
        }
    }
}

enum BackupFileIO {
    static func readData(
        from url: URL,
        limits: BackupLimits = .standard
    ) throws -> Data {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = values.fileSize, size > limits.maximumFileSize {
                throw BackupServiceError.fileTooLarge(
                    maximum: limits.maximumFileSize
                )
            }
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else {
                throw BackupServiceError.emptyFile
            }
            guard data.count <= limits.maximumFileSize else {
                throw BackupServiceError.fileTooLarge(
                    maximum: limits.maximumFileSize
                )
            }
            return data
        } catch let error as BackupServiceError {
            throw error
        } catch {
            let cocoaError = error as NSError
            let reason: String
            switch cocoaError.code {
            case CocoaError.fileReadNoPermission.rawValue:
                reason = "没有读取权限。"
            case CocoaError.fileNoSuchFile.rawValue:
                reason = "文件不存在或已被移动。"
            default:
                reason = "请检查文件是否存在且具有读取权限。"
            }
            throw BackupServiceError.fileReadFailed(reason)
        }
    }

    static func readSecurityScopedOwnedData(
        from url: URL,
        limits: BackupLimits = .standard
    ) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try readData(from: url, limits: limits)
    }
}

private struct CSVRowError: Error {
    let reason: String
}
