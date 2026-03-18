import SwiftUI
import CoreLocation
import MapKit

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var exits: [StationExit] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var cameraPosition: MapCameraPosition = .automatic

    // 手動位置指定モード
    @State private var isManualMode = false
    @State private var isFollowingLocation = false          // 現在地フォローモード
    @State private var lastProgrammaticCameraUpdate = Date.distantPast  // プログラム操作 vs ユーザー操作の区別
    @State private var mapCameraHeading: Double = 0
    @State private var manualCoordinate: CLLocationCoordinate2D?
    @State private var pinnedManualCoordinate: CLLocationCoordinate2D?  // 検索実行時に確定したピン
    @State private var pinnedLocationName: String?  // 場所検索で確定した場所名

    // ルート
    @State private var selectedExit: StationExit?
    @State private var route: MKRoute?
    @State private var isCalculatingRoute = false

    // 設定
    @State private var showSettings = false

    // 起動時マップ向き
    @State private var hasSetInitialHeading = false

    // 初回検索完了フラグ（起動直後の「見つかりませんでした」誤表示を防ぐ）
    @State private var hasFetchedOnce = false

    // ローディングメッセージのローテーション
    private let loadingMessages = [
        "出口を探しています...",
        "地図データを確認中...",
        "少々お待ちください...",
        "周辺の駅を確認中...",
        "出口情報を読み込み中...",
        "通信中..."
    ]
    @State private var loadingMessageIndex = 0

    // 場所検索
    @State private var searchText = ""
    @State private var locationSearchResults: [MKMapItem] = []
    @State private var isSearchingLocation = false  // 候補リスト表示中かどうか

    var searchCoordinate: CLLocationCoordinate2D? {
        isManualMode ? manualCoordinate : locationManager.location?.coordinate
    }

    var body: some View {
        NavigationStack {
            Group {
                switch locationManager.authorizationStatus {
                case .notDetermined:
                    permissionView
                case .denied, .restricted:
                    deniedView
                default:
                    mainView
                }
            }
            .navigationTitle("駅出口マップ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await fetchExits() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading || searchCoordinate == nil)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "行きたい場所を検索")
            .task(id: searchText) {
                await performLocationSearch()
            }
        }
        .onAppear { locationManager.requestLocation() }
        .onChange(of: locationManager.location) { _, newLocation in
            if newLocation != nil && exits.isEmpty && !isManualMode {
                Task { await fetchExits() }
            }
            // フォローモード中は現在地に追従（カメラの向きを維持）
            if isFollowingLocation, let coord = newLocation?.coordinate {
                setCamera(.camera(MapCamera(
                    centerCoordinate: coord,
                    distance: 800,
                    heading: mapCameraHeading,
                    pitch: 0
                )))
            }
        }
        .onReceive(locationManager.$heading) { _ in
            applyInitialHeadingIfNeeded()
        }
    }

    // MARK: - メインビュー

    private var mainView: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // コンテンツが少なければ縮み、多ければ最大 50% まで伸びる
                exitListView
                    .frame(maxHeight: geometry.size.height * 0.4)
                // マップは残りをすべて使う（最低 60%）
                mapView
                    .frame(minHeight: geometry.size.height * 0.6)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: - マップ

    private var mapView: some View {
        ZStack {
            Map(position: $cameraPosition) {
                // 現在地（カスタム：常時コーン表示）
                if let userLocation = locationManager.location {
                    Annotation("", coordinate: userLocation.coordinate, anchor: .center) {
                        UserLocationView(
                            userHeading: locationManager.heading.map {
                                $0.trueHeading >= 0 ? $0.trueHeading : $0.magneticHeading
                            },
                            mapCameraHeading: mapCameraHeading
                        )
                    }
                    .annotationTitles(.hidden)
                }

                // 手動指定ピン
                if let pinCoord = pinnedManualCoordinate {
                    Annotation(pinnedLocationName ?? "指定した場所", coordinate: pinCoord) {
                        VStack(spacing: 0) {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 28, height: 28)
                                    .shadow(radius: 3)
                                Image(systemName: "mappin")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            // ピンの尻尾
                            Triangle()
                                .fill(Color.red)
                                .frame(width: 10, height: 6)
                        }
                    }
                }

                // ルート描画
                if let route {
                    MapPolyline(route.polyline)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }

                // 出口ピン
                ForEach(Array(exits.enumerated()), id: \.element.id) { index, exit in
                    let rank = index + 1
                    let isSelected = selectedExit?.id == exit.id
                    let annotationLabel: String = {
                        if exit.isStationNode { return exit.stationName }
                        if let ref = exit.ref  { return "\(ref)番出口" }
                        return exit.stationName  // ref なし → name 自体が出口名
                    }()
                    Annotation(annotationLabel, coordinate: exit.coordinate) {
                        ZStack {
                            Circle()
                                .fill(pinColor(for: exit, isSelected: isSelected))
                                .frame(width: isSelected ? 36 : 28, height: isSelected ? 36 : 28)
                                .shadow(color: isSelected ? .black.opacity(0.3) : .clear, radius: 4)
                            if exit.isStationNode {
                                Image(systemName: "tram.fill")
                                    .font(.system(size: isSelected ? 18 : 14))
                                    .foregroundStyle(.black)
                            } else {
                                Text(rankLabel(rank))
                                    .font(.system(size: isSelected ? 14 : 12, weight: .bold))
                                    .foregroundStyle(isSelected ? .white : .black)
                            }
                        }
                        .animation(.spring(duration: 0.2), value: isSelected)
                    }
                }
            }
            .onMapCameraChange(frequency: .continuous) { context in
                mapCameraHeading = context.camera.heading
                if isManualMode { manualCoordinate = context.region.center }
                // プログラム操作から 0.8 秒以上経過していればユーザー操作 → フォロー解除
                if isFollowingLocation,
                   Date().timeIntervalSince(lastProgrammaticCameraUpdate) > 0.8 {
                    isFollowingLocation = false
                }
            }
            .mapControlVisibility(.hidden)

            // ボタン類（左上: 手動ピン、右上: 向き追従）
            VStack {
                HStack {
                    Button { toggleManualMode() } label: {
                        Image(systemName: "mappin")
                            .font(.system(size: isManualMode ? 20 : 17,
                                          weight: isManualMode ? .bold : .regular))
                            .foregroundStyle(isManualMode ? .red : .secondary)
                            .frame(width: 44, height: 44)
                            .animation(.spring(duration: 0.2), value: isManualMode)
                    }
                    .glassEffect(.regular.interactive(), in: Circle())
                    .padding(.leading, 8)
                    .padding(.top, 8)
                    Spacer()
                    Button { recenterOnUser() } label: {
                        Image(systemName: isFollowingLocation ? "location.fill" : "location")
                            .font(.system(size: 17))
                            .foregroundStyle(isFollowingLocation ? .blue : .secondary)
                            .frame(width: 44, height: 44)
                            .animation(.spring(duration: 0.2), value: isFollowingLocation)
                    }
                    .glassEffect(.regular.interactive(), in: Circle())
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                }
                Spacer()
            }

            // ルート計算中インジケーター
            if isCalculatingRoute {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("ルートを計算中...")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 12)
                }
            }

            // 手動モード UI
            if isManualMode {
                VStack(spacing: 0) {
                    Image(systemName: "mappin")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.red)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                    Circle()
                        .fill(Color.black.opacity(0.25))
                        .frame(width: 6, height: 3)
                        .blur(radius: 1.5)
                }
                .offset(y: -16) // ピン先端を中心に合わせる

                VStack {
                    Spacer()
                    Button { Task { await fetchExits() } } label: {
                        Label("この場所で検索", systemImage: "magnifyingglass")
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.yellow)
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(isLoading)
                    .padding(.bottom, 30)
                }
            }

            // クレジット
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("© OpenStreetMap contributors")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.trailing, 6)
                        .padding(.bottom, 6)
                }
            }
        }
        // マップタップでキーボードを閉じる
        .simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil, from: nil, for: nil
            )
        })
    }

    // MARK: - リスト（ScrollView でコンテンツ量に合わせて縮む）

    private var exitListView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 場所検索中は候補リストを表示
                if isSearchingLocation {
                    if locationSearchResults.isEmpty {
                        HStack {
                            Spacer()
                            Text("候補なし")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    } else {
                        ForEach(Array(locationSearchResults.enumerated()), id: \.element) { index, item in
                            Button {
                                selectLocation(item)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.red)
                                        .frame(width: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name ?? "不明な場所")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        if let address = item.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true) {
                                            Text(address)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.forward.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            if index < locationSearchResults.count - 1 {
                                Divider().padding(.leading, 64)
                            }
                        }
                    }
                } else if isManualMode {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin").foregroundStyle(.red)
                        Text("マップをドラッグして場所を指定し「この場所で検索」を押してください")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.05))
                    Divider()
                } else if let name = pinnedLocationName {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin").foregroundStyle(.red)
                        Text(name)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.05))
                    Divider()
                }

                if !isSearchingLocation {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView(loadingMessages[loadingMessageIndex])
                                .onAppear {
                                    loadingMessageIndex = 0
                                }
                                .task {
                                    while isLoading {
                                        try? await Task.sleep(for: .seconds(2))
                                        if isLoading {
                                            withAnimation(.easeInOut(duration: 0.4)) {
                                                loadingMessageIndex = (loadingMessageIndex + 1) % loadingMessages.count
                                            }
                                        }
                                    }
                                }
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    } else if let error = errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .padding(16)
                    } else if exits.isEmpty && hasFetchedOnce {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("近くに駅出口が見つかりませんでした").foregroundStyle(.secondary)
                            if let loc = locationManager.location {
                                Text("現在地: \(loc.coordinate.latitude, specifier: "%.5f"), \(loc.coordinate.longitude, specifier: "%.5f")")
                                    .font(.caption).foregroundStyle(.tertiary)
                            } else {
                                Text("現在地: 取得中...").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(16)
                    } else {
                        let hasOtherExits = exits.contains(where: { !$0.isStationNode })
                        ForEach(Array(exits.enumerated()), id: \.element.id) { index, exit in
                            ExitRow(
                                exit: exit,
                                rank: index + 1,
                                isSelected: selectedExit?.id == exit.id,
                                isCalculating: isCalculatingRoute && selectedExit?.id == exit.id,
                                hasOtherExits: hasOtherExits
                            ) {
                                Task { await calculateRoute(to: exit) }
                            }
                            if index < exits.count - 1 {
                                Divider().padding(.leading, 64)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(UIColor.systemBackground))
    }

    // MARK: - 許可ビュー

    private var permissionView: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.circle").font(.system(size: 64)).foregroundStyle(.blue)
            Text("現在地の使用を許可してください").font(.headline)
            Text("駅出口マップを使うために位置情報が必要です")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("位置情報を許可する") { locationManager.requestLocation() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var deniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.slash").font(.system(size: 64)).foregroundStyle(.red)
            Text("位置情報が許可されていません").font(.headline)
            Text("設定 > 駅出口マップ から位置情報を許可してください")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - ロジック

    private func pinColor(for exit: StationExit, isSelected: Bool) -> Color {
        isSelected ? .green : .yellow
    }

    /// fetchExits 完了後のカメラ設定（初回は向きを反映、以降は通常 region）
    private func setCameraAfterFetch(center: CLLocationCoordinate2D) {
        if !hasSetInitialHeading,
           !isManualMode,
           let h = locationManager.heading,
           (h.trueHeading >= 0 || h.magneticHeading >= 0) {
            hasSetInitialHeading = true
            let heading = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
            setCamera(.camera(MapCamera(
                centerCoordinate: center,
                distance: 800,
                heading: heading,
                pitch: 0
            )))
        } else {
            setCamera(.region(MKCoordinateRegion(
                center: center, latitudinalMeters: 600, longitudinalMeters: 600
            )))
        }
    }

    /// カメラをプログラムで変更（ユーザー操作と区別するためタイムスタンプを記録）
    private func setCamera(_ position: MapCameraPosition) {
        lastProgrammaticCameraUpdate = Date()
        cameraPosition = position
    }

    /// 現在地フォローモード：現在地に戻り、現在の向きに合わせてカメラを設定
    private func recenterOnUser() {
        guard let coord = locationManager.location?.coordinate else { return }
        // ピンモード中なら解除して現在地で再検索
        if isManualMode {
            selectedExit = nil
            route = nil
            pinnedManualCoordinate = nil
            pinnedLocationName = nil
            isManualMode = false
            exits = []
            Task { await fetchExits() }
        }
        isFollowingLocation = true
        if let h = locationManager.heading,
           (h.trueHeading >= 0 || h.magneticHeading >= 0) {
            let heading = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
            setCamera(.camera(MapCamera(
                centerCoordinate: coord,
                distance: 800,
                heading: heading,
                pitch: 0
            )))
        } else {
            setCamera(.region(MKCoordinateRegion(
                center: coord, latitudinalMeters: 600, longitudinalMeters: 600
            )))
        }
    }

    /// heading が遅れて到着した場合のフォールバック（1回だけ）
    private func applyInitialHeadingIfNeeded() {
        guard !hasSetInitialHeading,
              !isManualMode,
              !isFollowingLocation,
              !exits.isEmpty,
              let coord = locationManager.location?.coordinate,
              let h = locationManager.heading,
              (h.trueHeading >= 0 || h.magneticHeading >= 0) else { return }
        hasSetInitialHeading = true
        let heading = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
        setCamera(.camera(MapCamera(
            centerCoordinate: coord,
            distance: 800,
            heading: heading,
            pitch: 0
        )))
    }

    private func toggleManualMode() {
        selectedExit = nil
        route = nil
        pinnedManualCoordinate = nil
        pinnedLocationName = nil
        isFollowingLocation = false
        isManualMode.toggle()
        if !isManualMode {
            exits = []
            if let location = locationManager.location {
                setCamera(.region(MKCoordinateRegion(
                    center: location.coordinate,
                    latitudinalMeters: 600,
                    longitudinalMeters: 600
                )))
                Task { await fetchExits() }
            }
        } else {
            if let location = locationManager.location {
                manualCoordinate = location.coordinate
            }
        }
    }

    private func calculateRoute(to exit: StationExit) async {
        // 同じ出口をタップ → ルートをクリア
        if selectedExit?.id == exit.id {
            selectedExit = nil
            route = nil
            let resetCoord = pinnedManualCoordinate ?? locationManager.location?.coordinate
            if let coord = resetCoord {
                setCamera(.region(MKCoordinateRegion(
                    center: coord, latitudinalMeters: 600, longitudinalMeters: 600
                )))
            }
            return
        }

        selectedExit = exit
        route = nil
        isFollowingLocation = false
        isCalculatingRoute = true

        let request = MKDirections.Request()
        if let pinCoord = pinnedManualCoordinate {
            // 検索モード：出口 → 目的地（ピン）のルート
            request.source = MKMapItem(
                location: CLLocation(latitude: exit.coordinate.latitude, longitude: exit.coordinate.longitude),
                address: nil
            )
            request.destination = MKMapItem(
                location: CLLocation(latitude: pinCoord.latitude, longitude: pinCoord.longitude),
                address: nil
            )
        } else {
            // GPSモード：現在地 → 出口のルート
            guard let userCoord = locationManager.location?.coordinate else {
                isCalculatingRoute = false
                return
            }
            request.source = MKMapItem(
                location: CLLocation(latitude: userCoord.latitude, longitude: userCoord.longitude),
                address: nil
            )
            request.destination = MKMapItem(
                location: CLLocation(latitude: exit.coordinate.latitude, longitude: exit.coordinate.longitude),
                address: nil
            )
        }
        request.transportType = .walking

        do {
            let response = try await MKDirections(request: request).calculate()
            route = response.routes.first
            if let polyline = response.routes.first?.polyline {
                let rect = polyline.boundingMapRect
                // 余白を加えてカメラをフィット
                let padded = rect.insetBy(
                    dx: -rect.width * 0.4,
                    dy: -rect.height * 0.4
                )
                setCamera(.rect(padded))
            }
        } catch {
            // ルート取得失敗時は出口を中心に表示
            setCamera(.region(MKCoordinateRegion(
                center: exit.coordinate, latitudinalMeters: 600, longitudinalMeters: 600
            )))
        }
        isCalculatingRoute = false
    }

    private func performLocationSearch() async {
        guard !searchText.isEmpty else {
            locationSearchResults = []
            isSearchingLocation = false
            return
        }
        // デバウンス: 入力が止まってから 350ms 後に検索
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        isSearchingLocation = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.resultTypes = [.address, .pointOfInterest]
        if let coord = locationManager.location?.coordinate {
            request.region = MKCoordinateRegion(
                center: coord, latitudinalMeters: 100_000, longitudinalMeters: 100_000
            )
        }
        if let response = try? await MKLocalSearch(request: request).start() {
            locationSearchResults = response.mapItems
        } else {
            locationSearchResults = []
        }
    }

    private func selectLocation(_ item: MKMapItem) {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
        let coordinate = item.location.coordinate
        // searchText はそのまま保持（ユーザーが自分で消す）
        locationSearchResults = []
        isSearchingLocation = false
        isManualMode = true
        isFollowingLocation = false
        pinnedLocationName = item.name
        manualCoordinate = coordinate
        pinnedManualCoordinate = coordinate
        setCamera(.region(MKCoordinateRegion(
            center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600
        )))
        Task { await fetchExits() }
    }

    /// 座標から住所を取得（逆ジオコーディング）
    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        guard let placemark = placemarks?.first else { return nil }
        // 都道府県 + 市区町村 + 町名を組み合わせ（例: "東京都渋谷区桜丘町"）
        let components = [
            placemark.administrativeArea,  // 都道府県
            placemark.locality,            // 市区町村
            placemark.subLocality          // 町名
        ].compactMap { $0 }
        return components.isEmpty ? nil : components.joined()
    }

    private func fetchExits() async {
        guard let coordinate = searchCoordinate else {
            if !isManualMode { locationManager.requestLocation() }
            return
        }
        selectedExit = nil
        route = nil
        isFollowingLocation = false
        isLoading = true
        errorMessage = nil
        do {
            exits = try await OverpassService.fetchExits(near: coordinate)
            // 手動モードのとき検索座標をピンとして確定し、ピンモードを終了
            if isManualMode {
                pinnedManualCoordinate = coordinate
                isManualMode = false
                // 検索バー経由でなければ住所を逆ジオコーディングで取得
                if pinnedLocationName == nil {
                    pinnedLocationName = await reverseGeocode(coordinate)
                }
            }
            setCameraAfterFetch(center: coordinate)
        } catch {
            // 失敗したら 2 秒待って 1 回だけ自動リトライ（瞬断対策）
            try? await Task.sleep(for: .seconds(2))
            do {
                exits = try await OverpassService.fetchExits(near: coordinate)
                if isManualMode {
                    pinnedManualCoordinate = coordinate
                    isManualMode = false
                    if pinnedLocationName == nil {
                        pinnedLocationName = await reverseGeocode(coordinate)
                    }
                }
                setCameraAfterFetch(center: coordinate)
            } catch {
                errorMessage = "データの取得に失敗しました。通信状況を確認してください。"
            }
        }
        hasFetchedOnce = true
        isLoading = false
    }
}

// MARK: - ランクラベル（A, B, C, ...）

private func rankLabel(_ rank: Int) -> String {
    guard rank >= 1, rank <= 26 else { return "\(rank)" }
    return String(UnicodeScalar(64 + rank)!)
}

// MARK: - Triangle Shape（ピンの尻尾）

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - ユーザー位置（青丸 + 方向コーン）

struct UserLocationView: View {
    let userHeading: Double?
    let mapCameraHeading: Double

    private let dotSize: CGFloat = 22
    private let coneSize: CGFloat = 120

    var body: some View {
        ZStack {
            if let heading = userHeading, heading >= 0 {
                HeadingConeShape()
                    .fill(
                        RadialGradient(
                            colors: [.purple.opacity(0.7), .purple.opacity(0.2), .clear],
                            center: .center,
                            startRadius: dotSize / 2,
                            endRadius: coneSize / 2
                        )
                    )
                    .frame(width: coneSize, height: coneSize)
                    .rotationEffect(.degrees(heading - mapCameraHeading))
            }
            Circle()
                .fill(.white)
                .frame(width: dotSize, height: dotSize)
            Circle()
                .fill(.blue)
                .frame(width: dotSize - 4, height: dotSize - 4)
        }
        .allowsHitTesting(false)
    }
}

/// 上方向（12時）を中心とした 70° の扇形
struct HeadingConeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        // ±35° = 70° の扇形。中心は -90°（画面上方向）
        let halfAngle = 35.0
        var path = Path()
        path.move(to: center)
        // clockwise: false → 短い 70° 弧（向いている方向）
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90 - halfAngle),
            endAngle: .degrees(-90 + halfAngle),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - 時間フォーマット

