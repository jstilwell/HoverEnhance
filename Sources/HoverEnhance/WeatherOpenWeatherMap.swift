import Foundation

struct OpenWeatherMap: WeatherSource {
    func report(at coordinate: Coordinate, key: String?, timeZone: TimeZone, using http: any WeatherHTTP) async throws(WeatherError) -> WeatherReport {
        throw .unavailable(nil)
    }
}
