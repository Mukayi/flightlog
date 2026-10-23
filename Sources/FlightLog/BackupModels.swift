import Foundation

struct BackupLimits: Equatable, Sendable {
    let maximumFileSize: Int
    let maximumRowCount: Int
    let maximumFieldLength: Int

    static let standard = BackupLimits(
        maximumFileSize: 10 * 1_024 * 1_024,
        maximumRowCount: 50_000,
        maximumFieldLength: 10_000
    )
}

enum BackupServiceError: LocalizedError, Equatable {
    case emptyFile
    case fileTooLarge(maximum: Int)
    case invalidUTF8
    case tooManyRows(maximum: Int)
    case tooManyJSONRecords(maximum: Int)
    case fieldTooLong(line: Int, maximum: Int)
    case malformedCSV(line: Int, reason: String)
    case duplicateCSVHeader(String)
    case missingCSVHeaders([String])
    case invalidJSON
    case unsupportedSchemaVersion(Int)
    case invalidBackupRecord(index: Int, reason: String)
    case duplicateBackupID(UUID)
    case duplicateBackupProfileID(UUID)
    case orphanRecord(UUID, UUID)
    case legacyTargetRequired
    case invalidProfileMapping(String)
    case fullRestoreRequiresV2FullArchive
    case fullRestoreRequiresProfile
    case staleImportPlan
    case targetProfileMismatch(expected: UUID, actual: UUID)
    case targetProfileMissing(UUID)
    case exportedFileTooLarge(maximum: Int)
    case fileReadFailed(String)
    case fileWriteFailed(String)
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            "所选文件为空。"
        case let .fileTooLarge(maximum):
            "文件过大，最大允许 \(Self.byteCount(maximum))。"
        case .invalidUTF8:
            "文件不是有效的 UTF-8 编码。请将文件转换为 UTF-8 后重试。"
        case let .tooManyRows(maximum):
            "CSV 行数过多，最多允许 \(maximum) 行。"
        case let .tooManyJSONRecords(maximum):
            "JSON 记录数过多，最多允许 \(maximum) 条记录。"
        case let .fieldTooLong(line, maximum):
            "第 \(line) 行字段过长，单个字段最多允许 \(maximum) 个字符。"
        case let .malformedCSV(line, reason):
            "CSV 第 \(line) 行格式错误：\(reason)"
        case let .duplicateCSVHeader(header):
            "CSV 表头“\(header)”重复。"
        case let .missingCSVHeaders(headers):
            "CSV 缺少必需表头：\(headers.joined(separator: ", "))。"
        case .invalidJSON:
            "JSON 备份格式无效或内容已损坏。"
        case let .unsupportedSchemaVersion(version):
            "不支持 schemaVersion \(version)；此应用仅支持版本 \(BackupService.currentSchemaVersion)。"
        case let .invalidBackupRecord(index, reason):
            "JSON 第 \(index) 条航班记录无效：\(reason)"
        case let .duplicateBackupID(id):
            "JSON 中存在重复记录 ID：\(id.uuidString)。"
        case let .duplicateBackupProfileID(id):
            "JSON 中存在重复用户 ID：\(id.uuidString)。"
        case let .orphanRecord(recordID, ownerID):
            "航班 \(recordID.uuidString) 的用户 \(ownerID.uuidString) 不在备份用户清单中。"
        case .legacyTargetRequired:
            "旧版 JSON/CSV 不包含用户归属，必须明确选择目标用户。"
        case let .invalidProfileMapping(reason):
            "用户映射无效：\(reason)"
        case .fullRestoreRequiresV2FullArchive:
            "完整恢复仅接受 schema v2 的全部用户备份。"
        case .fullRestoreRequiresProfile:
            "完整恢复至少需要一个用户档案。"
        case .staleImportPlan:
            "数据已变化，请重新确认。"
        case let .targetProfileMismatch(expected, actual):
            "导入目标用户不匹配：计划目标为 \(expected.uuidString)，实际请求为 \(actual.uuidString)。"
        case let .targetProfileMissing(id):
            "导入目标用户不存在（\(id.uuidString)），未写入任何数据。"
        case let .exportedFileTooLarge(maximum):
            "导出内容超过 \(Self.byteCount(maximum)) 的安全上限。"
        case let .fileReadFailed(reason):
            "无法读取文件：\(reason)"
        case let .fileWriteFailed(reason):
            "无法写入文件：\(reason)"
        case let .persistenceFailed(reason):
            "无法保存导入结果：\(reason)"
        }
    }

    private static func byteCount(_ value: Int) -> String {
        ByteCountFormatter.string(
            fromByteCount: Int64(value),
            countStyle: .file
        )
    }
}

