import XCTest
@testable import ConstellationBar

final class WeatherProviderTests: XCTestCase {
    private final class Transport: WeatherTransporting {
        var calls = 0
        var response = WeatherTransportResponse(error: "Timed out")
        var requests: [URLRequest] = []
        func fetch(_ request: URLRequest) -> WeatherTransportResponse { calls += 1; requests.append(request); return response }
        func succeed() { response = .init(data: Data(#"{"current":{"temperature_2m":21,"apparent_temperature":20,"relative_humidity_2m":50,"wind_speed_10m":4,"weather_code":0,"is_day":1}}"#.utf8), status: 200) }
    }
    private var config: BarConfig {
        var config = BarConfig.default
        config.weather.locationLabel = "Phoenix"
        config.weather.latitude = 33; config.weather.longitude = -112
        return config
    }
    func testTimeoutRetriesSoonAndRecoveryResetsFreshness() {
        let transport = Transport(); var time = Date(timeIntervalSince1970: 1000)
        let provider = WeatherProvider(transport: transport, now: { time })
        var state = SystemState(); provider.sample(config: config, into: &state)
        XCTAssertNil(state.weather.temperature); XCTAssertEqual(state.weather.failure, "Timed out")
        time.addTimeInterval(29); provider.sample(config: config, into: &state); XCTAssertEqual(transport.calls, 1)
        transport.succeed(); time.addTimeInterval(1); provider.sample(config: config, into: &state)
        XCTAssertEqual(transport.calls, 2); XCTAssertEqual(state.weather.temperature, 21)
        XCTAssertNil(state.weather.failure); XCTAssertEqual(state.weather.fetchedAt, time)
        time.addTimeInterval(599); provider.sample(config: config, into: &state); XCTAssertEqual(transport.calls, 2)
        time.addTimeInterval(1); provider.sample(config: config, into: &state); XCTAssertEqual(transport.calls, 3)
    }
    func testOutageKeepsTruthfulStaleReadingThenExpires() {
        let transport = Transport(); transport.succeed()
        let provider = WeatherProvider(transport: transport)
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(provider.sampleWeather(config: config, now: start).temperature, 21)
        transport.response = .init(status: 503)
        let stale = provider.sampleWeather(config: config, now: start.addingTimeInterval(600))
        XCTAssertEqual(stale.temperature, 21); XCTAssertTrue(stale.isStale); XCTAssertEqual(stale.age, 600)
        XCTAssertTrue(stale.statusDescription.contains("HTTP 503"))
        XCTAssertEqual(stale.nextAttemptAt, start.addingTimeInterval(630))
        let expired = provider.sampleWeather(config: config, now: start.addingTimeInterval(3600))
        XCTAssertNil(expired.temperature); XCTAssertEqual(expired.fetchedAt, start)
        XCTAssertTrue(expired.statusDescription.contains("expired"))
    }
    func testFailureBackoffIsBoundedAndLocationChangesDropOldForecast() {
        let transport = Transport(); let provider = WeatherProvider(transport: transport)
        var time = Date(timeIntervalSince1970: 1000)
        for delay in [30.0, 60, 120, 240, 300, 300] {
            let state = provider.sampleWeather(config: config, now: time)
            XCTAssertEqual(state.nextAttemptAt, time.addingTimeInterval(delay)); time.addTimeInterval(delay)
        }
        transport.succeed(); XCTAssertEqual(provider.sampleWeather(config: config, now: time).temperature, 21)
        var changed = config; changed.weather.latitude = 40
        transport.response = .init(error: "Offline")
        let state = provider.sampleWeather(config: changed, now: time)
        XCTAssertNil(state.temperature); XCTAssertNil(state.fetchedAt)
        XCTAssertTrue(transport.requests.last!.url!.query!.contains("latitude=40"))
    }
    func testHTTPAndMalformedOrInvalidReadingsNeverBecomeSuccessfulCache() {
        let transport = Transport(); let provider = WeatherProvider(transport: transport)
        let responses: [WeatherTransportResponse] = [
            .init(data: Data("{}".utf8), status: 500), .init(data: Data("broken".utf8), status: 200),
            .init(data: Data(#"{"current":{"temperature_2m":21,"apparent_temperature":20,"relative_humidity_2m":150,"wind_speed_10m":4,"weather_code":0,"is_day":1}}"#.utf8), status: 200)
        ]
        for (index, response) in responses.enumerated() {
            transport.response = response
            let state = provider.sampleWeather(config: config, now: Date(timeIntervalSince1970: Double(index * 1000)))
            XCTAssertNil(state.temperature); XCTAssertNil(state.fetchedAt); XCTAssertNotNil(state.failure)
        }
    }
}
