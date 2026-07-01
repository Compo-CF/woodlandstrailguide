import Foundation
import Observation

/// Fetches current weather conditions from Open-Meteo (free, no API key,
/// unlimited use for a hobby-scale app). Temp, wind, and condition code
/// are the hiker/biker-relevant fields — rain and Texas heat shape a walk
/// more than they shape most other things.
enum WeatherService {
    struct Snapshot: Hashable {
        let temperatureF: Double
        let weatherCode: Int
        let windMph: Double
        let windDirectionDegrees: Int
    }

    enum WeatherError: Error { case badResponse, decodeFailed }

    static func fetch(latitude: Double, longitude: Double) async throws -> Snapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,wind_speed_10m,wind_direction_10m"),
            .init(name: "temperature_unit", value: "fahrenheit"),
            .init(name: "wind_speed_unit", value: "mph"),
            .init(name: "timezone", value: "auto"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadRevalidatingCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WeatherError.badResponse
        }
        struct Response: Decodable {
            struct Current: Decodable {
                let temperature_2m: Double
                let weather_code: Int
                let wind_speed_10m: Double
                let wind_direction_10m: Int
            }
            let current: Current
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw WeatherError.decodeFailed
        }
        return Snapshot(
            temperatureF: decoded.current.temperature_2m,
            weatherCode: decoded.current.weather_code,
            windMph: decoded.current.wind_speed_10m,
            windDirectionDegrees: decoded.current.wind_direction_10m
        )
    }
}

extension WeatherService.Snapshot {
    /// Open-Meteo WMO weather code → short human label.
    var conditionLabel: String {
        switch weatherCode {
        case 0: "Clear"
        case 1: "Mainly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55: "Drizzle"
        case 56, 57: "Freezing drizzle"
        case 61, 63, 65: "Rain"
        case 66, 67: "Freezing rain"
        case 71, 73, 75, 77: "Snow"
        case 80, 81, 82: "Showers"
        case 85, 86: "Snow showers"
        case 95: "Thunderstorm"
        case 96, 99: "Thunderstorm with hail"
        default: "—"
        }
    }

    var conditionSymbol: String {
        switch weatherCode {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 80, 81, 82: "cloud.drizzle.fill"
        case 56, 57, 66, 67: "cloud.sleet.fill"
        case 61, 63, 65: "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    var windCardinal: String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((Double(windDirectionDegrees) + 22.5) / 45.0) % 8
        return dirs[index]
    }

    var summary: String {
        let temp = Int(temperatureF.rounded())
        let wind = Int(windMph.rounded())
        return "\(temp)°F · \(conditionLabel) · Wind \(wind) mph \(windCardinal)"
    }

    /// Recommend caution when hiking conditions are meaningfully off — hot
    /// Texas afternoons, active precipitation, thunder. Nil if it's fine.
    var walkingAdvisory: String? {
        if [95, 96, 99].contains(weatherCode) { return "Thunderstorm — head indoors" }
        if (61...67).contains(weatherCode) || (80...82).contains(weatherCode) { return "Rain — pathways may be slippery" }
        if temperatureF >= 100 { return "Extreme heat — bring water" }
        if temperatureF >= 90 { return "Hot — bring water" }
        return nil
    }
}

/// Wraps WeatherService with debounced refresh + cached snapshot. Refreshes
/// no more than once per 15 minutes unless callers pass `force: true`
/// (e.g. after moving to a new area).
@Observable
final class WeatherStore {
    var snapshot: WeatherService.Snapshot?
    var lastFetch: Date?
    var lastFetchLocation: (lat: Double, lon: Double)?
    var isFetching = false

    private static let refreshIntervalSeconds: TimeInterval = 15 * 60

    /// The Woodlands centroid — fallback when we don't have user location.
    private static let fallbackLat = 30.1658
    private static let fallbackLon = -95.4613

    @MainActor
    func refresh(latitude: Double? = nil, longitude: Double? = nil, force: Bool = false) async {
        let lat = latitude ?? Self.fallbackLat
        let lon = longitude ?? Self.fallbackLon
        if !force,
           let last = lastFetch,
           Date.now.timeIntervalSince(last) < Self.refreshIntervalSeconds,
           let prev = lastFetchLocation,
           abs(prev.lat - lat) < 0.02 && abs(prev.lon - lon) < 0.02 {
            return
        }
        isFetching = true
        defer { isFetching = false }
        do {
            let snap = try await WeatherService.fetch(latitude: lat, longitude: lon)
            snapshot = snap
            lastFetch = .now
            lastFetchLocation = (lat, lon)
        } catch {
            // Keep the previous snapshot on failure; silently swallow.
        }
    }
}
