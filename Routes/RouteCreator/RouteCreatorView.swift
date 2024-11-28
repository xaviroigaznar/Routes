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
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationManager.self) var locationManager
    @Query(filter: #Predicate<Placemark> {$0.route == nil}) private var searchPlacemarks: [Placemark]
    @Query private var listPoisPlacemarks: [PointOfInterestPlacemark]

    @State private var visibleRegion: MKCoordinateRegion?
    @State var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    // Search
    @State private var searchText = ""
    @FocusState private var searchFieldFocus: Bool

    // Route
    @State private var startingPlacemark: Placemark?
    @State private var routePlacemarks: [RouteIntermediatePlacemark] = []
    @State private var showDetail = false
    @State private var circularRoute = true
    @State private var designRoute = false
    @State private var fetchingRoute = false
    @State private var showRoute = false
    @State private var routeDisplaying = false
    @State private var route: Route?
    @State private var routeSegments: [MKRoute] = []
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
    private var pointsOfInterest: [PointOfInterestModel] = [.cafe, .gasStation, .hotel, .mechanic]

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
                        await updateRoute(with: selectedPointOfInterest)
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
                Toggle("", isOn: $circularRoute)
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
                                startingPlacemark = placemark
                                modelContext.insert(placemark)
                            } else {
                                let placemark = RouteIntermediatePlacemark(name: "Route point \(routePlacemarks.count + 1)",
                                                                           address: "",
                                                                           latitude: coordinate.latitude,
                                                                           longitude: coordinate.longitude)
                                routePlacemarks.append(placemark)
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
                        routeSegments: routeSegments,
                        showRoute: $showRoute,
                        circularRoute: $circularRoute,
                        cameraPosition: $cameraPosition
                    )
                    .presentationDetents([.large])
                }
                .onChange(of: designRoute) {
                    if designRoute {
                        showDetail = (circularRoute ? routePlacemarks.count + 1 : routePlacemarks.count) == routeSegments.count
                        if showDetail {
                            if let startingPlacemarkCoordinates = startingPlacemark?.coordinate {
                                cameraPosition = .region(MKCoordinateRegion(center: startingPlacemarkCoordinates,
                                                                            span: MKCoordinateSpan(latitudeDelta: 0.1,
                                                                                                   longitudeDelta: 0.1)))
                            }
                        }
                    }
                }
                .onChange(of: showRoute) {
                    if showRoute {
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
                    Label(startingPlacemark.name, systemImage: circularRoute ? "point.forward.to.point.capsulepath.fill" : "location.north.line")
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
                                  circularRoute ? "point.forward.to.point.capsulepath.fill" : "location.north.line" : designRoute && !circularRoute && routePlacemarks.last == placemark ? "stop.circle" : "point.topleft.filled.down.to.point.bottomright.curvepath")
                        }
                        .tint(placemark.name == "Starting point" ? .green : designRoute && !circularRoute && routePlacemarks.last == placemark ? .red : .blue)
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
            if !routeSegments.isEmpty, routeDisplaying {
                Group {
                    ForEach(routeSegments, id: \.self) { routeSegment in
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
                            routeSegments = []
                            startingPlacemark = nil
                            routePlacemarks = []
                            routeDisplaying = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .fixedSize(horizontal: true, vertical: false)
                } else if !fetchingRoute {
                    Button("Calculate the route", systemImage: "paperplane.circle") {
                        Task { @MainActor in
                            fetchingRoute = true
                            if (circularRoute ? routePlacemarks.count + 1 : routePlacemarks.count) != routeSegments.count {
                                await fetchRoute()
                            }
                            showRoute = true
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
                            routeSegments = []
                            startingPlacemark = nil
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

    func fetchRoute() async {
        guard let startingPlacemark, let finishingPlacemark = routePlacemarks.first else {
            return
        }
        // Calculate the first route segment (from starting placemark to the first intermediate placemark).
        await fetchFirstRouteSegment(startingPoint: startingPlacemark, to: finishingPlacemark)

        // If there is only one intermediate placemark.
        if routePlacemarks.count == 1 {
            // If the route is circular, calculate the last route segment (from the first intermediate placemark to the starting placemark).
            if circularRoute {
                await fetchCircularRouteLastSegment(from: finishingPlacemark, to: startingPlacemark)
            } else {
                // If the route is not circular, it has only one segment so just return.
                return
            }
        } else {
            // If the route has many intermediate placemarks, calculate the different route segments.
            for index in 1..<routePlacemarks.count {
                await fetchIntermediateRouteSegment(from: routePlacemarks[index - 1], to: routePlacemarks[index])
            }
        }
        if circularRoute, let lastIntermediatePlacemark = routePlacemarks.last {
            await fetchCircularRouteLastSegment(from: lastIntermediatePlacemark, to: startingPlacemark)
        }
    }

    func fetchFirstRouteSegment(startingPoint: Placemark, to: RouteIntermediatePlacemark) async {
        let request = MKDirections.Request()
        request.tollPreference = .avoid
        request.highwayPreference = .avoid
        request.transportType = .automobile
        let sourcePlacemark = MKPlacemark(coordinate: startingPoint.coordinate)
        let routeSource = MKMapItem(placemark: sourcePlacemark)
        let destinationPlacemark = MKPlacemark(coordinate: to.coordinate)
        var routeDestination = MKMapItem(placemark: destinationPlacemark)
        routeDestination.name = to.name
        request.source = routeSource
        request.destination = routeDestination
        let directions = MKDirections(request: request)
        let result = try? await directions.calculate()
        if let routeSegment = result?.routes.first {
            routeSegments.append(routeSegment)
        }
    }

    func fetchIntermediateRouteSegment(from: RouteIntermediatePlacemark, to: RouteIntermediatePlacemark) async {
        let request = MKDirections.Request()
        request.tollPreference = .avoid
        request.highwayPreference = .avoid
        request.transportType = .automobile
        let sourcePlacemark = MKPlacemark(coordinate: from.coordinate)
        let routeSource = MKMapItem(placemark: sourcePlacemark)
        let destinationPlacemark = MKPlacemark(coordinate: to.coordinate)
        var routeDestination = MKMapItem(placemark: destinationPlacemark)
        routeDestination.name = to.name
        request.source = routeSource
        request.destination = routeDestination
        let directions = MKDirections(request: request)
        let result = try? await directions.calculate()
        if let routeSegment = result?.routes.first {
            routeSegments.append(routeSegment)
        }
    }

    func fetchCircularRouteLastSegment(from: RouteIntermediatePlacemark, to: Placemark) async {
        let request = MKDirections.Request()
        request.tollPreference = .avoid
        request.highwayPreference = .avoid
        request.transportType = .automobile
        let sourcePlacemark = MKPlacemark(coordinate: from.coordinate)
        let routeSource = MKMapItem(placemark: sourcePlacemark)
        let destinationPlacemark = MKPlacemark(coordinate: to.coordinate)
        var routeDestination = MKMapItem(placemark: destinationPlacemark)
        routeDestination.name = to.name
        request.source = routeSource
        request.destination = routeDestination
        let directions = MKDirections(request: request)
        let result = try? await directions.calculate()
        if let routeSegment = result?.routes.first {
            routeSegments.append(routeSegment)
        }
    }

    func removeRoute() {
        MapManager.removeSearchResults(modelContext)
        routeDisplaying = false
        showRoute = false
        routeSegments = []
        startingPlacemark = nil
        routePlacemarks = []
        updateCameraPosition()
    }

    func updateRoute(with placemark: PointOfInterestPlacemark) async {
        let nearestPlacemarkIndex = findNearestPlacemarkIndex(to: placemark.coordinate)

        var firstNewRouteSegment: MKRoute?
        var secondNewRouteSegment: MKRoute?

        // Create a directions request
        let request = MKDirections.Request()
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: placemark.coordinate))
        request.transportType = .automobile
        if let nearestPlacemarkIndex {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: routePlacemarks[nearestPlacemarkIndex].coordinate))
        } else if let startingPlacemark {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: startingPlacemark.coordinate))
        }
        let firstDirections = MKDirections(request: request)
        let firstResult = try? await firstDirections.calculate()
        if let routeSegment = firstResult?.routes.first {
            firstNewRouteSegment = routeSegment
        }
        if let nearestPlacemarkIndex {
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: routePlacemarks[nearestPlacemarkIndex + 1].coordinate))
        } else if let firstIntermediatePlacemark = routePlacemarks.first {
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: firstIntermediatePlacemark.coordinate))
        }
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: placemark.coordinate))
        let secondDirections = MKDirections(request: request)
        let secondResult = try? await secondDirections.calculate()
        if let routeSegment = secondResult?.routes.first {
            secondNewRouteSegment = routeSegment
        }
        if let firstNewRouteSegment, let secondNewRouteSegment {
            routeSegments.remove(at: nearestPlacemarkIndex ?? 0)
            routeSegments.insert(firstNewRouteSegment, at: nearestPlacemarkIndex ?? 0)
            routeSegments.insert(secondNewRouteSegment, at: (nearestPlacemarkIndex ?? 0) + 1)
        }
    }

    func findNearestPlacemarkIndex(to coordinate: CLLocationCoordinate2D) -> Int? {
        let selectedLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var routeLocations: [CLLocation] = []
        if let startingPlacemark {
            routeLocations = [CLLocation(latitude: startingPlacemark.coordinate.latitude, longitude: startingPlacemark.coordinate.longitude)]
        }
        routeLocations.append(contentsOf: routePlacemarks.map { CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) })

        // Calculate distances and find the nearest placemark
        let distances = routeLocations.map { selectedLocation.distance(from: $0) }
        if let minIndex = distances.firstIndex(of: distances.min() ?? 0) {
            return minIndex == 0 ? nil : minIndex - 1
        }

        return nil
    }
}

#Preview {
    RouteCreatorView()
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
