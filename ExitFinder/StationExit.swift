import CoreLocation

struct StationExit: Identifiable {
    let id: Int
    let stationName: String
    let ref: String?
    let coordinate: CLLocationCoordinate2D
    var distance: CLLocationDistance = 0
    var isStationNode: Bool = false  // true = 駅ノード自体（出口ではなく駅エリア全体）

    var displayRef: String {
        ref ?? "出口"
    }

    var distanceText: String {
        distance < 1000 ? "\(Int(distance))m" : String(format: "%.1fkm", distance / 1000)
    }
}
