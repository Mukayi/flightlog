import Foundation
import XCTest
@testable import FlightLog

final class FlightWorkflowTests: XCTestCase {
    private let beijing = Airport(
        iata: "PEK",
        icao: "ZBAA",
        name: "Beijing Capital International Airport",
        city: "Beijing",
        country: "China",
        countryCode: "CN",
        latitude: 40.0801,
        longitude: 116.5846,
        timeZoneID: "Asia/Shanghai"
    )

    private let montreal = Airport(
        iata: "YUL",
        icao: "CYUL",
        name: "Montréal–Trudeau International Airport",
        city: "Montréal",
        country: "Canada",
        countryCode: "CA",
        latitude: 45.4706,
        longitude: -73.7408,
        timeZoneID: "America/Toronto"
    )

    private let tokyo = Airport(
        iata: "HND",
        icao: "RJTT",
        name: "Tokyo Haneda Airport",
        city: "Tokyo",
        country: "Japan",
        countryCode: "JP",
        latitude: 35.5494,
        longitude: 139.7798,
        timeZoneID: "Asia/Tokyo"
    )

    private let losAngeles = Airport(
        iata: "LAX",
        icao: "KLAX",
        name: "Los Angeles International Airport",
        city: "Los Angeles",
        country: "United States",
        countryCode: "US",
        latitude: 33.9416,
        longitude: -118.4085,
        timeZoneID: "America/Los_Angeles"
    )

    func testDraftNormalizesFlightNumberByRemovingWhitespaceAndUppercasing() {
        var draft = makeValidDraft()
        draft.flightNumber = " ca  12\t3 "

        XCTAssertEqual(draft.normalizedFlightNumber, "CA123")
    }

    func testChangingFlightDateMovesLocalJourneyDatesAndPreservesTimes() {
        var draft = makeValidDraft()
        draft.departureLocalDate = wallClockDate(2026, 8, 18, 23, 30)
        draft.arrivalLocalDate = wallClockDate(2026, 8, 19, 7, 45)

        draft.setFlightDate(wallClockDate(2026, 9, 5, 0, 0))

        XCTAssertEqual(
            draft.flightDate,
            wallClockDate(2026, 9, 5, 0, 0)
        )
        XCTAssertEqual(
            draft.departureLocalDate,
            wallClockDate(2026, 9, 5, 23, 30)
        )
        XCTAssertEqual(
            draft.arrivalLocalDate,
            wallClockDate(2026, 9, 6, 7, 45)
        )
    }

    func testLocalWallClockConvertsUsingAirportTimeZone() throws {
        let localTime = wallClockDate(2026, 8, 18, 10, 30)
        let expectedUTC = wallClockDate(2026, 8, 18, 2, 30)

        let converted = try LocalDateTimeConverter.absoluteDate(
            from: localTime,
            timeZoneID: "Asia/Shanghai"
        )

        XCTAssertEqual(converted, expectedUTC)
    }

    func testLocalWallClockRejectsNonexistentDaylightSavingTime() {
        let nonexistentTime = wallClockDate(2026, 3, 8, 2, 30)

        XCTAssertThrowsError(
            try LocalDateTimeConverter.absoluteDate(
                from: nonexistentTime,
                timeZoneID: "America/Los_Angeles"
            )
        ) { error in
            XCTAssertEqual(
                error as? LocalDateTimeConversionError,
                .nonexistentLocalTime
            )
        }
    }

    func testResolverReturnsBothRepeatedHourCandidatesAndDraftSelectsOccurrence() throws {
        var draft = makeValidDraft()
        draft.departureAirport = losAngeles
        draft.departureLocalDate = wallClockDate(2026, 11, 1, 1, 30)
        draft.arrivalLocalDate = wallClockDate(2026, 11, 2, 8, 0)

        let resolution = try LocalWallClockResolver.resolve(
            draft.departureLocalDate,
            timeZoneID: losAngeles.timeZoneID
        )

        XCTAssertEqual(resolution.candidates.count, 2)
        XCTAssertEqual(
            resolution.candidates.map(\.occurrence),
            [.first, .second]
        )
        XCTAssertEqual(
            resolution.candidates.map(\.utcOffsetSeconds),
            [-25_200, -28_800]
        )
        XCTAssertEqual(
            draft.departureAmbiguityChoices,
            [.first, .second]
        )

        draft.departureLocalTimeOccurrence = .second
        let result = validator.validate(draft)
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(
            result.departureDate,
            wallClockDate(2026, 11, 1, 9, 30)
        )
        XCTAssertEqual(result.departureUTCOffsetSeconds, -28_800)
    }

