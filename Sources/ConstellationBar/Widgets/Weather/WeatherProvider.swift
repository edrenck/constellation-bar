import AppKit

final class WeatherProvider: SystemProviding {
    let kinds: Set<WidgetKind> = [.weather]
    private var cachedWeather = WeatherState.unavailable
    private var weatherCacheKey = ""
    private var lastWeatherRefresh = Date.distantPast
    func sample(config: BarConfig, into state: inout SystemState) { state.weather = sampleWeather(config: config, now: Date()) }
    func sampleWeather(config: BarConfig, now: Date) -> WeatherState {
        let preferences = config.weather
        guard preferences.isConfigured else { return .unavailable }
        let key = "\(preferences.latitude),\(preferences.longitude),\(preferences.unit.rawValue)"
        if key == weatherCacheKey, now.timeIntervalSince(lastWeatherRefresh) < 600 {
            return cachedWeather
        }

        if key != weatherCacheKey { cachedWeather = .unavailable }
        weatherCacheKey = key
        lastWeatherRefresh = now
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(preferences.latitude)),
            URLQueryItem(name: "longitude", value: String(preferences.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"),
            URLQueryItem(name: "temperature_unit", value: preferences.unit.apiValue),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1")
        ]
        guard let url = components?.url else { return cachedWeather }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        let semaphore = DispatchSemaphore(value: 0)
        let response = WeatherResponseBuffer()
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            response.set(data)
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 2.2) == .success, let responseData = response.get() else {
            task.cancel()
            return key == weatherCacheKey ? cachedWeather : .unavailable
        }

        struct Response: Decodable {
            struct Current: Decodable {
                var temperature_2m: Double
                var apparent_temperature: Double
                var relative_humidity_2m: Int
                var wind_speed_10m: Double
                var weather_code: Int
                var is_day: Int
            }
            var current: Current
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: responseData) else {
            return key == weatherCacheKey ? cachedWeather : .unavailable
        }
        cachedWeather = WeatherState(
            temperature: decoded.current.temperature_2m,
            weatherCode: decoded.current.weather_code,
            isDay: decoded.current.is_day == 1,
            apparentTemperature: decoded.current.apparent_temperature,
            humidity: decoded.current.relative_humidity_2m,
            windSpeed: decoded.current.wind_speed_10m
        )
        weatherCacheKey = key
        lastWeatherRefresh = now
        return cachedWeather
    }

}
private final class WeatherResponseBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    func set(_ value: Data?) { lock.lock(); defer { lock.unlock() }; data = value }
    func get() -> Data? { lock.lock(); defer { lock.unlock() }; return data }
}
