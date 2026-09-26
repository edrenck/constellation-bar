import Foundation
import AppKit


struct WeatherState: Equatable {
    var temperature: Double?
    var weatherCode: Int
    var isDay: Bool
    var apparentTemperature: Double? = nil
    var humidity: Int? = nil
    var windSpeed: Double? = nil
    var fetchedAt: Date? = nil
    var age: TimeInterval? = nil
    var isStale = false
    var failure: String? = nil
    var nextAttemptAt: Date? = nil

    var freshnessDescription: String {
        if let age {
            let minutes = Int(age / 60)
            if temperature == nil { return "Forecast expired · last received \(minutes) minutes ago." }
            if isStale { return "Saved forecast · \(minutes) minutes old." }
            return "Forecast received \(minutes) minutes ago."
        }
        return "No forecast has been received."
    }
    var statusDescription: String {
        let problem = failure.map { " \($0) Automatic retry is scheduled." } ?? ""
        return freshnessDescription + problem
    }

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