    func testValidatorRequiresBothAirports() {
        var draft = makeValidDraft()
        draft.departureAirport = nil
        draft.arrivalAirport = nil

        let result = validator.validate(draft)

        XCTAssertNotNil(result.errors[.departureAirport])
        XCTAssertNotNil(result.errors[.arrivalAirport])
    }

    func testValidatorRejectsIdenticalAirports() {
        var draft = makeValidDraft()
        draft.arrivalAirport = beijing

        let result = validator.validate(draft)

        XCTAssertNotNil(result.errors[.arrivalAirport])
    }

    func testValidatorRejectsAirportOutsideRepository() {
        var draft = makeValidDraft()
        draft.departureAirport = Airport(
            iata: "ZZZ",
            icao: "ZZZZ",
            name: "Unknown",
            city: "Unknown",
            country: "Unknown",
            countryCode: "ZZ",
            latitude: 0,
            longitude: 0,
            timeZoneID: "Etc/UTC"
        )

        let result = validator.validate(draft)

        XCTAssertNotNil(result.errors[.departureAirport])
    }

    func testValidatorComparesAbsoluteArrivalAndDepartureTimes() {
        var draft = makeValidDraft()
        draft.departureAirport = montreal
        draft.arrivalAirport = beijing
        draft.departureLocalDate = wallClockDate(2026, 8, 18, 10, 0)
        draft.arrivalLocalDate = wallClockDate(2026, 8, 18, 17, 0)

        let result = validator.validate(draft)

        XCTAssertNotNil(result.errors[.arrivalLocalDate])
        XCTAssertNil(result.durationMinutes)
    }

