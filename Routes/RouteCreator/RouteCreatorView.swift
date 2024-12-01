//
//  RouteCreatorView.swift
//  Routes
//
//  Created by Xavi Roig Aznar on 4/11/24.
//

import MapKit
import SwiftUI
import SwiftData

struct RouteCreatorView: View {
    // MARK: - Environment properties
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationManager.self) var locationManager

    // MARK: - Query properties
    @Query(filter: #Predicate<Placemark> {$0.route == nil}) private var searchPlacemarks: [Placemark]
    @Query private var listPoisPlacemarks: [PointOfInterestPlacemark]

    // MARK: - Observed objects
    @ObservedObject var viewModel: RouteCreatorViewModel

    // MARK: - State properties
    @State private var visibleRegion: MKCoordinateRegion?
    @State var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    // Search
    @State private var searchText = ""
    @FocusState private var searchFieldFocus: Bool

    // Route
    @State private var startingPlacemark: Placemark?
    @State private var routePlacemarks: [RouteIntermediatePlacemark] = []
    @State private var showDetail = false
    @State private var designRoute = false
    @State private var fetchingRoute = false
    @State private var routeDisplaying = false
    @State private var route: Route?
    @State private var routeDestination: MKMapItem?
    @State private var travelInterval: TimeInterval?
    @State private var showSteps = false
    @Namespace private var mapScope
    @State private var mapStyleConfig = MapStyleConfig()

    // Points of Interest
    @State private var showPoisPicker = false
    @State private var selectedPointOfInterest: PointOfInterestPlacemark?
    @State private var poiSelectedIndex = 0
    @State private var showPoiSelectedAlert = false
    @State private var routePointsOfInterest: [PointOfInterestPlacemark] = []

    // MARK: - Stored properties
    private var pointsOfInterest: [PointOfInterestModel] = [.cafe, .gasStation, .hotel, .mechanic]

    // MARK: - Init
    init(viewModel: RouteCreatorViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Body
    var body: some View {
        ZStack {
            ZStack(alignment: .bottom) {
                mapReader
                bottomSafeAreaView
                    .padding(20)
                if showPoisPicker {
                    poisPickerView
                }
            }
            .opacity(fetchingRoute ? 0.3 : 1)
            if fetchingRoute {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
            }
        }
        .alert("Do you want to add it to the route?", isPresented: $showPoiSelectedAlert) {
            Button("No", role: .destructive) {
                selectedPointOfInterest = nil
            }
            Button("Yes", role: .cancel) {
                if let selectedPointOfInterest {
                    fetchingRoute = true
                    Task { @MainActor in
                        await viewModel.updateRoute(with: selectedPointOfInterest)
                        routePointsOfInterest.append(selectedPointOfInterest)
                        MapManager.removePointsOfInterestResults(modelContext)
                        fetchingRoute = false
                    }
                    self.selectedPointOfInterest = nil
                }
            }
        }
    }
}

// MARK: - Private views
private extension RouteCreatorView {
    @ViewBuilder var topSafeAreaView: some View {
        if routeDisplaying {
            VStack(alignment: .trailing) {
                Button {
                    showPoisPicker.toggle()
                } label: {
                    Image(systemName: "mappin")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appSecondary)
            .buttonBorderShape(.circle)
            .padding(30)
        }
        if !searchPlacemarks.isEmpty, !routeDisplaying {
            VStack(alignment: .trailing) {
                Text("Circular route")
                    .foregroundStyle(Color("AppSecondary"), Color("AccentColor"))
                    .font(.headline)
                Toggle("", isOn: $viewModel.circularRoute)
            }
            .padding(.trailing, 20)
        }
    }

    @ViewBuilder var mapReader: some View {
        MapReader { proxy in
            ZStack(alignment: .topTrailing) {
                map
                    .onTapGesture { position in
                        guard !showPoisPicker, !routeDisplaying else {
                            showPoisPicker = false
                            return
                        }
                        if let coordinate = proxy.convert(position, from: .local) {
                            if startingPlacemark == nil  {
                                let placemark = Placemark(name: "Starting point",
                                                          address: "",
                                                          latitude: coordinate.latitude,
                                                          longitude: coordinate.longitude)
                                viewModel.setStartingPlacemark(placemark)
                                startingPlacemark = placemark
                                modelContext.insert(placemark)
                            } else {
                                let placemark = RouteIntermediatePlacemark(name: "Route point \(routePlacemarks.count + 1)",
                                                                           address: "",
                                                                           latitude: coordinate.latitude,
                                                                           longitude: coordinate.longitude)
                                routePlacemarks.append(placemark)
                                viewModel.setRoutePlacemarks(routePlacemarks)
                                modelContext.insert(placemark)
                            }
                        }
                    }
                topSafeAreaView
                    .padding(20)
            }
                .onMapCameraChange{ context in
                    visibleRegion = context.region
                }
                .onAppear {
                    MapManager.removeSearchResults(modelContext)
                    MapManager.removePointsOfInterestResults(modelContext)
                    updateCameraPosition()
                }
                .mapStyle(mapStyleConfig.mapStyle)
                .sheet(isPresented: $showDetail) {
                    RouteDetailView(
                        route: $route,
                        startPlacemark: startingPlacemark,
                        routePlacemarks: routePlacemarks,
                        routeSegments: viewModel.routeSegments,
                        showRoute: $viewModel.showRoute,
                        circularRoute: $viewModel.circularRoute,
                        cameraPosition: $cameraPosition
                    )
                    .presentationDetents([.large])
                }
                .onChange(of: designRoute) {
                    if designRoute {
                        showDetail = (viewModel.circularRoute ? routePlacemarks.count + 1 : routePlacemarks.count) == viewModel.routeSegments.count
                        if showDetail {
                            if let startingPlacemarkCoordinates = startingPlacemark?.coordinate {
                                cameraPosition = .region(MKCoordinateRegion(center: startingPlacemarkCoordinates,
                                                                            span: MKCoordinateSpan(latitudeDelta: 0.1,
                                                                                                   longitudeDelta: 0.1)))
                            }
                        }
                    }
                }
                .onChange(of: viewModel.showRoute) {
                    if viewModel.showRoute {
                        withAnimation {
                            routeDisplaying = true
                            if let startingPlacemarkCoordinates = startingPlacemark?.coordinate {
                                cameraPosition = .region(MKCoordinateRegion(center: startingPlacemarkCoordinates,
                                                                            span: MKCoordinateSpan(latitudeDelta: 0.1,
                                                                                                   longitudeDelta: 0.1)))
                            }
                        }
                    }
                }
        }
    }

    @ViewBuilder var map: some View {
        Map(position: $cameraPosition, selection: $selectedPointOfInterest) {
            UserAnnotation()
            if let startingPlacemark {
                Marker(coordinate: startingPlacemark.coordinate) {
                    Label(startingPlacemark.name, systemImage: viewModel.circularRoute ? "point.forward.to.point.capsulepath.fill" : "location.north.line")
                }
                .tint(.green)
                .tag(startingPlacemark)
            }
            ForEach(routePlacemarks, id: \.self) { placemark in
                Group {
                    if placemark.route != nil {
                        Marker(coordinate: placemark.coordinate) {
                            Label(placemark.name, systemImage: "star")
                        }
                        .tint(.yellow)
                    } else {
                        Marker(coordinate: placemark.coordinate) {
                            Label(placemark.name, systemImage: placemark.name == "Starting point" ?
                                  viewModel.circularRoute ? "point.forward.to.point.capsulepath.fill" : "location.north.line" : designRoute && !viewModel.circularRoute && routePlacemarks.last == placemark ? "stop.circle" : "point.topleft.filled.down.to.point.bottomright.curvepath")
                        }
                        .tint(placemark.name == "Starting point" ? .green : designRoute && !viewModel.circularRoute && routePlacemarks.last == placemark ? .red : .blue)
                    }
                }.tag(placemark)
            }
            ForEach(listPoisPlacemarks, id: \.self) { placemark in
                Marker(coordinate: placemark.coordinate) {
                    if pointsOfInterest[poiSelectedIndex].name == PointOfInterestModel.cafe.name {
                        Label(placemark.name, systemImage: "cup.and.saucer.fill")
                    } else if pointsOfInterest[poiSelectedIndex].name == PointOfInterestModel.gasStation.name {
                        Label(placemark.name, systemImage: "flame")
                    } else if pointsOfInterest[poiSelectedIndex].name == PointOfInterestModel.hotel.name {
                        Label(placemark.name, systemImage: "house")
                    } else if pointsOfInterest[poiSelectedIndex].name == PointOfInterestModel.mechanic.name {
                        Label(placemark.name, systemImage: "figure.outdoor.cycle")
                    }
                }
                .tint(.green)
                .tag(placemark)
            }
            ForEach(routePointsOfInterest, id: \.self) { placemark in
                Marker(coordinate: placemark.coordinate) {
                    if placemark.type == PointOfInterestModel.cafe.name {
                        Label(placemark.name, systemImage: "cup.and.saucer.fill")
                    } else if placemark.type == PointOfInterestModel.gasStation.name {
                        Label(placemark.name, systemImage: "flame")
                    } else if placemark.type == PointOfInterestModel.hotel.name {
                        Label(placemark.name, systemImage: "house")
                    } else if placemark.type == PointOfInterestModel.mechanic.name {
                        Label(placemark.name, systemImage: "figure.outdoor.cycle")
                    }
                }
                .tint(.green)
                .tag(placemark)
            }
            if !viewModel.routeSegments.isEmpty, routeDisplaying {
                Group {
                    ForEach(viewModel.routeSegments, id: \.self) { routeSegment in
                        MapPolyline(routeSegment.polyline)
                            .stroke(Color.appSecondary, lineWidth: 4)
                    }
                }
            }
        }
        .task(id: selectedPointOfInterest) {
            guard !routePointsOfInterest.contains(where: { $0 == selectedPointOfInterest }) else {
                return
            }
            showPoiSelectedAlert = selectedPointOfInterest != nil
        }
    }

    @ViewBuilder var poisPickerView: some View {
        Picker("Select a Point of Interest", selection: $poiSelectedIndex) {
            ForEach(0..<pointsOfInterest.count, id: \.self) { index in
                HStack {
                    Text(pointsOfInterest[index].name)
                        .font(.headline)
                }
            }
        }
        .background(Color.white.opacity(0.7))
        .pickerStyle(WheelPickerStyle())
        .frame(height: 200)
        .onChange(of: poiSelectedIndex) {
            Task {
                MapManager.removePointsOfInterestResults(modelContext)
                await MapManager.searchPointsOfInterest(
                    modelContext,
                    searchText: pointsOfInterest[poiSelectedIndex].name,
                    visibleRegion: visibleRegion
                )
            }
        }
    }

    @ViewBuilder var bottomSafeAreaView: some View {
        HStack {
            VStack {
                if !fetchingRoute, routeDisplaying {
                    HStack(spacing: 20) {
                        Button("Create the route", systemImage: "plus.circle") {
                            designRoute = true
                        }
                        Button("Discard the route", systemImage: "minus.circle") {
                            MapManager.removeSearchResults(modelContext)
                            routeDisplaying = false
                            viewModel.removeRoute()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .fixedSize(horizontal: true, vertical: false)
                } else if !fetchingRoute {
                    Button("Calculate the route", systemImage: "paperplane.circle") {
                        Task { @MainActor in
                            fetchingRoute = true
                            if (viewModel.circularRoute ? routePlacemarks.count + 1 : routePlacemarks.count) != viewModel.routeSegments.count {
                                await viewModel.fetchRoute()
                            }
                            fetchingRoute = false
                        }
                    }
                    .disabled(routePlacemarks.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            Spacer()
            if !routeDisplaying, !fetchingRoute {
                VStack {
                    if !searchPlacemarks.isEmpty {
                        Button {
                            MapManager.removeSearchResults(modelContext)
                            viewModel.routeSegments = []
                            viewModel.setStartingPlacemark(nil)
                            startingPlacemark = nil
                            viewModel.setRoutePlacemarks([])
                            routePlacemarks = []
                        } label: {
                            Image(systemName: "mappin.slash")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    MapUserLocationButton(scope: mapScope)
                    MapCompass(scope: mapScope)
                        .mapControlVisibility(.visible)
                    MapPitchToggle(scope: mapScope)
                        .mapControlVisibility(.visible)
                }
                .buttonBorderShape(.circle)
            }
        }
        .padding(20)
    }
}

// MARK: - Private methods
private extension RouteCreatorView {
    func updateCameraPosition() {
        if let userLocation = locationManager.userLocation {
            let userRegion = MKCoordinateRegion(
                center: userLocation.coordinate,
                span: MKCoordinateSpan(
                    latitudeDelta: 0.15,
                    longitudeDelta: 0.15
                )
            )
            withAnimation {
                cameraPosition = .region(userRegion)
            }
        }
    }
}

#Preview {
    RouteCreatorView(viewModel: RouteCreatorViewModel())
        .environment(LocationManager())
        .modelContainer(Route.preview)
}

extension Sequence {
    func asyncForEach(_ operation: (Element) async throws -> Void) async rethrows {
        for element in self {
            try await operation(element)
        }
    }
}
