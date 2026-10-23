import CryptoKit
import Foundation
import SwiftData

struct SampleDataGenerationResult {
    let records: [FlightRecord]
    let skippedDuplicateCount: Int
}

@MainActor
struct SampleDataGenerationService {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func prepare(
        count: Int = SampleDataGenerator.defaultCount,
        repository: AirportRepository,
        ownerProfileID: UUID
    ) throws -> SampleDataGenerationResult {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let allRecords = try context.fetch(FetchDescriptor<FlightRecord>())
        return try SampleDataGenerator.generate(
            count: count,
            repository: repository,
            existingRecords: allRecords,
            ownerProfileID: ownerProfileID,
            occupiedRecordIDs: Set(allRecords.map(\.id))
        )
    }
}

enum SampleDataGeneratorError: LocalizedError, Equatable {
    case missingAirports([String])
    case invalidDate(index: Int)
    case invalidIdentifier(index: Int)

    var errorDescription: String? {
        switch self {
        case .missingAirports(let codes):
            "无法生成示例数据，机场资料中缺少：\(codes.joined(separator: "、"))。"
        case .invalidDate(let index):
            "无法生成第 \(index + 1) 条示例航班的日期。"
        case .invalidIdentifier(let index):
            "无法生成第 \(index + 1) 条示例航班的标识。"
        }
    }
}

enum SampleDataGenerator {
    static let defaultCount = 24

    static func generate(
        count: Int = defaultCount,
        repository: AirportRepository,
        existingRecords: [FlightRecord],
        ownerProfileID: UUID,
        occupiedRecordIDs: Set<UUID>
    ) throws -> SampleDataGenerationResult {
        guard count > 0 else {
            return SampleDataGenerationResult(
                records: [],
                skippedDuplicateCount: 0
            )
        }

        let requiredCodes = Set(
            templates.flatMap { [$0.departureIATA, $0.arrivalIATA] }
        )
        let airportsByCode = Dictionary(
            uniqueKeysWithValues: requiredCodes.compactMap { code in
                repository.airport(iata: code).map { (code, $0) }
            }
        )
        let missingCodes = requiredCodes
            .filter { airportsByCode[$0] == nil }
            .sorted()
        guard missingCodes.isEmpty else {
            throw SampleDataGeneratorError.missingAirports(missingCodes)
        }

        let ownedExistingRecords = existingRecords.filter {
            $0.ownerProfileID == ownerProfileID
        }
        var existingKeys = Set(ownedExistingRecords.map(SampleBusinessKey.init))
        var existingIDs = occupiedRecordIDs
        var generated: [FlightRecord] = []
        generated.reserveCapacity(count)
        var skippedDuplicateCount = 0

        for index in 0..<count {
            let template = templates[index % templates.count]
            guard
                let departure = airportsByCode[template.departureIATA],
                let arrival = airportsByCode[template.arrivalIATA]
            else {
                throw SampleDataGeneratorError.missingAirports(
                    [template.departureIATA, template.arrivalIATA].sorted()
                )
            }
            guard
                let flightDate = calendar.date(
                    from: DateComponents(
                        year: 2019 + index % 8,
                        month: 1 + (index / 8) % 12,
                        day: 1 + (index / 96) % 28
                    )
                )
            else {
                throw SampleDataGeneratorError.invalidDate(index: index)
            }
            let id = availableID(
                index: index,
                ownerProfileID: ownerProfileID,
                occupiedRecordIDs: existingIDs
            )

            let departureDate = flightDate.addingTimeInterval(
                Double(7 + index % 10) * 3_600
            )
            let arrivalDate = departureDate.addingTimeInterval(
                Double(template.durationMinutes) * 60
            )
            let record = FlightRecord(
                id: id,
                flightNumber: "\(template.airlineCode)\(1_000 + index)",
                airlineCode: template.airlineCode,
                airlineName: template.airlineName,
                flightDate: flightDate,
                departureAirport: departure,
                arrivalAirport: arrival,
                departureDate: departureDate,
                arrivalDate: arrivalDate,
                aircraftType: template.aircraftType,
                cabinClass: index.isMultiple(of: 5) ? "商务舱" : "经济舱",
                seat: "\(1 + index % 35)\(["A", "C", "D", "F"][index % 4])",
                notes: "FlightLog 可重复示例数据",
                ownerProfileID: ownerProfileID,
                createdAt: flightDate,
                updatedAt: flightDate
            )
            let key = SampleBusinessKey(record)

            guard
                !existingKeys.contains(key),
                !existingIDs.contains(record.id)
            else {
                skippedDuplicateCount += 1
                continue
            }

            existingKeys.insert(key)
            existingIDs.insert(record.id)
            generated.append(record)
        }

        return SampleDataGenerationResult(
            records: generated,
            skippedDuplicateCount: skippedDuplicateCount
        )
    }