enum BackupExportScope: String, Codable, Equatable, Sendable {
    case singleProfile
    case fullArchive
}

struct UserProfileBackupDTO: Codable, Equatable, Sendable {
    var id: UUID
    var displayName: String
    var createdAt: Date
    var sortOrder: Int
    var color: String

    init(
        id: UUID,
        displayName: String,
        createdAt: Date,
        sortOrder: Int,
        color: String
    ) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.color = color
    }

    init(profile: UserProfile) {
        self.init(
            id: profile.id,
            displayName: profile.displayName,
            createdAt: profile.createdAt,
            sortOrder: profile.sortOrder,
            color: profile.comparisonColorRawValue
        )
    }

    func makeProfile() -> UserProfile {
        UserProfile(
            id: id,
            displayName: displayName,
            createdAt: createdAt,
            sortOrder: sortOrder,
            comparisonColorRawValue: color
        )
    }
}

struct FlightBackupDTO: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var exportedAt: Date
    var scope: BackupExportScope?
    var profiles: [UserProfileBackupDTO]
    var records: [FlightRecordBackupDTO]
    private(set) var containsScopeField: Bool
    private(set) var containsProfilesField: Bool

    var legacySingleProfile: Bool {
        schemaVersion == 1 && scope == nil && profiles.isEmpty
    }

    init(
        schemaVersion: Int,
        exportedAt: Date,
        scope: BackupExportScope? = nil,
        profiles: [UserProfileBackupDTO] = [],
        records: [FlightRecordBackupDTO]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        containsScopeField = schemaVersion == 2
        containsProfilesField = schemaVersion == 2
        self.scope = scope
        self.profiles = profiles
        self.records = records
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case exportedAt
        case scope
        case profiles
        case records
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        containsScopeField = container.contains(.scope)
        containsProfilesField = container.contains(.profiles)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        scope = try container.decodeIfPresent(BackupExportScope.self, forKey: .scope)
        profiles = try container.decodeIfPresent(
            [UserProfileBackupDTO].self,
            forKey: .profiles
        ) ?? []
        records = try container.decode([FlightRecordBackupDTO].self, forKey: .records)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(exportedAt, forKey: .exportedAt)
        if schemaVersion != 1 {
            try container.encode(scope, forKey: .scope)
            try container.encode(profiles, forKey: .profiles)
        }
        try container.encode(records, forKey: .records)
    }
}

struct FlightRecordBackupDTO: Codable, Equatable, Sendable {
    var id: UUID
    var ownerProfileID: UUID?
    var flightNumber: String
    var airlineCode: String
    var airlineName: String
    var flightDate: Date

    var departureAirportIATA: String
    var departureDate: Date
    var departureTimeZoneID: String
    var departureLocalDateTime: String?
    var departureUTCOffsetSeconds: Int?
    var departureAirportName: String
    var departureCity: String
    var departureCountry: String
    var departureCountryCode: String
    var departureLatitude: Double
    var departureLongitude: Double

    var arrivalAirportIATA: String
    var arrivalDate: Date
    var arrivalTimeZoneID: String
    var arrivalLocalDateTime: String?
    var arrivalUTCOffsetSeconds: Int?
    var arrivalAirportName: String
    var arrivalCity: String
    var arrivalCountry: String
    var arrivalCountryCode: String
    var arrivalLatitude: Double
    var arrivalLongitude: Double

    var aircraftType: String?
    var cabinClass: String?
    var seat: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    private(set) var containsOwnerProfileIDField: Bool

