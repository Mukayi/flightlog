import Foundation

protocol FlightLookupTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

protocol FlightLookupClient: Sendable {
    func lookup(
        flightNumber: String,
        localDate: Date,
        apiKey: String
    ) async throws -> [FlightLookupResult]
}

struct URLSessionFlightLookupTransport: FlightLookupTransport {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AeroDataBoxError.invalidResponse
        }
        return (data, response)
    }
}

enum FlightLookupTimeSource: String, Sendable, Equatable {
    case runway
    case revised
    case predicted
    case scheduled

    var title: String {
        switch self {
        case .runway: "实际"
        case .revised: "修订"
        case .predicted: "预计"
        case .scheduled: "计划"
        }
    }
}

struct FlightLookupTime: Sendable, Equatable {
    let absoluteDate: Date
    let local: String
    let source: FlightLookupTimeSource
}

struct FlightLookupMovement: Sendable, Equatable {
    let airportIATA: String
    let airportTimeZoneID: String?
    let time: FlightLookupTime?
}

struct FlightLookupResult: Sendable, Equatable, Identifiable {
    let id: UUID
    let flightNumber: String
    let airlineCode: String?
    let airlineName: String?
    let aircraftType: String?
    let departure: FlightLookupMovement
    let arrival: FlightLookupMovement

    init(
        id: UUID = UUID(),
        flightNumber: String,
        airlineCode: String?,
        airlineName: String?,
        aircraftType: String?,
        departure: FlightLookupMovement,
        arrival: FlightLookupMovement
    ) {
        self.id = id
        self.flightNumber = flightNumber
        self.airlineCode = airlineCode
        self.airlineName = airlineName
        self.aircraftType = aircraftType
        self.departure = departure
        self.arrival = arrival
    }
}

enum AeroDataBoxError: LocalizedError, Equatable {
    case missingAPIKey
    case noResults
    case missingAirport
    case unauthorized
    case rateLimited
    case serverUnavailable
    case decodingFailed
    case offline
    case timedOut
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "尚未保存 RapidAPI API key，请先在设置中配置。"
        case .noResults:
            "没有找到该当地起飞日期对应的航班。"
        case .missingAirport:
            "查询结果缺少出发或到达机场，无法安全填充。"
        case .unauthorized:
            "API key 无效或无权访问此接口（401/403）。"
        case .rateLimited:
            "RapidAPI 配额已用尽或请求过于频繁（429），请稍后重试。"
        case .serverUnavailable:
            "AeroDataBox 服务暂时不可用（5xx），请稍后重试。"
        case .decodingFailed:
            "AeroDataBox 返回了无法识别的数据。"
        case .offline:
            "当前网络不可用，请检查连接后重试。"
        case .timedOut:
            "联网查询超时（15 秒），请稍后重试。"
        case .invalidResponse:
            "联网查询收到无效响应。"
        }
    }
}

struct AeroDataBoxClient: FlightLookupClient, Sendable {
    static let host = "aerodatabox.p.rapidapi.com"
    let transport: any FlightLookupTransport

    init(transport: any FlightLookupTransport = URLSessionFlightLookupTransport()) {
        self.transport = transport
    }