    private static func deterministicID(
        index: Int,
        ownerProfileID: UUID,
        collisionAttempt: Int = 0
    ) -> UUID {
        var bytes = Array(
            SHA256.hash(
                data: Data(
                    "\(ownerProfileID.uuidString):\(index):\(collisionAttempt)"
                        .utf8
                )
            ).prefix(16)
        )
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private static func availableID(
        index: Int,
        ownerProfileID: UUID,
        occupiedRecordIDs: Set<UUID>
    ) -> UUID {
        var attempt = 0
        while true {
            let candidate = deterministicID(
                index: index,
                ownerProfileID: ownerProfileID,
                collisionAttempt: attempt
            )
            if !occupiedRecordIDs.contains(candidate) {
                return candidate
            }
            attempt += 1
        }
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static let templates: [Template] = [
        Template(
            departureIATA: "PEK",
            arrivalIATA: "SHA",
            airlineCode: "CA",
            airlineName: "中国国际航空",
            durationMinutes: 135,
            aircraftType: "Airbus A321"
        ),
        Template(
            departureIATA: "CAN",
            arrivalIATA: "CTU",
            airlineCode: "CZ",
            airlineName: "中国南方航空",
            durationMinutes: 150,
            aircraftType: "Airbus A320"
        ),
        Template(
            departureIATA: "HND",
            arrivalIATA: "ITM",
            airlineCode: "NH",
            airlineName: "全日空",
            durationMinutes: 70,
            aircraftType: "Boeing 787-8"
        ),
        Template(
            departureIATA: "LAX",
            arrivalIATA: "JFK",
            airlineCode: "DL",
            airlineName: "达美航空",
            durationMinutes: 325,
            aircraftType: "Airbus A321neo"
        ),
        Template(
            departureIATA: "PEK",
            arrivalIATA: "HND",
            airlineCode: "JL",
            airlineName: "日本航空",
            durationMinutes: 210,
            aircraftType: "Boeing 787-9"
        ),
        Template(
            departureIATA: "HND",
            arrivalIATA: "LAX",
            airlineCode: "JL",
            airlineName: "日本航空",
            durationMinutes: 610,
            aircraftType: "Boeing 787-9"
        ),
        Template(
            departureIATA: "LHR",
            arrivalIATA: "CDG",
            airlineCode: "BA",
            airlineName: "英国航空",
            durationMinutes: 80,
            aircraftType: "Airbus A320neo"
        ),
        Template(
            departureIATA: "SIN",
            arrivalIATA: "SYD",
            airlineCode: "SQ",
            airlineName: "新加坡航空",
            durationMinutes: 475,
            aircraftType: "Airbus A350-900"
        ),
        Template(
            departureIATA: "DXB",
            arrivalIATA: "LHR",
            airlineCode: "EK",
            airlineName: "阿联酋航空",
            durationMinutes: 455,
            aircraftType: "Airbus A380-800"
        ),
        Template(
            departureIATA: "YUL",
            arrivalIATA: "JFK",
            airlineCode: "AC",
            airlineName: "加拿大航空",
            durationMinutes: 105,
            aircraftType: "Airbus A220-300"
        ),
        Template(
            departureIATA: "FRA",
            arrivalIATA: "SIN",
            airlineCode: "LH",
            airlineName: "德国汉莎航空",
            durationMinutes: 745,
            aircraftType: "Airbus A350-900"
        ),
        Template(
            departureIATA: "SFO",
            arrivalIATA: "YVR",
            airlineCode: "UA",
            airlineName: "美国联合航空",
            durationMinutes: 145,
            aircraftType: "Boeing 737 MAX 8"
        ),
    ]

    private struct Template {
        let departureIATA: String
        let arrivalIATA: String
        let airlineCode: String
        let airlineName: String
        let durationMinutes: Int
        let aircraftType: String
    }

    private struct SampleBusinessKey: Hashable {
        let flightNumber: String
        let flightDate: Date
        let departureIATA: String
        let arrivalIATA: String

        init(_ record: FlightRecord) {
            flightNumber = FlightRecordNormalization.code(record.flightNumber)
            flightDate = FlightDateNormalization.canonicalDate(record.flightDate)
            departureIATA = FlightRecordNormalization.code(
                record.departureAirportIATA
            )
            arrivalIATA = FlightRecordNormalization.code(
                record.arrivalAirportIATA
            )
        }
    }
}
