import Foundation
import AppKit


struct WeatherState: Equatable {
    var temperature: Double?
    var weatherCode: Int
    var isDay: Bool
    var apparentTemperature: Double? = nil
    var humidity: Int? = nil
    var windSpeed: Double? = nil

    static let unavailable = WeatherState(temperature: nil, weatherCode: -1, isDay: true)

    var symbolName: String {
        switch weatherCode {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}
