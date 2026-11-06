import Foundation

/// Raw form text stays separate from validated configuration until the edit can be saved.
struct WeatherSettingsInput {
    var locationLabel: String
    var latitude: String
    var longitude: String

    func applying(to preferences: WeatherPreferences) throws -> WeatherPreferences {
        var value = preferences
        value.latitude = try coordinate(latitude, name: "Latitude", range: -90...90)
        value.longitude = try coordinate(longitude, name: "Longitude", range: -180...180)
        value.locationLabel = locationLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }

    private func coordinate(_ text: String, name: String, range: ClosedRange<Double>) throws -> Double {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite, range.contains(value) else {
            throw ConfigurationError.invalid("\(name) must be a number from \(Int(range.lowerBound)) to \(Int(range.upperBound)).")
        }
        return value
    }
}
