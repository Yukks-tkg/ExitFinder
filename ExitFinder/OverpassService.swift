import CoreLocation

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum OverpassError: Error {
    case invalidURL
    case noData
}

struct OverpassService {
    // タイムアウト付き URLSession（35秒）
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 35
        config.timeoutIntervalForResource = 35
        return URLSession(configuration: config)
    }()

    // 並列リクエスト用ミラー一覧（全部同時に叩いて最速を使う）
    private static let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
        "https://overpass.osm.jp/api/interpreter",           // 日本ミラー
        "https://overpass.openstreetmap.ru/api/interpreter",  // ロシアミラー
    ]

    // 簡易キャッシュ（2分間・100m以内は再利用）
    private struct CacheEntry {
        let exits: [StationExit]
        let timestamp: Date
        let coordinate: CLLocationCoordinate2D
    }
    private static var cache: CacheEntry?
    private static let cacheDuration: TimeInterval = 300
    private static let cacheDistanceThreshold: Double = 300

    static func fetchExits(near coordinate: CLLocationCoordinate2D, radius: Int = 500, forceRefresh: Bool = false) async throws -> [StationExit] {
        let userLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        // キャッシュヒット確認（forceRefresh 時はスキップ）
        if !forceRefresh,
           let cached = cache,
           Date().timeIntervalSince(cached.timestamp) < cacheDuration,
           userLocation.distance(from: CLLocation(
               latitude: cached.coordinate.latitude,
               longitude: cached.coordinate.longitude)
           ) < cacheDistanceThreshold {
            return cached.exits
        }

        // [timeout:30] = サーバー側タイムアウト（URLSession の 35 秒より短め）
        let query = """
        [out:json][timeout:30];
        (
          node[railway=subway_entrance](around:\(radius),\(coordinate.latitude),\(coordinate.longitude));
          node[railway=entrance](around:\(radius),\(coordinate.latitude),\(coordinate.longitude));
          node[railway=train_station_entrance](around:\(radius),\(coordinate.latitude),\(coordinate.longitude));
          node[railway=station](around:\(radius),\(coordinate.latitude),\(coordinate.longitude));
        ) -> .nodes;
        .nodes out body;
        relation[public_transport=stop_area](bn.nodes);
        out;
        """

        // 全エンドポイントに並列リクエスト → 最初に成功したものを採用
        let exits = try await withThrowingTaskGroup(of: Result<[StationExit], Error>.self) { group in
            for endpoint in endpoints {
                group.addTask {
                    do {
                        let result = try await fetchFromEndpoint(endpoint, query: query, userLocation: userLocation)
                        return .success(result)
                    } catch {
                        return .failure(error)
                    }
                }
            }

            var lastError: Error = OverpassError.noData
            for try await result in group {
                switch result {
                case .success(let exits):
                    group.cancelAll()
                    return exits
                case .failure(let error):
                    lastError = error
                }
            }
            throw lastError
        }

        // キャッシュ更新
        cache = CacheEntry(exits: exits, timestamp: Date(), coordinate: coordinate)
        return exits
    }

    // MARK: - 単一エンドポイントへのリクエスト（POST）

    private static func fetchFromEndpoint(
        _ endpoint: String,
        query: String,
        userLocation: CLLocation
    ) async throws -> [StationExit] {
        guard let url = URL(string: endpoint),
              let body = "data=\(query)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?.data(using: .utf8)
        else { throw OverpassError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        // HTTP エラーは失敗扱い
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OverpassError.noData
        }

        let overpassResponse = try JSONDecoder().decode(OverpassResponse.self, from: data)

        // stop_area リレーションから「ノードID → 駅名」マップを構築
        let nodeToStationName: [Int: String] = {
            var map: [Int: String] = [:]
            for element in overpassResponse.elements where element.type == "relation" {
                let name = element.tags["name:ja"] ?? element.tags["name"] ?? ""
                guard !name.isEmpty else { continue }
                for member in element.members ?? [] where member.type == "node" {
                    map[member.ref] = name
                }
            }
            return map
        }()

        let sorted = overpassResponse.elements
            .filter { $0.type == "node" }
            .compactMap { element -> StationExit? in
                guard let lat = element.lat, let lon = element.lon else { return nil }
                let railwayType = element.tags["railway"] ?? ""
                let isStation  = railwayType == "station"
                let isEntrance = railwayType == "entrance" || railwayType == "subway_entrance"
                let isTrainEntrance = railwayType == "train_station_entrance"
                guard isEntrance || isTrainEntrance || isStation else { return nil }

                // train_station_entrance で名前もrefもないノードはスキップ
                if isTrainEntrance {
                    let hasRef = element.tags["ref"]?.nilIfEmpty != nil
                    let hasName = (element.tags["name:ja"] ?? element.tags["name"] ?? "").contains(";")
                        || (element.tags["name:ja"] ?? element.tags["name"] ?? "").nilIfEmpty != nil
                    if !hasRef && !hasName { return nil }
                }

                let dist = userLocation.distance(from: CLLocation(latitude: lat, longitude: lon))

                let ownName = element.tags["name:ja"] ?? element.tags["name"] ?? ""
                // JR改札口の名前をきれいに整形（例: "JR秋葉原駅;電気街改札" → "電気街改札"）
                let cleanedName: String = {
                    if isTrainEntrance, ownName.contains(";") {
                        return ownName.components(separatedBy: ";").last ?? ownName
                    }
                    return ownName
                }()
                let stationName: String = {
                    if isTrainEntrance, ownName.contains(";") {
                        return ownName.components(separatedBy: ";").first ?? "付近の駅"
                    }
                    return nodeToStationName[element.id]
                        ?? (ownName == "駅" || ownName.isEmpty ? nil : ownName)
                        ?? "付近の駅"
                }()

                return StationExit(
                    id: element.id,
                    stationName: stationName,
                    ref: (isEntrance || isTrainEntrance) ? (element.tags["ref"]?.nilIfEmpty ?? (isTrainEntrance ? cleanedName.nilIfEmpty : nil)) : nil,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    distance: dist,
                    isStationNode: isStation
                )
            }
            .sorted { $0.distance < $1.distance }

        // 同じ出口名で50m以内のノードは重複とみなし、最も近いものだけ残す
        var deduped: [StationExit] = []
        for exit in sorted {
            let isDuplicate = deduped.contains { existing in
                guard let existingRef = existing.ref, let exitRef = exit.ref else { return false }
                guard existingRef == exitRef else { return false }
                let loc1 = CLLocation(latitude: existing.coordinate.latitude, longitude: existing.coordinate.longitude)
                let loc2 = CLLocation(latitude: exit.coordinate.latitude, longitude: exit.coordinate.longitude)
                return loc1.distance(from: loc2) < 50
            }
            if !isDuplicate { deduped.append(exit) }
        }

        // 具体的な出口ノードが1件以上あれば駅入口エリアを除外、
        // 出口ノードがまったくない場合のみフォールバックとして残す
        let hasEntrances = deduped.contains { !$0.isStationNode }
        return (hasEntrances ? deduped.filter { !$0.isStationNode } : deduped)
            .prefix(10)
            .map { $0 }
    }
}

// MARK: - Overpass API レスポンスモデル

private struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
}

private struct OverpassElement: Decodable {
    let type: String
    let id: Int
    let lat: Double?
    let lon: Double?
    let tags: [String: String]
    let members: [OverpassMember]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type    = try c.decode(String.self, forKey: .type)
        id      = try c.decode(Int.self, forKey: .id)
        lat     = try c.decodeIfPresent(Double.self, forKey: .lat)
        lon     = try c.decodeIfPresent(Double.self, forKey: .lon)
        tags    = (try? c.decodeIfPresent([String: String].self, forKey: .tags)) ?? [:]
        members = try? c.decodeIfPresent([OverpassMember].self, forKey: .members)
    }

    enum CodingKeys: String, CodingKey { case type, id, lat, lon, tags, members }
}

private struct OverpassMember: Decodable {
    let type: String
    let ref: Int
    let role: String
}