    init(record: FlightRecord) {
        id = record.id
        containsOwnerProfileIDField = true
        ownerProfileID = record.ownerProfileID
        flightNumber = record.flightNumber
        airlineCode = record.airlineCode
        airlineName = record.airlineName
        flightDate = record.flightDate

        departureAirportIATA = record.departureAirportIATA
        departureDate = record.departureDate
        departureTimeZoneID = record.departureTimeZoneID
        departureLocalDateTime = record.departureLocalDateTime
        departureUTCOffsetSeconds = record.departureUTCOffsetSeconds
        departureAirportName = record.departureAirportName
        departureCity = record.departureCity
        departureCountry = record.departureCountry
        departureCountryCode = record.departureCountryCode
        departureLatitude = record.departureLatitude
        departureLongitude = record.departureLongitude

        arrivalAirportIATA = record.arrivalAirportIATA
        arrivalDate = record.arrivalDate
        arrivalTimeZoneID = record.arrivalTimeZoneID
        arrivalLocalDateTime = record.arrivalLocalDateTime
        arrivalUTCOffsetSeconds = record.arrivalUTCOffsetSeconds
        arrivalAirportName = record.arrivalAirportName
        arrivalCity = record.arrivalCity
        arrivalCountry = record.arrivalCountry
        arrivalCountryCode = record.arrivalCountryCode
        arrivalLatitude = record.arrivalLatitude
        arrivalLongitude = record.arrivalLongitude

        aircraftType = record.aircraftType
        cabinClass = record.cabinClass
        seat = record.seat
        notes = record.notes
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    init(record: FlightLogSchemaV1.FlightRecord) {
        id = record.id
        containsOwnerProfileIDField = false
        ownerProfileID = nil
        flightNumber = record.flightNumber
        airlineCode = record.airlineCode
        airlineName = record.airlineName
        flightDate = record.flightDate

        departureAirportIATA = record.departureAirportIATA
        departureDate = record.departureDate
        departureTimeZoneID = record.departureTimeZoneID
        departureLocalDateTime = record.departureLocalDateTime
        departureUTCOffsetSeconds = record.departureUTCOffsetSeconds
        departureAirportName = record.departureAirportName
        departureCity = record.departureCity
        departureCountry = record.departureCountry
        departureCountryCode = record.departureCountryCode
        departureLatitude = record.departureLatitude
        departureLongitude = record.departureLongitude

        arrivalAirportIATA = record.arrivalAirportIATA
        arrivalDate = record.arrivalDate
        arrivalTimeZoneID = record.arrivalTimeZoneID
        arrivalLocalDateTime = record.arrivalLocalDateTime
        arrivalUTCOffsetSeconds = record.arrivalUTCOffsetSeconds
        arrivalAirportName = record.arrivalAirportName
        arrivalCity = record.arrivalCity
        arrivalCountry = record.arrivalCountry
        arrivalCountryCode = record.arrivalCountryCode
        arrivalLatitude = record.arrivalLatitude
        arrivalLongitude = record.arrivalLongitude

        aircraftType = record.aircraftType
        cabinClass = record.cabinClass
        seat = record.seat
        notes = record.notes
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    init(
        id: UUID = UUID(),
        flightNumber: String,
        airlineCode: String,
        airlineName: String,
        flightDate: Date,
        departureAirport: Airport,
        arrivalAirport: Airport,
        departureDate: Date,
        arrivalDate: Date,
        departureLocalDateTime: String?,
        departureUTCOffsetSeconds: Int?,
        arrivalLocalDateTime: String?,
        arrivalUTCOffsetSeconds: Int?,
        aircraftType: String?,
        cabinClass: String?,
        seat: String?,
        notes: String?,
        ownerProfileID: UUID? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        containsOwnerProfileIDField = ownerProfileID != nil
        self.ownerProfileID = ownerProfileID
        self.flightNumber = flightNumber
        self.airlineCode = airlineCode
        self.airlineName = airlineName
        self.flightDate = flightDate
        departureAirportIATA = departureAirport.iata
        self.departureDate = departureDate
        departureTimeZoneID = departureAirport.timeZoneID
        self.departureLocalDateTime = departureLocalDateTime
        self.departureUTCOffsetSeconds = departureUTCOffsetSeconds
        departureAirportName = departureAirport.name
        departureCity = departureAirport.city
        departureCountry = departureAirport.country
        departureCountryCode = departureAirport.countryCode
        departureLatitude = departureAirport.latitude
        departureLongitude = departureAirport.longitude
        arrivalAirportIATA = arrivalAirport.iata
        self.arrivalDate = arrivalDate
        arrivalTimeZoneID = arrivalAirport.timeZoneID
        self.arrivalLocalDateTime = arrivalLocalDateTime
        self.arrivalUTCOffsetSeconds = arrivalUTCOffsetSeconds
        arrivalAirportName = arrivalAirport.name
        arrivalCity = arrivalAirport.city
        arrivalCountry = arrivalAirport.country
        arrivalCountryCode = arrivalAirport.countryCode
        arrivalLatitude = arrivalAirport.latitude
        arrivalLongitude = arrivalAirport.longitude
        self.aircraftType = aircraftType
        self.cabinClass = cabinClass
        self.seat = seat
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case ownerProfileID
        case flightNumber
        case airlineCode
        case airlineName
        case flightDate
        case departureAirportIATA
        case departureDate
        case departureTimeZoneID
        case departureLocalDateTime
        case departureUTCOffsetSeconds
        case departureAirportName
        case departureCity
        case departureCountry
        case departureCountryCode
        case departureLatitude
        case departureLongitude
        case arrivalAirportIATA
        case arrivalDate
        case arrivalTimeZoneID
        case arrivalLocalDateTime
        case arrivalUTCOffsetSeconds
        case arrivalAirportName
        case arrivalCity
        case arrivalCountry
        case arrivalCountryCode
        case arrivalLatitude
        case arrivalLongitude
        case aircraftType
        case cabinClass
        case seat
        case notes
        case createdAt
        case updatedAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(ownerProfileID, forKey: .ownerProfileID)
        try container.encode(flightNumber, forKey: .flightNumber)
        try container.encode(airlineCode, forKey: .airlineCode)
        try container.encode(airlineName, forKey: .airlineName)
        try container.encode(flightDate, forKey: .flightDate)
        try container.encode(
            departureAirportIATA,
            forKey: .departureAirportIATA
        )
        try container.encode(departureDate, forKey: .departureDate)
        try container.encode(
            departureTimeZoneID,
            forKey: .departureTimeZoneID
        )
        try encodeOptional(
            departureLocalDateTime,
            forKey: .departureLocalDateTime,
            into: &container
        )
        try encodeOptional(
            departureUTCOffsetSeconds,
            forKey: .departureUTCOffsetSeconds,
            into: &container
        )
        try container.encode(
            departureAirportName,
            forKey: .departureAirportName
        )
        try container.encode(departureCity, forKey: .departureCity)
        try container.encode(departureCountry, forKey: .departureCountry)
        try container.encode(
            departureCountryCode,
            forKey: .departureCountryCode
        )
        try container.encode(departureLatitude, forKey: .departureLatitude)
        try container.encode(departureLongitude, forKey: .departureLongitude)
        try container.encode(arrivalAirportIATA, forKey: .arrivalAirportIATA)
        try container.encode(arrivalDate, forKey: .arrivalDate)
        try container.encode(arrivalTimeZoneID, forKey: .arrivalTimeZoneID)
        try encodeOptional(
            arrivalLocalDateTime,
            forKey: .arrivalLocalDateTime,
            into: &container
        )
        try encodeOptional(
            arrivalUTCOffsetSeconds,
            forKey: .arrivalUTCOffsetSeconds,
            into: &container
        )
        try container.encode(arrivalAirportName, forKey: .arrivalAirportName)
        try container.encode(arrivalCity, forKey: .arrivalCity)
        try container.encode(arrivalCountry, forKey: .arrivalCountry)
        try container.encode(
            arrivalCountryCode,
            forKey: .arrivalCountryCode
        )
        try container.encode(arrivalLatitude, forKey: .arrivalLatitude)
        try container.encode(arrivalLongitude, forKey: .arrivalLongitude)
        try encodeOptional(aircraftType, forKey: .aircraftType, into: &container)
        try encodeOptional(cabinClass, forKey: .cabinClass, into: &container)
        try encodeOptional(seat, forKey: .seat, into: &container)
        try encodeOptional(notes, forKey: .notes, into: &container)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        containsOwnerProfileIDField = container.contains(.ownerProfileID)
        id = try container.decode(UUID.self, forKey: .id)
        ownerProfileID = try container.decodeIfPresent(
            UUID.self,
            forKey: .ownerProfileID
        )
        flightNumber = try container.decode(String.self, forKey: .flightNumber)
        airlineCode = try container.decode(String.self, forKey: .airlineCode)
        airlineName = try container.decode(String.self, forKey: .airlineName)
        flightDate = try container.decode(Date.self, forKey: .flightDate)
        departureAirportIATA = try container.decode(
            String.self,
            forKey: .departureAirportIATA
        )
        departureDate = try container.decode(Date.self, forKey: .departureDate)
        departureTimeZoneID = try container.decode(
            String.self,
            forKey: .departureTimeZoneID
        )
        departureLocalDateTime = try container.decodeIfPresent(
            String.self,
            forKey: .departureLocalDateTime
        )
        departureUTCOffsetSeconds = try container.decodeIfPresent(
            Int.self,
            forKey: .departureUTCOffsetSeconds
        )
        departureAirportName = try container.decode(
            String.self,
            forKey: .departureAirportName
        )
        departureCity = try container.decode(String.self, forKey: .departureCity)
        departureCountry = try container.decode(
            String.self,
            forKey: .departureCountry
        )
        departureCountryCode = try container.decode(
            String.self,
            forKey: .departureCountryCode
        )
        departureLatitude = try container.decode(
            Double.self,
            forKey: .departureLatitude
        )
        departureLongitude = try container.decode(
            Double.self,
            forKey: .departureLongitude
        )
        arrivalAirportIATA = try container.decode(
            String.self,
            forKey: .arrivalAirportIATA
        )
        arrivalDate = try container.decode(Date.self, forKey: .arrivalDate)
        arrivalTimeZoneID = try container.decode(
            String.self,
            forKey: .arrivalTimeZoneID
        )
        arrivalLocalDateTime = try container.decodeIfPresent(
            String.self,
            forKey: .arrivalLocalDateTime
        )
        arrivalUTCOffsetSeconds = try container.decodeIfPresent(
            Int.self,
            forKey: .arrivalUTCOffsetSeconds
        )
        arrivalAirportName = try container.decode(
            String.self,
            forKey: .arrivalAirportName
        )
        arrivalCity = try container.decode(String.self, forKey: .arrivalCity)
        arrivalCountry = try container.decode(
            String.self,
            forKey: .arrivalCountry
        )
        arrivalCountryCode = try container.decode(
            String.self,
            forKey: .arrivalCountryCode
        )
        arrivalLatitude = try container.decode(
            Double.self,
            forKey: .arrivalLatitude
        )
        arrivalLongitude = try container.decode(
            Double.self,
            forKey: .arrivalLongitude
        )
        aircraftType = try container.decodeIfPresent(
            String.self,
            forKey: .aircraftType
        )
        cabinClass = try container.decodeIfPresent(
            String.self,
            forKey: .cabinClass
        )
        seat = try container.decodeIfPresent(String.self, forKey: .seat)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    private func encodeOptional(
        _ value: String?,
        forKey key: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }

    private func encodeOptional(
        _ value: Int?,
        forKey key: CodingKeys,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }

    func makeRecord(
        ownerProfileID: UUID,
        recordID: UUID? = nil
    ) -> FlightRecord {
        let departureAirport = Airport(
            iata: departureAirportIATA,
            icao: "",
            name: departureAirportName,
            city: departureCity,
            country: departureCountry,
            countryCode: departureCountryCode,
            latitude: departureLatitude,
            longitude: departureLongitude,
            timeZoneID: departureTimeZoneID
        )
        let arrivalAirport = Airport(
            iata: arrivalAirportIATA,
            icao: "",
            name: arrivalAirportName,
            city: arrivalCity,
            country: arrivalCountry,
            countryCode: arrivalCountryCode,
            latitude: arrivalLatitude,
            longitude: arrivalLongitude,
            timeZoneID: arrivalTimeZoneID
        )
        let record = FlightRecord(
            id: recordID ?? id,
            flightNumber: flightNumber,
            airlineCode: airlineCode,
            airlineName: airlineName,
            flightDate: flightDate,
            departureAirport: departureAirport,
            arrivalAirport: arrivalAirport,
            departureDate: departureDate,
            arrivalDate: arrivalDate,
            departureLocalDateTime: departureLocalDateTime,
            departureUTCOffsetSeconds: departureUTCOffsetSeconds,
            arrivalLocalDateTime: arrivalLocalDateTime,
            arrivalUTCOffsetSeconds: arrivalUTCOffsetSeconds,
            aircraftType: aircraftType,
            cabinClass: cabinClass,
            seat: seat,
            notes: notes,
            ownerProfileID: ownerProfileID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        // Preserve every backed-up value exactly rather than reinterpreting a
        // complete JSON snapshot through current normalization rules.
        record.flightNumber = flightNumber
        record.airlineCode = airlineCode
        record.airlineName = airlineName
        record.flightDate = flightDate
        record.departureAirportIATA = departureAirportIATA
        record.departureDate = departureDate
        record.departureTimeZoneID = departureTimeZoneID
        record.departureLocalDateTime = departureLocalDateTime
        record.departureUTCOffsetSeconds = departureUTCOffsetSeconds
        record.departureAirportName = departureAirportName
        record.departureCity = departureCity
        record.departureCountry = departureCountry
        record.departureCountryCode = departureCountryCode
        record.departureLatitude = departureLatitude
        record.departureLongitude = departureLongitude
        record.arrivalAirportIATA = arrivalAirportIATA
        record.arrivalDate = arrivalDate
        record.arrivalTimeZoneID = arrivalTimeZoneID
        record.arrivalLocalDateTime = arrivalLocalDateTime
        record.arrivalUTCOffsetSeconds = arrivalUTCOffsetSeconds
        record.arrivalAirportName = arrivalAirportName
        record.arrivalCity = arrivalCity
        record.arrivalCountry = arrivalCountry
        record.arrivalCountryCode = arrivalCountryCode
        record.arrivalLatitude = arrivalLatitude
        record.arrivalLongitude = arrivalLongitude
        record.aircraftType = aircraftType
        record.cabinClass = cabinClass
        record.seat = seat
        record.notes = notes
        record.createdAt = createdAt
        record.updatedAt = updatedAt
        return record
    }
}

enum BackupRestoreMode: Equatable, Sendable {
    case merge
    case replace
    case fullRestore
}

enum FlightImportFormat: String, Equatable, Sendable {
    case csv = "CSV"
    case json = "JSON"
}

enum FlightImportIssueKind: Equatable, Sendable {
    case failure
    case duplicate
}

struct FlightImportIssue: Identifiable, Equatable, Sendable {
    let rowNumber: Int?
    let kind: FlightImportIssueKind
    let reason: String

    var id: String {
        "\(rowNumber ?? 0)|\(kind)|\(reason)"
    }
}

struct FlightImportReport: Equatable, Sendable {
    let format: FlightImportFormat
    var successCount: Int
    var failureCount: Int
    var duplicateCount: Int
    var remappedUUIDCount: Int
    var issues: [FlightImportIssue]

    init(
        format: FlightImportFormat,
        successCount: Int = 0,
        failureCount: Int = 0,
        duplicateCount: Int = 0,
        remappedUUIDCount: Int = 0,
        issues: [FlightImportIssue] = []
    ) {
        self.format = format
        self.successCount = successCount
        self.failureCount = failureCount
        self.duplicateCount = duplicateCount
        self.remappedUUIDCount = remappedUUIDCount
        self.issues = issues
    }

    var summary: String {
        let base =
            "成功 \(successCount) 条，失败 \(failureCount) 条，重复跳过 \(duplicateCount) 条"
        return remappedUUIDCount > 0
            ? "\(base)，UUID 重映射 \(remappedUUIDCount) 条"
            : base
    }

    var canCopy: Bool {
        true
    }

    var copyText: String {
        var lines = [
            "\(format.rawValue) 导入结果",
            summary,
        ]
        lines.append(
            contentsOf: issues.map { issue in
                let location = issue.rowNumber.map {
                    format == .csv ? "第 \($0) 行" : "第 \($0) 条记录"
                } ?? "文件"
                let category = issue.kind == .duplicate ? "重复" : "失败"
                return "\(location) [\(category)] \(issue.reason)"
            }
        )
        return lines.joined(separator: "\n")
    }
}

struct PreparedFlightImport: Equatable, Sendable {
    let records: [FlightRecordBackupDTO]
    let sourceProfiles: [UserProfileBackupDTO]
    let report: FlightImportReport
    let mode: BackupRestoreMode
    let mappingPlan: ProfileImportMappingPlan
    let sourceSchemaVersion: Int?
    let sourceScope: BackupExportScope?
    let existingDatasetFingerprint: FlightDatasetFingerprint
    let fingerprintScope: ImportFingerprintScope
    let occupiedRecordIDs: Set<UUID>

    var targetProfileID: UUID? {
        let targets = Set(
            mappingPlan.entries.map(\.destination.localProfileID)
        )
        return targets.count == 1 ? targets.first : nil
    }

    init(
        records: [FlightRecordBackupDTO],
        report: FlightImportReport,
        mode: BackupRestoreMode,
        targetProfileID: UUID,
        sourceProfiles: [UserProfileBackupDTO] = [],
        existingDatasetFingerprint: FlightDatasetFingerprint = .empty,
        occupiedRecordIDs: Set<UUID> = []
    ) {
        self.records = records
        self.sourceProfiles = sourceProfiles
        self.report = report
        self.mode = mode
        let sourceIDs = Set(
            records.map {
                $0.ownerProfileID
                    ?? ProfileImportMappingPlan.legacySourceProfileID
            }
        )
        mappingPlan = ProfileImportMappingPlan(
            entries: (sourceIDs.isEmpty
                ? Set([ProfileImportMappingPlan.legacySourceProfileID])
                : sourceIDs
            ).map {
                .init(
                    sourceProfileID: $0,
                    destination: .existing(targetProfileID)
                )
            }
        )
        sourceSchemaVersion = nil
        sourceScope = nil
        self.existingDatasetFingerprint = existingDatasetFingerprint
        fingerprintScope = ImportFingerprintScope(
            profileIDs: [],
            recordOwnerIDs: [targetProfileID]
        )
        self.occupiedRecordIDs = occupiedRecordIDs
    }

    init(
        records: [FlightRecordBackupDTO],
        report: FlightImportReport,
        mode: BackupRestoreMode,
        mappingPlan: ProfileImportMappingPlan,
        sourceSchemaVersion: Int?,
        sourceScope: BackupExportScope?,
        sourceProfiles: [UserProfileBackupDTO] = [],
        existingDatasetFingerprint: FlightDatasetFingerprint = .empty,
        fingerprintScope: ImportFingerprintScope? = nil,
        occupiedRecordIDs: Set<UUID> = []
    ) {
        self.records = records
        self.sourceProfiles = sourceProfiles
        self.report = report
        self.mode = mode
        self.mappingPlan = mappingPlan
        self.sourceSchemaVersion = sourceSchemaVersion
        self.sourceScope = sourceScope
        self.existingDatasetFingerprint = existingDatasetFingerprint
        self.fingerprintScope = fingerprintScope
            ?? (mode == .fullRestore
                ? .fullDataset
                : ImportFingerprintScope(
                    profileIDs: existingDatasetFingerprint.profiles.isEmpty
                        ? []
                        : nil,
                    recordOwnerIDs: Set(
                        mappingPlan.entries.compactMap {
                            guard case .existing(let id) = $0.destination else {
                                return nil
                            }
                            return id
                        }
                    )
                ))
        self.occupiedRecordIDs = occupiedRecordIDs
    }
}

struct ImportFingerprintScope: Equatable, Sendable {
    let profileIDs: Set<UUID>?
    let recordOwnerIDs: Set<UUID>?

    static let fullDataset = ImportFingerprintScope(
        profileIDs: nil,
        recordOwnerIDs: nil
    )
}

enum ProfileImportDestination: Equatable, Hashable, Sendable {
    case existing(UUID)
    case create(
        localProfileID: UUID,
        displayName: String,
        color: String
    )

    var localProfileID: UUID {
        switch self {
        case .existing(let id):
            id
        case .create(let id, _, _):
            id
        }
    }
}

struct ProfileImportMappingPlan: Equatable, Hashable, Sendable {
    struct Entry: Equatable, Hashable, Sendable {
        var sourceProfileID: UUID
        var destination: ProfileImportDestination
    }

    static let legacySourceProfileID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000004"
    )!

    var entries: [Entry]

    func localProfileID(for sourceProfileID: UUID) -> UUID? {
        entries.first { $0.sourceProfileID == sourceProfileID }?
            .destination.localProfileID
    }

    @discardableResult
    func validated(
        sourceProfiles: [UserProfileBackupDTO],
        localProfiles: [UserProfileBackupDTO]
    ) throws -> ProfileImportMappingPlan {
        let sourceIDs = Set(sourceProfiles.map(\.id))
        guard Set(entries.map(\.sourceProfileID)) == sourceIDs,
              entries.count == sourceIDs.count
        else {
            throw BackupServiceError.invalidProfileMapping("必须为每个来源用户选择目标。")
        }
        let targetIDs = entries.map(\.destination.localProfileID)
        guard Set(targetIDs).count == targetIDs.count else {
            throw BackupServiceError.invalidProfileMapping("两个来源用户不能映射到同一目标。")
        }
        let localIDs = Set(localProfiles.map(\.id))
        let existingNames = localProfiles.map(\.displayName)
        var createdNames: [String] = []
        for (index, entry) in entries.enumerated() {
            if index.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            switch entry.destination {
            case .existing(let id):
                guard localIDs.contains(id) else {
                    throw BackupServiceError.invalidProfileMapping("所选本地用户不存在。")
                }
            case let .create(id, name, _):
                guard !localIDs.contains(id) else {
                    throw BackupServiceError.invalidProfileMapping("新用户 ID 已被占用。")
                }
                let validated: String
                do {
                    validated = try UserProfileNameValidator.validatedName(
                        name,
                        existingNames: existingNames + createdNames
                    )
                } catch {
                    throw BackupServiceError.invalidProfileMapping("新用户昵称为空、过长或重复。")
                }
                createdNames.append(validated)
                guard ProfileComparisonColor(rawValue: entry.destination.color) != nil else {
                    throw BackupServiceError.invalidProfileMapping("新用户颜色无效。")
                }
            }
        }
        return self
    }
}

private extension ProfileImportDestination {
    var color: String {
        switch self {
        case .existing:
            ""
        case .create(_, _, let color):
            color
        }
    }
}

struct FlightDatasetFingerprint: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let id: UUID
        let record: FlightRecordBackupDTO
    }

    let entries: [Entry]
    let profiles: [UserProfileBackupDTO]

    static let empty = FlightDatasetFingerprint(profiles: [], recordSnapshots: [])

    init(records: [FlightRecord]) {
        self.init(profiles: [], recordSnapshots: records.map(FlightRecordBackupDTO.init))
    }

    init(recordSnapshots: [FlightRecordBackupDTO]) {
        self.init(profiles: [], recordSnapshots: recordSnapshots)
    }

    init(
        profiles: [UserProfileBackupDTO],
        recordSnapshots: [FlightRecordBackupDTO]
    ) {
        self.profiles = profiles.sorted {
            if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        entries = recordSnapshots
            .map { record in
                Entry(
                    id: record.id,
                    record: record
                )
            }
            .sorted {
                $0.id.uuidString < $1.id.uuidString
            }
    }
}