private extension TimeInterval {
    var formattedWalkTime: String {
        let minutes = Int(self / 60)
        if minutes < 1 { return "1分以内" }
        if minutes < 60 { return "\(minutes)分" }
        return "\(minutes / 60)時間\(minutes % 60)分"
    }
}

// MARK: - 出口行

struct ExitRow: View {
    let exit: StationExit
    let rank: Int
    let isSelected: Bool
    let isCalculating: Bool
    let hasOtherExits: Bool  // 番号付き出口が他にあるか
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.green : Color.yellow)
                        .frame(width: 40, height: 40)
                    if isCalculating {
                        ProgressView().tint(.white)
                    } else {
                        if exit.isStationNode {
                            Image(systemName: "tram.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.black)
                        } else {
                            Text(rankLabel(rank))
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(isSelected ? .white : .black)
                        }
                    }
                }
                .animation(.spring(duration: 0.2), value: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    // サブタイトル（駅名 or "駅出口"）
                    Text(exit.isStationNode || exit.ref != nil ? exit.stationName : "駅出口")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // メインラベル
                    if exit.isStationNode {
                        // 駅ノード（他に出口がなければ primary、あれば secondary）
                        Text("駅入口")
                            .font(.headline)
                            .foregroundStyle(isSelected ? .green : (hasOtherExits ? .secondary : .primary))
                    } else if let ref = exit.ref {
                        // ref あり → "A5b出口" のように表示
                        Text("\(ref)番出口")
                            .font(.headline)
                            .foregroundStyle(isSelected ? .green : .primary)
                    } else {
                        // ref なし → name タグ自体が出口名（"仲町口", "West exit" など）
                        Text(exit.stationName)
                            .font(.headline)
                            .foregroundStyle(isSelected ? .green : .primary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(exit.distanceText)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(isSelected ? .green : .primary)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.green.opacity(0.08) : Color.clear)
        .padding(.horizontal, 4)
    }
}
