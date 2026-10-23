import Foundation
import SwiftData
import XCTest
@testable import FlightLog

final class FlightDataTests: XCTestCase {
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

    func testFlightRecordNormalizesFlightAndAirlineCodes() {
        let record = makeRecord(flightNumber: " ca- 123 ", airlineCode: " ca ")

        XCTAssertEqual(record.flightNumber, "CA123")
        XCTAssertEqual(record.airlineCode, "CA")
    }

    func testFlightRecordCopiesAirportSnapshots() {
        let record = makeRecord()

        XCTAssertEqual(record.departureAirportIATA, "PEK")
        XCTAssertEqual(record.departureAirportName, beijing.name)
        XCTAssertEqual(record.departureCity, "Beijing")
        XCTAssertEqual(record.departureCountry, "China")
        XCTAssertEqual(record.departureLatitude, 40.0801)
        XCTAssertEqual(record.departureLongitude, 116.5846)
        XCTAssertEqual(record.departureTimeZoneID, "Asia/Shanghai")
        XCTAssertEqual(record.arrivalAirportIATA, "YUL")
        XCTAssertEqual(record.arrivalTimeZoneID, "America/Toronto")
    }

    @MainActor
    func testFlightRecordPersistsInMemoryWithSwiftData() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: FlightRecord.self,
            configurations: configuration
        )
        let context = container.mainContext
        context.insert(makeRecord(flightNumber: "ac301", airlineCode: "ac"))
        try context.save()

        let records = try context.fetch(FetchDescriptor<FlightRecord>())

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.flightNumber, "AC301")
        XCTAssertEqual(records.first?.departureAirportIATA, "PEK")
        XCTAssertEqual(records.first?.arrivalAirportIATA, "YUL")
    }

    func testAirportSearchRanksExactIATAFirstAndHonorsLimit() {
        let repository = AirportRepository(airports: [
            beijing,
            montreal,
            Airport(
                iata: "PEQ",
                icao: "KPEQ",
                name: "Pecos Municipal Airport",
                city: "Peking",
                country: "United States",
                countryCode: "US",
                latitude: 31.3824,
                longitude: -103.5107,
                timeZoneID: "America/Chicago"
            ),
        ])

        let matches = repository.search("pek", limit: 2)

        XCTAssertEqual(matches.map(\.iata), ["PEK", "PEQ"])
    }

    func testAirportSearchIsCaseAndDiacriticInsensitiveAcrossTextFields() {
        let repository = AirportRepository(airports: [beijing, montreal])

        XCTAssertEqual(repository.search("MONTREAL").map(\.iata), ["YUL"])
        XCTAssertEqual(repository.search("trudeau").map(\.iata), ["YUL"])
        XCTAssertEqual(repository.search("canada").map(\.iata), ["YUL"])
        XCTAssertEqual(repository.search("cyul").map(\.iata), ["YUL"])
    }

    func testAirportDecodingDefaultsMissingAliasesToEmptyArray() throws {
        let json = """
        {
          "iata": "PEK",
          "icao": "ZBAA",
          "name": "Beijing Capital International Airport",
          "city": "Beijing",
          "country": "China",
          "countryCode": "CN",
          "latitude": 40.0801,
          "longitude": 116.5846,
          "timeZoneID": "Asia/Shanghai"
        }
        """

        let airport = try JSONDecoder().decode(
            Airport.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(airport.aliases, [])
    }

    func testAirportSearchRanksAliasExactThenPrefixBeforeEnglishContains() {
        let repository = AirportRepository(airports: [
            Airport(
                iata: "ZZZ",
                icao: "KZZZ",
                name: "Airport Serving 北京",
                city: "Example",
                country: "United States",
                countryCode: "US",
                latitude: 0,
                longitude: 0,
                timeZoneID: "Etc/UTC"
            ),
            Airport(
                iata: "PKX",
                icao: "ZBAD",
                name: "Beijing Daxing International Airport",
                city: "Beijing",
                country: "China",
                countryCode: "CN",
                latitude: 39.5098,
                longitude: 116.4105,
                timeZoneID: "Asia/Shanghai",
                aliases: ["北京市", "北京大兴国际机场"]
            ),
            Airport(
                iata: "PEK",
                icao: "ZBAA",
                name: "Beijing Capital International Airport",
                city: "Beijing",
                country: "China",
                countryCode: "CN",
                latitude: 40.0801,
                longitude: 116.5846,
                timeZoneID: "Asia/Shanghai",
                aliases: ["北京", "首都机场", "北京"]
            ),
        ])

        XCTAssertEqual(
            repository.search("北京").map(\.iata),
            ["PEK", "PKX", "ZZZ"]
        )
        XCTAssertEqual(repository.search("首都").map(\.iata), ["PEK"])
    }

    func testBundledChineseAirportAliasesFindRequiredAirports() throws {
        let repository = try AirportRepository()
        let expectations: [(String, String)] = [
            ("北京", "PEK"),
            ("首都", "PEK"),
            ("大兴", "PKX"),
            ("上海", "PVG"),
            ("浦东", "PVG"),
            ("虹桥", "SHA"),
            ("广州", "CAN"),
            ("白云", "CAN"),
            ("深圳", "SZX"),
            ("宝安", "SZX"),
            ("成都", "TFU"),
            ("天府", "TFU"),
            ("香港", "HKG"),
            ("台北", "TPE"),
            ("桃园", "TPE"),
            ("东京", "HND"),
            ("羽田", "HND"),
            ("伦敦", "LHR"),
            ("希思罗", "LHR"),
            ("纽约", "JFK"),
            ("肯尼迪", "JFK"),
        ]

        for (query, expectedIATA) in expectations {
            XCTAssertEqual(
                repository.search(query).first?.iata,
                expectedIATA,
                "Expected \(query) to find \(expectedIATA)"
            )
        }
    }

    func testResourceSmokeReportRecordsAliasCountAndChineseQueries() {
        let airports = [
            Airport(
                iata: "PEK", icao: "ZBAA", name: "Capital", city: "Beijing",
                country: "China", countryCode: "CN", latitude: 0, longitude: 0,
                timeZoneID: "Asia/Shanghai", aliases: ["北京"]
            ),
            Airport(
                iata: "PKX", icao: "ZBAD", name: "Daxing", city: "Beijing",
                country: "China", countryCode: "CN", latitude: 0, longitude: 0,
                timeZoneID: "Asia/Shanghai", aliases: ["北京大兴"]
            ),
            Airport(
                iata: "PVG", icao: "ZSPD", name: "Pudong", city: "Shanghai",
                country: "China", countryCode: "CN", latitude: 0, longitude: 0,
                timeZoneID: "Asia/Shanghai", aliases: ["浦东"]
            ),
            Airport(
                iata: "HND", icao: "RJTT", name: "Haneda", city: "Tokyo",
                country: "Japan", countryCode: "JP", latitude: 0, longitude: 0,
                timeZoneID: "Asia/Tokyo", aliases: ["羽田"]
            ),
            Airport(
                iata: "LHR", icao: "EGLL", name: "Heathrow", city: "London",
                country: "United Kingdom", countryCode: "GB",
                latitude: 0, longitude: 0, timeZoneID: "Europe/London",
                aliases: ["希思罗"]
            ),
            Airport(
                iata: "JFK", icao: "KJFK", name: "Kennedy", city: "New York",
                country: "United States", countryCode: "US",
                latitude: 0, longitude: 0, timeZoneID: "America/New_York",
                aliases: ["肯尼迪"]
            ),
        ]
        let repository = AirportRepository(airports: airports)

        XCTAssertEqual(repository.airports.count, 6)
        XCTAssertEqual(repository.airports.filter { !$0.aliases.isEmpty }.count, 6)
        XCTAssertEqual(
            repository.search("北京", limit: 20)
                .map(\.iata)
                .filter { ["PEK", "PKX"].contains($0) },
            ["PEK", "PKX"]
        )
        XCTAssertEqual(repository.search("浦东", limit: 1).map(\.iata), ["PVG"])
        XCTAssertEqual(repository.search("羽田", limit: 1).map(\.iata), ["HND"])
        XCTAssertEqual(repository.search("希思罗", limit: 1).map(\.iata), ["LHR"])
        XCTAssertEqual(repository.search("肯尼迪", limit: 1).map(\.iata), ["JFK"])
    }

    func testBundledResourcesPassFinalExternalValidationContract() throws {
        let repository = try AirportRepository()

        XCTAssertGreaterThanOrEqual(repository.airports.count, 9_000)
        XCTAssertGreaterThan(
            repository.airports.filter { !$0.aliases.isEmpty }.count,
            0
        )
        XCTAssertEqual(
            repository.search("北京", limit: 20)
                .map(\.iata)
                .filter { ["PEK", "PKX"].contains($0) },
            ["PEK", "PKX"]
        )
        XCTAssertEqual(repository.search("浦东", limit: 1).map(\.iata), ["PVG"])
        XCTAssertEqual(repository.search("羽田", limit: 1).map(\.iata), ["HND"])
        XCTAssertEqual(repository.search("希思罗", limit: 1).map(\.iata), ["LHR"])
        XCTAssertEqual(repository.search("肯尼迪", limit: 1).map(\.iata), ["JFK"])
    }

    func testBundledAirportResourceLoadsGlobalData() throws {
        let repository = try AirportRepository()

        XCTAssertGreaterThanOrEqual(repository.airports.count, 9_000)
        XCTAssertEqual(repository.search("JFK", limit: 1).first?.iata, "JFK")
        XCTAssertEqual(repository.search("HND", limit: 1).first?.timeZoneID, "Asia/Tokyo")
    }

    private func makeRecord(
        flightNumber: String = "CA123",
        airlineCode: String = "CA"
    ) -> FlightRecord {
        FlightRecord(
            flightNumber: flightNumber,
            airlineCode: airlineCode,
            airlineName: "Air China",
            flightDate: Date(timeIntervalSince1970: 1_787_011_200),
            departureAirport: beijing,
            arrivalAirport: montreal,
            departureDate: Date(timeIntervalSince1970: 1_787_040_000),
            arrivalDate: Date(timeIntervalSince1970: 1_787_076_000),
            aircraftType: "Boeing 787-9",
            cabinClass: "Business",
            seat: "3A",
            notes: "Test record",
            ownerProfileID: UserProfileDefaults.id
        )
    }
}