    func lookup(
        flightNumber: String,
        localDate: Date,
        apiKey: String
    ) async throws -> [FlightLookupResult] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw AeroDataBoxError.missingAPIKey }
        let request = try makeRequest(
            flightNumber: flightNumber,
            localDate: localDate,
            apiKey: key
        )

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw CancellationError()
            case .timedOut:
                throw AeroDataBoxError.timedOut
            case .notConnectedToInternet, .networkConnectionLost,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                throw AeroDataBoxError.offline
            default:
                throw AeroDataBoxError.invalidResponse
            }
        }

        switch response.statusCode {
        case 204:
            throw AeroDataBoxError.noResults
        case 200..<300:
            break
        case 401, 403:
            throw AeroDataBoxError.unauthorized
        case 404:
            throw AeroDataBoxError.noResults
        case 429:
            throw AeroDataBoxError.rateLimited
        case 500..<600:
            throw AeroDataBoxError.serverUnavailable
        default:
            throw AeroDataBoxError.invalidResponse
        }

        let contracts: [FlightContract]
        do {
            contracts = try JSONDecoder().decode([FlightContract].self, from: data)
        } catch {
            throw AeroDataBoxError.decodingFailed
        }
        guard !contracts.isEmpty else { throw AeroDataBoxError.noResults }
        let results = contracts.compactMap(Self.result(from:))
        guard !results.isEmpty else { throw AeroDataBoxError.missingAirport }
        return results
    }

    func makeRequest(
        flightNumber: String,
        localDate: Date,
        apiKey: String
    ) throws -> URLRequest {
        let allowed = CharacterSet.alphanumerics
        guard
            let encodedNumber = flightNumber.addingPercentEncoding(
                withAllowedCharacters: allowed
            )
        else {
            throw AeroDataBoxError.invalidResponse
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        components.percentEncodedPath =
            "/flights/number/\(encodedNumber)/\(Self.dateString(localDate))"
        components.queryItems = [
            URLQueryItem(name: "withAircraftImage", value: "false"),
            URLQueryItem(name: "withLocation", value: "false"),
            URLQueryItem(name: "withFlightPlan", value: "false"),
            URLQueryItem(name: "dateLocalRole", value: "Departure"),
        ]
        guard let url = components.url else {
            throw AeroDataBoxError.invalidResponse
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue(Self.host, forHTTPHeaderField: "x-rapidapi-host")
        request.setValue(apiKey, forHTTPHeaderField: "x-rapidapi-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func result(from contract: FlightContract) -> FlightLookupResult? {
        guard
            let departure = movement(from: contract.departure),
            let arrival = movement(from: contract.arrival)
        else {
            return nil
        }
        return FlightLookupResult(
            flightNumber: contract.number ?? "",
            airlineCode: contract.airline?.iata,
            airlineName: contract.airline?.name,
            aircraftType: contract.aircraft?.model,
            departure: departure,
            arrival: arrival
        )
    }

    private static func movement(
        from contract: FlightAirportMovementContract?
    ) -> FlightLookupMovement? {
        guard
            let iata = contract?.airport?.iata?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !iata.isEmpty
        else {
            return nil
        }
        let candidates: [(FlightLookupTimeSource, DateTimeContract?)] = [
            (.runway, contract?.runwayTime),
            (.revised, contract?.revisedTime),
            (.predicted, contract?.predictedTime),
            (.scheduled, contract?.scheduledTime),
        ]
        let selected = candidates.lazy.compactMap { source, value in
            lookupTime(value, source: source)
        }.first
        return FlightLookupMovement(
            airportIATA: FlightRecordNormalization.code(iata),
            airportTimeZoneID: contract?.airport?.timeZone,
            time: selected
        )
    }

    private static func lookupTime(
        _ contract: DateTimeContract?,
        source: FlightLookupTimeSource
    ) -> FlightLookupTime? {
        guard
            let utc = contract?.utc,
            let absoluteDate = parseISO8601(utc)
        else {
            return nil
        }
        let local = normalizedLocal(contract?.local)
            ?? normalizedLocal(utc)
            ?? LocalWallClockResolver.stableString(from: absoluteDate)
        return FlightLookupTime(
            absoluteDate: absoluteDate,
            local: local,
            source: source
        )
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let normalized = value.replacingOccurrences(of: " ", with: "T")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: normalized)
            ?? ISO8601DateFormatter().date(from: normalized)
        {
            return date
        }
        for format in [
            "yyyy-MM-dd'T'HH:mmXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        ] {
            let fallback = DateFormatter()
            fallback.calendar = Calendar(identifier: .gregorian)
            fallback.locale = Locale(identifier: "en_US_POSIX")
            fallback.timeZone = TimeZone(secondsFromGMT: 0)
            fallback.dateFormat = format
            fallback.isLenient = false
            if let date = fallback.date(from: normalized) {
                return date
            }
        }
        return nil
    }

    private static func normalizedLocal(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.replacingOccurrences(of: " ", with: "T")
        guard normalized.count >= 16 else { return nil }
        let minute = String(normalized.prefix(16))
        if normalized.count >= 19,
           normalized[normalized.index(normalized.startIndex, offsetBy: 16)] == ":"
        {
            return String(normalized.prefix(19))
        }
        return minute + ":00"
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

enum FlightLookupPresentation {
    static func localTime(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: " ", with: "T")
        let hasSeconds = normalized.count >= 19
            && normalized[
                normalized.index(normalized.startIndex, offsetBy: 16)
            ] == ":"
        let localValue = String(normalized.prefix(hasSeconds ? 19 : 16))
        let formats = hasSeconds
            ? ["yyyy-MM-dd'T'HH:mm:ss"]
            : ["yyyy-MM-dd'T'HH:mm"]
        for format in formats {
            let parser = DateFormatter()
            parser.calendar = Calendar(identifier: .gregorian)
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = TimeZone(secondsFromGMT: 0)
            parser.dateFormat = format
            parser.isLenient = false
            guard let date = parser.date(from: localValue) else { continue }

            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            return formatter.string(from: date)
        }
        return value
    }
}

private struct FlightContract: Decodable {
    let number: String?
    let airline: AirlineContract?
    let aircraft: AircraftContract?
    let departure: FlightAirportMovementContract?
    let arrival: FlightAirportMovementContract?
}

private struct AirlineContract: Decodable {
    let name: String?
    let iata: String?
}

private struct AircraftContract: Decodable {
    let model: String?
}

private struct FlightAirportMovementContract: Decodable {
    let airport: ListingAirportContract?
    let scheduledTime: DateTimeContract?
    let revisedTime: DateTimeContract?
    let predictedTime: DateTimeContract?
    let runwayTime: DateTimeContract?
}

private struct ListingAirportContract: Decodable {
    let iata: String?
    let timeZone: String?
}

private struct DateTimeContract: Decodable {
    let utc: String?
    let local: String?
}
