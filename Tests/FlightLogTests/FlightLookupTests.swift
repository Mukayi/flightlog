import Foundation
import XCTest
@testable import FlightLog

final class FlightLookupTests: XCTestCase {
    func testBuildsEncodedRequestWithRapidAPIHeadersAndTimeout() async throws {
        let transport = RecordingTransport(responseData: fixture)
        let client = AeroDataBoxClient(transport: transport)

        _ = try await client.lookup(
            flightNumber: "CA 123/测试",
            localDate: date(2026, 11, 1),
            apiKey: "secret-key"
        )

        let capturedRequest = await transport.lastRequest
        let request = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://aerodatabox.p.rapidapi.com/flights/number/CA%20123%2F%E6%B5%8B%E8%AF%95/2026-11-01?withAircraftImage=false&withLocation=false&withFlightPlan=false&dateLocalRole=Departure"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "x-rapidapi-host"),
            "aerodatabox.p.rapidapi.com"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "x-rapidapi-key"),
            "secret-key"
        )
        XCTAssertEqual(request.timeoutInterval, 15)
    }

    func testDecodesOfficialFlightContractAndChoosesBestTimes() async throws {
        let client = AeroDataBoxClient(
            transport: RecordingTransport(responseData: fixture)
        )

        let results = try await client.lookup(
            flightNumber: "CA123",
            localDate: date(2026, 11, 1),
            apiKey: "key"
        )

        XCTAssertEqual(results.count, 2)
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.flightNumber, "CA123")
        XCTAssertEqual(result.airlineCode, "CA")
        XCTAssertEqual(result.airlineName, "Air China")
        XCTAssertEqual(result.aircraftType, "Boeing 787-9")
        XCTAssertEqual(result.departure.airportIATA, "LAX")
        XCTAssertEqual(result.departure.airportTimeZoneID, "America/Los_Angeles")
        XCTAssertEqual(result.departure.time?.source, .runway)
        XCTAssertEqual(result.departure.time?.local, "2026-11-01T01:30:00")
        XCTAssertEqual(result.departure.time?.absoluteDate, iso("2026-11-01T09:30:00Z"))
        XCTAssertEqual(result.arrival.time?.source, .revised)
        XCTAssertEqual(result.arrival.time?.absoluteDate, iso("2026-11-01T18:15:00Z"))
    }

    func testTimePriorityFallsBackThroughRevisedPredictedAndScheduled() async throws {
        let data = Data("""
        [{
          "number":"T1",
          "departure":{"airport":{"iata":"LAX","timeZone":"America/Los_Angeles"},
            "scheduledTime":{"utc":"2026-11-01 10:00Z","local":"2026-11-01 02:00-08:00"},
            "predictedTime":{"utc":"2026-11-01 10:10Z","local":"2026-11-01 02:10-08:00"}},
          "arrival":{"airport":{"iata":"JFK","timeZone":"America/New_York"},
            "scheduledTime":{"utc":"2026-11-01 18:00Z","local":"2026-11-01 13:00-05:00"}}
        }]
        """.utf8)

        let results = try await AeroDataBoxClient(
            transport: RecordingTransport(responseData: data)
        ).lookup(
            flightNumber: "T1",
            localDate: date(2026, 11, 1),
            apiKey: "k"
        )
        let result = try XCTUnwrap(results.first)

        XCTAssertEqual(result.departure.time?.source, .predicted)
        XCTAssertEqual(result.arrival.time?.source, .scheduled)
    }

    func testMapsStatusAndTransportErrorsToChineseErrors() async {
        for (status, expected, message) in [
            (404, AeroDataBoxError.noResults, "没有找到该当地起飞日期对应的航班。"),
            (401, AeroDataBoxError.unauthorized, "API key 无效或无权访问此接口（401/403）。"),
            (403, AeroDataBoxError.unauthorized, "API key 无效或无权访问此接口（401/403）。"),
            (429, AeroDataBoxError.rateLimited, "RapidAPI 配额已用尽或请求过于频繁（429），请稍后重试。"),
            (503, AeroDataBoxError.serverUnavailable, "AeroDataBox 服务暂时不可用（5xx），请稍后重试。"),
        ] {
            await assertLookupError(
                transport: RecordingTransport(responseData: Data(), statusCode: status),
                expected: expected,
                expectedMessage: message
            )
        }
        await assertLookupError(
            transport: RecordingTransport(error: URLError(.timedOut)),
            expected: .timedOut,
            expectedMessage: "联网查询超时（15 秒），请稍后重试。"
        )
        await assertLookupError(
            transport: RecordingTransport(error: URLError(.notConnectedToInternet)),
            expected: .offline,
            expectedMessage: "当前网络不可用，请检查连接后重试。"
        )
        await assertLookupError(
            transport: RecordingTransport(responseData: Data("{}".utf8)),
            expected: .decodingFailed,
            expectedMessage: "AeroDataBox 返回了无法识别的数据。"
        )
        await assertLookupError(
            transport: RecordingTransport(responseData: Data("[]".utf8)),
            expected: .noResults,
            expectedMessage: "没有找到该当地起飞日期对应的航班。"
        )
        await assertLookupError(
            transport: RecordingTransport(responseData: Data(), statusCode: 204),
            expected: .noResults,
            expectedMessage: "没有找到该当地起飞日期对应的航班。"
        )
    }

    func testLocalTimePresentationKeepsMinuteZero() {
        XCTAssertEqual(
            FlightLookupPresentation.localTime("2026-11-01T13:00:00"),
            "2026-11-01 13:00"
        )
        XCTAssertEqual(
            FlightLookupPresentation.localTime("2026-11-01 01:30-08:00"),
            "2026-11-01 01:30"
        )
    }

    @MainActor
    func testCoordinatorReadsKeyQueriesWaitsForCandidateAndAppliesAfterSelection() async throws {
        let original = populatedDraft()
        let store = TrackingAPIKeyStore(value: "key")
        let client = StubLookupClient(results: [lookupResult])
        let coordinator = FlightLookupCoordinator(
            draft: original,
            repository: lookupRepository,
            isEditing: false,
            keyStore: store,
            client: client
        )

        await coordinator.query(currentDraft: { original })

        XCTAssertEqual(store.loadCount, 1)
        XCTAssertEqual(client.lastFlightNumber, "KEEP123")
        XCTAssertEqual(client.lastLocalDate, original.departureLocalDate)
        XCTAssertEqual(client.lastAPIKey, "key")
        guard case .awaitingCandidateSelection(let results) = coordinator.state else {
            return XCTFail("应等待候选确认")
        }
        XCTAssertEqual(results, [lookupResult])
        assertDraft(coordinator.draft, equals: original)

        coordinator.selectCandidate(lookupResult, currentDraft: original)

        guard case .applied(let report) = coordinator.state else {
            return XCTFail("选择后应应用结果")
        }
        XCTAssertTrue(report.filledFields.contains("航班号"))
        XCTAssertEqual(coordinator.draft.flightNumber, "CA123")
        XCTAssertEqual(coordinator.draft.departureAirport?.iata, "LAX")
    }

    @MainActor
    func testCoordinatorEditingRequiresSecondConfirmationAndCancelPreservesEveryField() async {
        let original = populatedDraft()
        let coordinator = FlightLookupCoordinator(
            draft: original,
            repository: lookupRepository,
            isEditing: true,
            keyStore: TrackingAPIKeyStore(value: "key"),
            client: StubLookupClient(results: [lookupResult])
        )

        await coordinator.query(currentDraft: { original })
        coordinator.selectCandidate(lookupResult, currentDraft: original)

        guard case .awaitingOverwriteConfirmation = coordinator.state else {
            return XCTFail("编辑已有记录必须等待二次覆盖确认")
        }
        assertDraft(coordinator.draft, equals: original)

        coordinator.cancel()

        XCTAssertEqual(coordinator.state, .idle)
        assertDraft(coordinator.draft, equals: original)
    }

    @MainActor
    func testCoordinatorEditingAppliesOnlyAfterOverwriteConfirmation() async {
        let coordinator = FlightLookupCoordinator(
            draft: populatedDraft(),
            repository: lookupRepository,
            isEditing: true,
            keyStore: TrackingAPIKeyStore(value: "key"),
            client: StubLookupClient(results: [lookupResult])
        )

        let draft = coordinator.draft
        await coordinator.query(currentDraft: { draft })
        coordinator.selectCandidate(lookupResult, currentDraft: draft)
        coordinator.confirmOverwrite(currentDraft: draft)

        guard case .applied = coordinator.state else {
            return XCTFail("二次确认后应应用结果")
        }
        XCTAssertEqual(coordinator.draft.flightNumber, "CA123")
    }

    @MainActor
    func testCoordinatorFailureAndCandidateCancelPreserveEveryDraftField() async {
        let original = populatedDraft()
        let failed = FlightLookupCoordinator(
            draft: original,
            repository: lookupRepository,
            isEditing: false,
            keyStore: TrackingAPIKeyStore(value: "key"),
            client: StubLookupClient(error: AeroDataBoxError.offline)
        )

        await failed.query(currentDraft: { original })

        XCTAssertEqual(
            failed.state,
            .failed("当前网络不可用，请检查连接后重试。")
        )
        assertDraft(failed.draft, equals: original)

        let cancelled = FlightLookupCoordinator(
            draft: original,
            repository: lookupRepository,
            isEditing: false,
            keyStore: TrackingAPIKeyStore(value: "key"),
            client: StubLookupClient(results: [lookupResult])
        )
        await cancelled.query(currentDraft: { original })
        cancelled.cancel()

        XCTAssertEqual(cancelled.state, .idle)
        assertDraft(cancelled.draft, equals: original)
    }

    @MainActor
    func testCoordinatorPreservesLatestNotesAndSeatEditedDuringQuery() async {
        let original = populatedDraft()
        var latest = original
        let client = SuspendedLookupClient()
        let coordinator = FlightLookupCoordinator(
            draft: original,
            repository: lookupRepository,
            isEditing: false,
            keyStore: TrackingAPIKeyStore(value: "key"),
            client: client
        )
        let task = Task {
            await coordinator.query(currentDraft: { latest })
        }
        await client.waitUntilStarted()
        latest.notes = "查询期间的新备注"
        latest.seat = "22F"
        latest.cabinClass = "最新舱位"
        await client.succeed(with: [lookupResult])
        await task.value

        coordinator.selectCandidate(lookupResult, currentDraft: latest)

        guard case .applied = coordinator.state else {
            return XCTFail("身份未变时应应用候选")
        }
        XCTAssertEqual(coordinator.draft.notes, "查询期间的新备注")
        XCTAssertEqual(coordinator.draft.seat, "22F")
        XCTAssertEqual(coordinator.draft.cabinClass, "最新舱位")
    }

    @MainActor
    func testCoordinatorRejectsResultWhenFlightNumberOrDepartureDateChangesDuringQuery() async {
        for changeIdentity in [
            { (draft: inout FlightDraft) in draft.flightNumber = "NEW456" },
            { (draft: inout FlightDraft) in
                draft.departureLocalDate = self.date(2026, 8, 19, 10, 5)
            },
        ] {
            let original = populatedDraft()
            var latest = original
            let client = SuspendedLookupClient()
            let coordinator = FlightLookupCoordinator(
                draft: original,
                repository: lookupRepository,
                isEditing: false,
                keyStore: TrackingAPIKeyStore(value: "key"),
                client: client
            )
            let task = Task {
                await coordinator.query(currentDraft: { latest })
            }
            await client.waitUntilStarted()
            changeIdentity(&latest)
            await client.succeed(with: [lookupResult])
            await task.value

            XCTAssertEqual(
                coordinator.state,
                .failed("航班号或日期已更改，请重新查询")
            )
            assertDraft(coordinator.draft, equals: latest)
        }
    }

    @MainActor
    func testEditingOverwriteConfirmationAppliesOntoLatestDraftBase() async {
        let original = populatedDraft()
        var latest = original
        let coordinator = FlightLookupCoordinator(
            draft: original,
            repository: lookupRepository,
            isEditing: true,
            keyStore: TrackingAPIKeyStore(value: "key"),
            client: StubLookupClient(results: [lookupResult])
        )
        await coordinator.query(currentDraft: { latest })
        coordinator.selectCandidate(lookupResult, currentDraft: latest)
        latest.notes = "确认前更新"
        latest.seat = "33C"
        latest.cabinClass = "确认前舱位"

        coordinator.confirmOverwrite(currentDraft: latest)

        guard case .applied = coordinator.state else {
            return XCTFail("身份未变时应确认覆盖")
        }
        XCTAssertEqual(coordinator.draft.notes, "确认前更新")
        XCTAssertEqual(coordinator.draft.seat, "33C")
        XCTAssertEqual(coordinator.draft.cabinClass, "确认前舱位")
    }

    func testRejectsMissingKeyAndFlightsWithoutBothAirports() async {
        await assertLookupError(
            transport: RecordingTransport(responseData: fixture),
            key: " ",
            expected: .missingAPIKey
        )
        let missingAirport = Data("""
        [{"number":"CA123","departure":{},"arrival":{"airport":{"iata":"JFK"}}}]
        """.utf8)
        await assertLookupError(
            transport: RecordingTransport(responseData: missingAirport),
            expected: .missingAirport
        )
    }

    func testAppliesResultUsingRepositoryTimeZonesAndDSTOccurrence() throws {
        let lax = airport("LAX", "America/Los_Angeles")
        let jfk = airport("JFK", "America/New_York")
        let repository = AirportRepository(airports: [lax, jfk])
        var draft = FlightDraft(flightNumber: "old")
        let result = FlightLookupResult(
            flightNumber: "CA123",
            airlineCode: "CA",
            airlineName: "Air China",
            aircraftType: "Boeing 787-9",
            departure: FlightLookupMovement(
                airportIATA: "LAX",
                airportTimeZoneID: "America/Los_Angeles",
                time: FlightLookupTime(
                    absoluteDate: iso("2026-11-01T09:30:00Z"),
                    local: "2026-11-01T01:30:00",
                    source: .runway
                )
            ),
            arrival: FlightLookupMovement(
                airportIATA: "JFK",
                airportTimeZoneID: "America/New_York",
                time: FlightLookupTime(
                    absoluteDate: iso("2026-11-01T18:15:00Z"),
                    local: "2026-11-01T13:15:00",
                    source: .revised
                )
            )
        )

        let report = try FlightLookupDraftApplicator.apply(
            result,
            to: &draft,
            repository: repository
        )

        XCTAssertEqual(draft.departureAirport?.iata, "LAX")
        XCTAssertEqual(draft.arrivalAirport?.iata, "JFK")
        XCTAssertEqual(draft.departureLocalDate, date(2026, 11, 1, 1, 30))
        XCTAssertEqual(draft.departureLocalTimeOccurrence, .second)
        XCTAssertEqual(draft.arrivalLocalDate, date(2026, 11, 1, 13, 15))
        XCTAssertEqual(draft.airlineName, "Air China")
        XCTAssertTrue(report.filledFields.contains("当地起飞时间（实际）"))
    }

    func testApplicatorDoesNotReplaceDraftWhenAirportCannotMap() {
        let repository = AirportRepository(
            airports: [airport("LAX", "America/Los_Angeles")]
        )
        var draft = FlightDraft(flightNumber: "KEEP")
        let original = draft.flightNumber
        let result = FlightLookupResult(
            flightNumber: "CA123",
            airlineCode: nil,
            airlineName: nil,
            aircraftType: nil,
            departure: FlightLookupMovement(airportIATA: "LAX", airportTimeZoneID: nil, time: nil),
            arrival: FlightLookupMovement(airportIATA: "ZZZ", airportTimeZoneID: nil, time: nil)
        )

        XCTAssertThrowsError(
            try FlightLookupDraftApplicator.apply(
                result,
                to: &draft,
                repository: repository
            )
        )
        XCTAssertEqual(draft.flightNumber, original)
    }

    @MainActor
    func testMissingOrBlankResponseNumberPreservesQueriedNumberForNewAndEditedDrafts() async throws {
        let blankNumberResult = FlightLookupResult(
            id: lookupResult.id,
            flightNumber: "  ",
            airlineCode: lookupResult.airlineCode,
            airlineName: lookupResult.airlineName,
            aircraftType: lookupResult.aircraftType,
            departure: lookupResult.departure,
            arrival: lookupResult.arrival
        )
        let missingNumberData = Data("""
        [{
          "departure":{"airport":{"iata":"LAX","timeZone":"America/Los_Angeles"},
            "scheduledTime":{"utc":"2026-11-01 09:30Z","local":"2026-11-01 01:30-08:00"}},
          "arrival":{"airport":{"iata":"JFK","timeZone":"America/New_York"},
            "scheduledTime":{"utc":"2026-11-01 18:15Z","local":"2026-11-01 13:15-05:00"}}
        }]
        """.utf8)
        let missingNumberResults = try await AeroDataBoxClient(
            transport: RecordingTransport(responseData: missingNumberData)
        ).lookup(
            flightNumber: "KEEP123",
            localDate: date(2026, 11, 1),
            apiKey: "key"
        )
        let missingNumberResult = try XCTUnwrap(missingNumberResults.first)

        for result in [blankNumberResult, missingNumberResult] {
            for isEditing in [false, true] {
                let original = populatedDraft()
                let coordinator = FlightLookupCoordinator(
                    draft: original,
                    repository: lookupRepository,
                    isEditing: isEditing,
                    keyStore: TrackingAPIKeyStore(value: "key"),
                    client: StubLookupClient(results: [result])
                )
                await coordinator.query(currentDraft: { original })
                coordinator.selectCandidate(result, currentDraft: original)
                if isEditing {
                    coordinator.confirmOverwrite(currentDraft: original)
                }

                guard case .applied(let report) = coordinator.state else {
                    return XCTFail("缺失或空航班号不应阻止其他可靠字段应用")
                }
                XCTAssertEqual(coordinator.draft.flightNumber, "KEEP123")
                XCTAssertFalse(report.filledFields.contains("航班号"))
            }
        }
    }

    @MainActor
    func testCoordinatorCancellationIgnoresLateResponseAndKeepsIdleState() async {
        let original = populatedDraft()
        let client = SuspendedLookupClient()
        let coordinator = FlightLookupCoordinator(
            draft: original,
            repository: lookupRepository,
            isEditing: false,
            keyStore: TrackingAPIKeyStore(value: "key"),
            client: client
        )
        let task = Task {
            await coordinator.query(currentDraft: { original })
        }
        await client.waitUntilStarted()

        coordinator.cancel()
        task.cancel()
        await client.succeed(with: [lookupResult])
        await task.value

        XCTAssertEqual(coordinator.state, .idle)
        assertDraft(coordinator.draft, equals: original)
    }

    func testClientPropagatesCancellationWithoutLocalizedLookupError() async {
        do {
            _ = try await AeroDataBoxClient(
                transport: RecordingTransport(error: URLError(.cancelled))
            ).lookup(
                flightNumber: "CA123",
                localDate: date(2026, 11, 1),
                apiKey: "key"
            )
            XCTFail("取消请求应抛出 CancellationError")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testAPIKeyStoreProtocolSupportsMemorySubstitute() throws {
        let store: any APIKeyStore = MemoryAPIKeyStore()
        try store.save("secret")
        XCTAssertEqual(try store.load(), "secret")
        try store.delete()
        XCTAssertNil(try store.load())
    }

    private func assertLookupError(
        transport: RecordingTransport,
        key: String = "key",
        expected: AeroDataBoxError,
        expectedMessage: String? = nil
    ) async {
        do {
            _ = try await AeroDataBoxClient(transport: transport).lookup(
                flightNumber: "CA123",
                localDate: date(2026, 11, 1),
                apiKey: key
            )
            XCTFail("应抛出 \(expected)")
        } catch {
            XCTAssertEqual(error as? AeroDataBoxError, expected)
            if let expectedMessage {
                XCTAssertEqual(error.localizedDescription, expectedMessage)
            }
        }
    }

    private var lookupRepository: AirportRepository {
        AirportRepository(
            airports: [
                airport("LAX", "America/Los_Angeles"),
                airport("JFK", "America/New_York"),
            ]
        )
    }

    private var lookupResult: FlightLookupResult {
        FlightLookupResult(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            flightNumber: "CA123",
            airlineCode: "CA",
            airlineName: "Air China",
            aircraftType: "Boeing 787-9",
            departure: FlightLookupMovement(
                airportIATA: "LAX",
                airportTimeZoneID: "America/Los_Angeles",
                time: FlightLookupTime(
                    absoluteDate: iso("2026-11-01T09:30:00Z"),
                    local: "2026-11-01T01:30:00",
                    source: .runway
                )
            ),
            arrival: FlightLookupMovement(
                airportIATA: "JFK",
                airportTimeZoneID: "America/New_York",
                time: FlightLookupTime(
                    absoluteDate: iso("2026-11-01T18:15:00Z"),
                    local: "2026-11-01T13:15:00",
                    source: .revised
                )
            )
        )
    }

    private func populatedDraft() -> FlightDraft {
        FlightDraft(
            flightDate: date(2026, 8, 18),
            flightNumber: "KEEP123",
            airlineCode: "KP",
            airlineName: "Keep Air",
            departureAirport: airport("LAX", "America/Los_Angeles"),
            arrivalAirport: airport("JFK", "America/New_York"),
            departureLocalDate: date(2026, 8, 18, 10, 5),
            arrivalLocalDate: date(2026, 8, 18, 18, 45),
            departureLocalTimeOccurrence: .first,
            arrivalLocalTimeOccurrence: .second,
            aircraftType: "Keep Plane",
            cabinClass: "Keep Cabin",
            seat: "12A",
            notes: "Keep Notes"
        )
    }

    private func assertDraft(
        _ actual: FlightDraft,
        equals expected: FlightDraft,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.flightDate, expected.flightDate, file: file, line: line)
        XCTAssertEqual(actual.flightNumber, expected.flightNumber, file: file, line: line)
        XCTAssertEqual(actual.airlineCode, expected.airlineCode, file: file, line: line)
        XCTAssertEqual(actual.airlineName, expected.airlineName, file: file, line: line)
        assertAirport(
            actual.departureAirport,
            equals: expected.departureAirport,
            file: file,
            line: line
        )
        assertAirport(
            actual.arrivalAirport,
            equals: expected.arrivalAirport,
            file: file,
            line: line
        )
        XCTAssertEqual(actual.departureLocalDate, expected.departureLocalDate, file: file, line: line)
        XCTAssertEqual(actual.arrivalLocalDate, expected.arrivalLocalDate, file: file, line: line)
        XCTAssertEqual(
            actual.departureLocalTimeOccurrence,
            expected.departureLocalTimeOccurrence,
            file: file,
            line: line
        )
        XCTAssertEqual(
            actual.arrivalLocalTimeOccurrence,
            expected.arrivalLocalTimeOccurrence,
            file: file,
            line: line
        )
        XCTAssertEqual(actual.aircraftType, expected.aircraftType, file: file, line: line)
        XCTAssertEqual(actual.cabinClass, expected.cabinClass, file: file, line: line)
        XCTAssertEqual(actual.seat, expected.seat, file: file, line: line)
        XCTAssertEqual(actual.notes, expected.notes, file: file, line: line)
    }

    private func assertAirport(
        _ actual: Airport?,
        equals expected: Airport?,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertEqual(actual?.iata, expected?.iata, file: file, line: line)
        XCTAssertEqual(actual?.icao, expected?.icao, file: file, line: line)
        XCTAssertEqual(actual?.name, expected?.name, file: file, line: line)
        XCTAssertEqual(actual?.city, expected?.city, file: file, line: line)
        XCTAssertEqual(actual?.country, expected?.country, file: file, line: line)
        XCTAssertEqual(actual?.countryCode, expected?.countryCode, file: file, line: line)
        XCTAssertEqual(actual?.latitude, expected?.latitude, file: file, line: line)
        XCTAssertEqual(actual?.longitude, expected?.longitude, file: file, line: line)
        XCTAssertEqual(actual?.timeZoneID, expected?.timeZoneID, file: file, line: line)
    }

    private var fixture: Data {
        Data("""
        [
          {
            "number":"CA123",
            "airline":{"name":"Air China","iata":"CA"},
            "aircraft":{"model":"Boeing 787-9"},
            "departure":{
              "airport":{"iata":"LAX","timeZone":"America/Los_Angeles"},
              "scheduledTime":{"utc":"2026-11-01 08:50Z","local":"2026-11-01 01:50-07:00"},
              "predictedTime":{"utc":"2026-11-01 09:10Z","local":"2026-11-01 01:10-08:00"},
              "revisedTime":{"utc":"2026-11-01 09:20Z","local":"2026-11-01 01:20-08:00"},
              "runwayTime":{"utc":"2026-11-01 09:30Z","local":"2026-11-01 01:30-08:00"}
            },
            "arrival":{
              "airport":{"iata":"JFK","timeZone":"America/New_York"},
              "scheduledTime":{"utc":"2026-11-01 18:00Z","local":"2026-11-01 13:00-05:00"},
              "revisedTime":{"utc":"2026-11-01 18:15Z","local":"2026-11-01 13:15-05:00"}
            }
          },
          {
            "number":"CA123",
            "departure":{"airport":{"iata":"SFO","timeZone":"America/Los_Angeles"},
              "scheduledTime":{"utc":"2026-11-01 12:00Z","local":"2026-11-01 04:00-08:00"}},
            "arrival":{"airport":{"iata":"JFK","timeZone":"America/New_York"},
              "scheduledTime":{"utc":"2026-11-01 20:00Z","local":"2026-11-01 15:00-05:00"}}
          }
        ]
        """.utf8)
    }

    private func airport(_ iata: String, _ timeZone: String) -> Airport {
        Airport(
            iata: iata, icao: "", name: iata, city: iata, country: "US",
            countryCode: "US", latitude: 0, longitude: 0, timeZoneID: timeZone
        )
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(
                year: year, month: month, day: day, hour: hour, minute: minute
            )
        )!
    }

    private func iso(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

private actor RecordingTransport: FlightLookupTransport {
    private(set) var lastRequest: URLRequest?
    let responseData: Data
    let statusCode: Int
    let error: Error?

    init(responseData: Data = Data(), statusCode: Int = 200, error: Error? = nil) {
        self.responseData = responseData
        self.statusCode = statusCode
        self.error = error
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        if let error { throw error }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}

private final class MemoryAPIKeyStore: APIKeyStore, @unchecked Sendable {
    private var value: String?
    func load() throws -> String? { value }
    func save(_ key: String) throws { value = key }
    func delete() throws { value = nil }
}

private final class TrackingAPIKeyStore: APIKeyStore, @unchecked Sendable {
    private let value: String?
    private(set) var loadCount = 0

    init(value: String?) {
        self.value = value
    }

    func load() throws -> String? {
        loadCount += 1
        return value
    }

    func save(_ key: String) throws {}
    func delete() throws {}
}

private final class StubLookupClient: FlightLookupClient, @unchecked Sendable {
    let results: [FlightLookupResult]
    let error: Error?
    private(set) var lastFlightNumber: String?
    private(set) var lastLocalDate: Date?
    private(set) var lastAPIKey: String?

    init(results: [FlightLookupResult] = [], error: Error? = nil) {
        self.results = results
        self.error = error
    }

    func lookup(
        flightNumber: String,
        localDate: Date,
        apiKey: String
    ) async throws -> [FlightLookupResult] {
        lastFlightNumber = flightNumber
        lastLocalDate = localDate
        lastAPIKey = apiKey
        if let error { throw error }
        return results
    }
}

private actor SuspendedLookupClient: FlightLookupClient {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var responseContinuation:
        CheckedContinuation<[FlightLookupResult], Error>?

    func lookup(
        flightNumber: String,
        localDate: Date,
        apiKey: String
    ) async throws -> [FlightLookupResult] {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        return try await withCheckedThrowingContinuation { continuation in
            responseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func succeed(with results: [FlightLookupResult]) {
        responseContinuation?.resume(returning: results)
        responseContinuation = nil
    }
}
