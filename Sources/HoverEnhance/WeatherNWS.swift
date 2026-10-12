import Foundation

/// Watches and warnings from the US National Weather Service, for places in the US when the chosen
/// provider has no alerts of its own. Free, with no key; it asks only for a User-Agent saying who's asking.
enum NWSAlerts {
    /// The US and the territories the NWS forecasts for, by the country Apple's maps put the place in.
    /// A place whose country isn't known isn't sent to it at all.
    static func covers(_ place: WeatherPlace) -> Bool {
        guard let country = place.countryCode?.uppercased() else { return false }
        return ["US", "PR", "VI", "GU", "AS", "MP"].contains(country)
    }

    static func request(at coordinate: Coordinate) -> URLRequest? {
        var request = URLComponents.request("https://api.weather.gov/alerts/active", [
            "point": String(format: "%.2f,%.2f", coordinate.latitude, coordinate.longitude),
            "status": "actual",
        ])
        // Required: without one the NWS answers 403.
        request?.setValue("HoverEnhance (https://hoverenhance.com)", forHTTPHeaderField: "User-Agent")
        request?.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        return request
    }

    static func alerts(at coordinate: Coordinate, using http: any WeatherHTTP) async throws(WeatherError) -> [WeatherAlert] {
        guard let request = request(at: coordinate) else { return [] }
        return try alerts(from: await http.data(for: request), at: coordinate)
    }

    /// Active alerts, most severe first, without updates repeating an alert or any that have ended.
    static func alerts(from data: Data, at coordinate: Coordinate, now: Date = Date()) throws(WeatherError) -> [WeatherAlert] {
        guard let features = try JSON.object(data)["features"] as? [[String: Any]] else { throw .unreadable }
        // The point's forecast page, which lists its alerts in full.
        let page = URL(string: String(format: "https://forecast.weather.gov/MapClick.php?lat=%.2f&lon=%.2f", coordinate.latitude, coordinate.longitude))
        var seen = Set<String>()
        return features.compactMap { feature -> WeatherAlert? in
            guard let properties = feature["properties"] as? [String: Any], let event = properties["event"] as? String else { return nil }
            let ends = JSON.date(properties["ends"]) ?? JSON.date(properties["expires"])
            if let ends, ends < now { return nil }
            guard seen.insert("\(event)|\(ends?.timeIntervalSince1970 ?? 0)").inserted else { return nil }
            return WeatherAlert(title: event, severity: .init(properties["severity"] as? String),
                                starts: JSON.date(properties["onset"]) ?? JSON.date(properties["effective"]), ends: ends,
                                detail: properties["headline"] as? String ?? properties["description"] as? String,
                                source: properties["senderName"] as? String, url: page)
        }
        .sorted { $0.severity > $1.severity }
    }
}