    func testValidatorReturnsDurationFromConvertedAbsoluteTimes() {
        let result = validator.validate(makeValidDraft())

        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.durationMinutes, 600)
    }

    func testValidatorEnforcesOptionalFieldLengthBoundaries() {
        var accepted = makeValidDraft()
        accepted.aircraftType = String(repeating: "A", count: 80)
        accepted.cabinClass = String(repeating: "B", count: 40)
        accepted.seat = String(repeating: "C", count: 20)
        accepted.notes = String(repeating: "D", count: 2_000)

        let acceptedResult = validator.validate(accepted)

        XCTAssertNil(acceptedResult.errors[.aircraftType])
        XCTAssertNil(acceptedResult.errors[.cabinClass])
        XCTAssertNil(acceptedResult.errors[.seat])
        XCTAssertNil(acceptedResult.errors[.notes])

        var rejected = accepted
        rejected.aircraftType.append("A")
        rejected.cabinClass.append("B")
        rejected.seat.append("C")
        rejected.notes.append("D")

        let rejectedResult = validator.validate(rejected)

        XCTAssertNotNil(rejectedResult.errors[.aircraftType])
        XCTAssertNotNil(rejectedResult.errors[.cabinClass])
        XCTAssertNotNil(rejectedResult.errors[.seat])
        XCTAssertNotNil(rejectedResult.errors[.notes])
    }

    func testWriterCreatesRecordWithCanonicalValuesAndAirportSnapshots() throws {
        var draft = makeValidDraft()
        draft.flightNumber = " ca 123 "
        draft.airlineCode = " ca "
        draft.airlineName = " Air China "
        draft.notes = "  靠窗  "
        let now = wallClockDate(2026, 8, 20, 12, 0)

        let record = try FlightRecordWriter.makeRecord(
            from: draft,
            repository: repository,
            ownerProfileID: UserProfileDefaults.id,
            now: now
        )

        XCTAssertEqual(record.flightNumber, "CA123")
        XCTAssertEqual(record.airlineCode, "CA")
        XCTAssertEqual(record.airlineName, "Air China")
        XCTAssertEqual(record.flightDate, wallClockDate(2026, 8, 18, 0, 0))
        XCTAssertEqual(record.departureAirportIATA, "PEK")
        XCTAssertEqual(record.departureAirportName, beijing.name)
        XCTAssertEqual(record.departureCity, beijing.city)
        XCTAssertEqual(record.departureCountry, beijing.country)
        XCTAssertEqual(record.departureLatitude, beijing.latitude)
        XCTAssertEqual(record.departureLongitude, beijing.longitude)
        XCTAssertEqual(record.departureTimeZoneID, beijing.timeZoneID)
        XCTAssertEqual(record.arrivalAirportIATA, "YUL")
        XCTAssertEqual(record.arrivalAirportName, montreal.name)
        XCTAssertEqual(record.arrivalTimeZoneID, montreal.timeZoneID)
        XCTAssertEqual(record.departureDate, wallClockDate(2026, 8, 18, 2, 0))
        XCTAssertEqual(record.arrivalDate, wallClockDate(2026, 8, 18, 12, 0))
        XCTAssertEqual(record.notes, "靠窗")
        XCTAssertEqual(record.createdAt, now)
        XCTAssertEqual(record.updatedAt, now)
    }

    func testWriterUpdatesSnapshotsAndTimestampWithoutChangingIdentity() throws {
        let createdAt = wallClockDate(2026, 8, 1, 0, 0)
        let record = try FlightRecordWriter.makeRecord(
            from: makeValidDraft(),
            repository: repository,
            ownerProfileID: UserProfileDefaults.id,
            now: createdAt
        )
        let originalID = record.id
        var edited = makeValidDraft()
        edited.departureAirport = montreal
        edited.arrivalAirport = tokyo
        edited.departureLocalDate = wallClockDate(2026, 8, 19, 8, 0)
        edited.arrivalLocalDate = wallClockDate(2026, 8, 20, 8, 0)
        edited.flightNumber = " ac 7 "
        let updatedAt = wallClockDate(2026, 8, 2, 0, 0)

        try FlightRecordWriter.update(
            record,
            from: edited,
            repository: repository,
            ownerProfileID: UserProfileDefaults.id,
            now: updatedAt
        )

        XCTAssertEqual(record.id, originalID)
        XCTAssertEqual(record.createdAt, createdAt)
        XCTAssertEqual(record.updatedAt, updatedAt)
        XCTAssertEqual(record.flightNumber, "AC7")
        XCTAssertEqual(record.departureAirportIATA, "YUL")
        XCTAssertEqual(record.departureAirportName, montreal.name)
        XCTAssertEqual(record.arrivalAirportIATA, "HND")
        XCTAssertEqual(record.arrivalCity, tokyo.city)
        XCTAssertEqual(record.arrivalTimeZoneID, tokyo.timeZoneID)
    }

    func testEditingOnlyNotesPreservesSavedSnapshotAndAbsoluteTimesWhenRepositoryChanges() throws {
        let record = try FlightRecordWriter.makeRecord(
            from: makeValidDraft(),
            repository: repository,
            ownerProfileID: UserProfileDefaults.id
        )
        let departureDate = record.departureDate
        let arrivalDate = record.arrivalDate
        let departureSnapshot = (
            record.departureAirportName,
            record.departureCity,
            record.departureCountry,
            record.departureLatitude,
            record.departureLongitude,
            record.departureTimeZoneID
        )
        let changedBeijing = Airport(
            iata: "PEK",
            icao: "ZBAA",
            name: "Renamed Beijing Airport",
            city: "New Beijing",
            country: "Updated China",
            countryCode: "CN",
            latitude: 41,
            longitude: 117,
            timeZoneID: "Asia/Tokyo"
        )
        let changedRepository = AirportRepository(
            airports: [changedBeijing, montreal]
        )
        var draft = FlightDraft(record: record, repository: changedRepository)
        draft.notes = "只修改备注"

        try FlightRecordWriter.update(
            record,
            from: draft,
            repository: changedRepository,
            ownerProfileID: UserProfileDefaults.id
        )

        XCTAssertEqual(record.departureDate, departureDate)
        XCTAssertEqual(record.arrivalDate, arrivalDate)
        XCTAssertEqual(record.departureAirportName, departureSnapshot.0)
        XCTAssertEqual(record.departureCity, departureSnapshot.1)
        XCTAssertEqual(record.departureCountry, departureSnapshot.2)
        XCTAssertEqual(record.departureLatitude, departureSnapshot.3)
        XCTAssertEqual(record.departureLongitude, departureSnapshot.4)
        XCTAssertEqual(record.departureTimeZoneID, departureSnapshot.5)
        XCTAssertEqual(record.notes, "只修改备注")
    }

    func testEditingRecordStillSavesWhenSavedAirportWasRemovedFromRepository() throws {
        let record = try FlightRecordWriter.makeRecord(
            from: makeValidDraft(),
            repository: repository,
            ownerProfileID: UserProfileDefaults.id
        )
        let departureDate = record.departureDate
        let departureName = record.departureAirportName
        let repositoryWithoutDeparture = AirportRepository(
            airports: [montreal]
        )
        var draft = FlightDraft(
            record: record,
            repository: repositoryWithoutDeparture
        )
        draft.notes = "机场已下线仍可编辑"

        do {
            try FlightRecordWriter.update(
                record,
                from: draft,
                repository: repositoryWithoutDeparture,
                ownerProfileID: UserProfileDefaults.id
            )
        } catch {
            XCTFail("只修改备注不应依赖当前机场库：\(error)")
            return
        }

        XCTAssertEqual(record.departureDate, departureDate)
        XCTAssertEqual(record.departureAirportName, departureName)
        XCTAssertEqual(record.notes, "机场已下线仍可编辑")
    }

    func testDraftForEditingRestoresAirportSelectionsAndLocalWallClocks() throws {
        let record = try FlightRecordWriter.makeRecord(
            from: makeValidDraft(),
            repository: repository,
            ownerProfileID: UserProfileDefaults.id
        )

        let draft = FlightDraft(record: record, repository: repository)

        XCTAssertEqual(draft.departureAirport?.iata, "PEK")
        XCTAssertEqual(draft.arrivalAirport?.iata, "YUL")
        XCTAssertEqual(
            draft.departureLocalDate,
            wallClockDate(2026, 8, 18, 10, 0)
        )
        XCTAssertEqual(
            draft.arrivalLocalDate,
            wallClockDate(2026, 8, 18, 8, 0)
        )
    }

    func testDuplicateDetectorUsesNormalizedNumberDateAndRoute() throws {
        let record = try FlightRecordWriter.makeRecord(
            from: makeValidDraft(),
            repository: repository,
            ownerProfileID: UserProfileDefaults.id,
            now: wallClockDate(2026, 8, 1, 0, 0)
        )
        var candidate = makeValidDraft()
        candidate.flightNumber = " ca 123 "
        candidate.flightDate = wallClockDate(2026, 8, 18, 18, 45)

        let duplicates = FlightDuplicateDetector.matches(
            candidate,
            in: [record],
            ownerProfileID: UserProfileDefaults.id
        )

        XCTAssertEqual(duplicates.map(\.id), [record.id])
    }

    func testDuplicateDetectorCanExcludeEditedRecord() throws {
        let record = try FlightRecordWriter.makeRecord(
            from: makeValidDraft(),
            repository: repository,
            ownerProfileID: UserProfileDefaults.id,
            now: wallClockDate(2026, 8, 1, 0, 0)
        )

        let duplicates = FlightDuplicateDetector.matches(
            makeValidDraft(),
            in: [record],
            ownerProfileID: UserProfileDefaults.id,
            excluding: record.id
        )

        XCTAssertTrue(duplicates.isEmpty)
    }

    func testDuplicateDetectorDerivesDateFromDepartureWallClock() throws {
        let record = try FlightRecordWriter.makeRecord(
            from: makeValidDraft(),
            repository: repository,
            ownerProfileID: UserProfileDefaults.id
        )
        var candidate = makeValidDraft()
        candidate.flightDate = wallClockDate(2035, 1, 1, 0, 0)

        let duplicates = FlightDuplicateDetector.matches(
            candidate,
            in: [record],
            ownerProfileID: UserProfileDefaults.id
        )

        XCTAssertEqual(duplicates.map(\.id), [record.id])
    }

    func testListSearchMatchesFlightAirlineAirportAndCity() throws {
        let airChina = try FlightRecordWriter.makeRecord(
            from: makeValidDraft(),
            repository: repository,
            ownerProfileID: UserProfileDefaults.id
        )
        var japanDraft = makeValidDraft()
        japanDraft.flightNumber = "JL20"
        japanDraft.airlineCode = "JL"
        japanDraft.airlineName = "Japan Airlines"
        japanDraft.departureAirport = tokyo
        japanDraft.arrivalAirport = beijing
        japanDraft.departureLocalDate = wallClockDate(2026, 8, 19, 8, 0)
        japanDraft.arrivalLocalDate = wallClockDate(2026, 8, 19, 12, 0)
        japanDraft.flightDate = wallClockDate(2026, 8, 19, 0, 0)
        let japan = try FlightRecordWriter.makeRecord(
            from: japanDraft,
            repository: repository,
            ownerProfileID: UserProfileDefaults.id
        )
        let records = [airChina, japan]

        XCTAssertEqual(
            FlightListQuery.apply(to: records, searchText: "ca123").map(\.id),
            [airChina.id]
        )
        XCTAssertEqual(
            FlightListQuery.apply(to: records, searchText: "japan").map(\.id),
            [japan.id]
        )
        XCTAssertEqual(
            FlightListQuery.apply(to: records, searchText: "yul").map(\.id),
            [airChina.id]
        )
        XCTAssertEqual(
            FlightListQuery.apply(to: records, searchText: "montreal").map(\.id),
            [airChina.id]
        )
    }

    func testListQuerySortsByDateFlightNumberAndRoute() throws {
        let records = try makeListRecords()

        XCTAssertEqual(
            FlightListQuery.apply(
                to: records,
                sortOrder: .dateDescending
            ).map(\.flightNumber),
            ["JL20", "CA123", "AC7"]
        )
        XCTAssertEqual(
            FlightListQuery.apply(
                to: records,
                sortOrder: .flightNumber
            ).map(\.flightNumber),
            ["AC7", "CA123", "JL20"]
        )
        XCTAssertEqual(
            FlightListQuery.apply(
                to: records,
                sortOrder: .route
            ).map(\.flightNumber),
            ["JL20", "CA123", "AC7"]
        )
    }

    func testListQueryCombinesYearAirlineAndAirportFilters() throws {
        let records = try makeListRecords()
        let filter = FlightListFilter(
            year: 2026,
            airline: "CA",
            airportIATA: "YUL"
        )

        let result = FlightListQuery.apply(
            to: records,
            filter: filter
        )

        XCTAssertEqual(result.map(\.flightNumber), ["CA123"])
    }

    func testListSelectionClearsHiddenRecordAndKeepsVisibleRecord() {
        let selectedID = UUID()

        XCTAssertNil(
            FlightListSelection.reconciled(
                selectedID: selectedID,
                visibleIDs: [UUID()]
            )
        )
        XCTAssertEqual(
            FlightListSelection.reconciled(
                selectedID: selectedID,
                visibleIDs: [selectedID]
            ),
            selectedID
        )
    }

    private var repository: AirportRepository {
        AirportRepository(airports: [beijing, losAngeles, montreal, tokyo])
    }

    private var validator: FlightValidator {
        FlightValidator(repository: repository)
    }

    private func makeValidDraft() -> FlightDraft {
        FlightDraft(
            flightDate: wallClockDate(2026, 8, 18, 0, 0),
            flightNumber: "CA123",
            airlineCode: "CA",
            airlineName: "Air China",
            departureAirport: beijing,
            arrivalAirport: montreal,
            departureLocalDate: wallClockDate(2026, 8, 18, 10, 0),
            arrivalLocalDate: wallClockDate(2026, 8, 18, 8, 0),
            aircraftType: "Boeing 787-9",
            cabinClass: "商务舱",
            seat: "3A",
            notes: "测试"
        )
    }

    private func makeListRecords() throws -> [FlightRecord] {
        var airCanadaDraft = makeValidDraft()
        airCanadaDraft.flightNumber = "AC7"
        airCanadaDraft.airlineCode = "AC"
        airCanadaDraft.airlineName = "Air Canada"
        airCanadaDraft.departureAirport = montreal
        airCanadaDraft.arrivalAirport = beijing
        airCanadaDraft.departureLocalDate = wallClockDate(2025, 12, 31, 8, 0)
        airCanadaDraft.arrivalLocalDate = wallClockDate(2026, 1, 1, 8, 0)
        airCanadaDraft.flightDate = wallClockDate(2025, 12, 31, 0, 0)

        var japanDraft = makeValidDraft()
        japanDraft.flightNumber = "JL20"
        japanDraft.airlineCode = "JL"
        japanDraft.airlineName = "Japan Airlines"
        japanDraft.departureAirport = tokyo
        japanDraft.arrivalAirport = beijing
        japanDraft.departureLocalDate = wallClockDate(2026, 8, 19, 8, 0)
        japanDraft.arrivalLocalDate = wallClockDate(2026, 8, 19, 12, 0)
        japanDraft.flightDate = wallClockDate(2026, 8, 19, 0, 0)

        return try [
            FlightRecordWriter.makeRecord(
                from: makeValidDraft(),
                repository: repository,
                ownerProfileID: UserProfileDefaults.id
            ),
            FlightRecordWriter.makeRecord(
                from: airCanadaDraft,
                repository: repository,
                ownerProfileID: UserProfileDefaults.id
            ),
            FlightRecordWriter.makeRecord(
                from: japanDraft,
                repository: repository,
                ownerProfileID: UserProfileDefaults.id
            ),
        ]
    }

    private func wallClockDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}
