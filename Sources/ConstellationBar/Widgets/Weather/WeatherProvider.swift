import Foundation

struct WeatherTransportResponse {
    var data: Data? = nil
    var status: Int? = nil
    var error: String? = nil
}
protocol WeatherTransporting {
    func fetch(_ request: URLRequest) -> WeatherTransportResponse
}

/// The synchronous boundary is bounded; ownership stays on the weather provider queue.
struct URLSessionWeatherTransport: WeatherTransporting {
    func fetch(_ request: URLRequest) -> WeatherTransportResponse {
        let ready = DispatchSemaphore(value: 0)
        let buffer = WeatherResponseBuffer()
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            buffer.set(WeatherTransportResponse(data: data, status: (response as? HTTPURLResponse)?.statusCode,
                                                error: error?.localizedDescription))
            ready.signal()
        }
        task.resume()
        guard ready.wait(timeout: .now() + 2.2) == .success else {
            task.cancel(); return WeatherTransportResponse(error: "Weather request timed out.")
        }
        return buffer.get()
    }
}

final class WeatherProvider: SystemProviding {
    let kinds: Set<WidgetKind> = [.weather]
    static let refreshInterval: TimeInterval = 600
    static let maximumAge: TimeInterval = 3600
    private var cachedWeather = WeatherState.unavailable
    private var weatherCacheKey = ""
    private var lastSuccess: Date?
    private var nextAttempt = Date.distantPast
    private var failures = 0
    private var failure: String?
    private let transport: WeatherTransporting
    private let clock: () -> Date
    init(transport: WeatherTransporting = URLSessionWeatherTransport(), now: @escaping () -> Date = Date.init) {
        self.transport = transport; clock = now
    }
    func sample(config: BarConfig, into state: inout SystemState) { state.weather = sampleWeather(config: config, now: clock()) }
    func sampleWeather(config: BarConfig, now: Date) -> WeatherState {
        let preferences = config.weather
        guard preferences.isConfigured else {
            weatherCacheKey = ""; cachedWeather = .unavailable; lastSuccess = nil; failures = 0; failure = nil; nextAttempt = .distantPast
            return .unavailable
        }
        let key = "\(preferences.latitude),\(preferences.longitude),\(preferences.unit.rawValue)"
        if key != weatherCacheKey {
            cachedWeather = .unavailable; lastSuccess = nil; failures = 0; failure = nil; nextAttempt = .distantPast
            weatherCacheKey = key
        }
        if now >= nextAttempt {
            var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            components.queryItems = [
                URLQueryItem(name: "latitude", value: String(preferences.latitude)),
                URLQueryItem(name: "longitude", value: String(preferences.longitude)),
                URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"),
                URLQueryItem(name: "temperature_unit", value: preferences.unit.apiValue),
                URLQueryItem(name: "timezone", value: "auto"), URLQueryItem(name: "forecast_days", value: "1")
            ]
            var request = URLRequest(url: components.url!)
            request.timeoutInterval = 2
            let response = transport.fetch(request)
            if let error = response.error { recordFailure(error, at: now) }
            else if response.status != 200 { recordFailure("Weather service returned HTTP \(response.status.map(String.init) ?? "unknown").", at: now) }
            else if let data = response.data, data.count <= 262_144,
                    let decoded = try? JSONDecoder().decode(Response.self, from: data), decoded.current.valid {
                let current = decoded.current
                cachedWeather = WeatherState(temperature: current.temperature_2m, weatherCode: current.weather_code,
                    isDay: current.is_day == 1, apparentTemperature: current.apparent_temperature,
                    humidity: current.relative_humidity_2m, windSpeed: current.wind_speed_10m)
                lastSuccess = now; failures = 0; failure = nil; nextAttempt = now.addingTimeInterval(Self.refreshInterval)
            } else { recordFailure("Weather service returned an invalid forecast.", at: now) }
        }
        var result = cachedWeather
        if let lastSuccess, now.timeIntervalSince(lastSuccess) >= Self.maximumAge { result = .unavailable }
        result.fetchedAt = lastSuccess
        result.isStale = lastSuccess.map { now.timeIntervalSince($0) >= Self.refreshInterval } ?? false
        result.age = lastSuccess.map { max(0, now.timeIntervalSince($0)) }
        result.failure = failure
        result.nextAttemptAt = nextAttempt
        return result
    }
    private func recordFailure(_ message: String, at now: Date) {
        failures += 1; failure = message
        // Retry in 30 seconds, then 1, 2, 4, 5 minutes. Success resets the cadence.
        nextAttempt = now.addingTimeInterval(min(300, 30 * pow(2, Double(min(failures - 1, 4)))))
    }
    private struct Response: Decodable {
        struct Current: Decodable {
            var temperature_2m: Double
            var apparent_temperature: Double
            var relative_humidity_2m: Int
            var wind_speed_10m: Double
            var weather_code: Int
            var is_day: Int
            var valid: Bool {
                (-150...180).contains(temperature_2m) && (-200...200).contains(apparent_temperature) && (0...500).contains(wind_speed_10m) &&
                (0...100).contains(relative_humidity_2m) && [0, 1].contains(is_day) && (0...99).contains(weather_code)
            }
        }
        var current: Current
    }
}
private final class WeatherResponseBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var response = WeatherTransportResponse(error: "No weather response.")
    func set(_ value: WeatherTransportResponse) { lock.lock(); defer { lock.unlock() }; response = value }
    func get() -> WeatherTransportResponse { lock.lock(); defer { lock.unlock() }; return response }
}
