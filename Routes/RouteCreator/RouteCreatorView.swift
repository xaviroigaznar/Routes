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

    var body: some View {
        MapReader { proxy in
            map
            .onTapGesture { position in
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
            .onMapCameraChange{ context in
                visibleRegion = context.region
            }
            .onAppear {
                MapManager.removeSearchResults(modelContext)
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
                        if let rect = routeSegments.first?.polyline.boundingMapRect {
                            cameraPosition = .rect(rect)
                        }
                    }
                }
            }
            .onChange(of: showRoute) {
                if showRoute {
                    withAnimation {
                        routeDisplaying = true
                        if let rect = routeSegments.first?.polyline.boundingMapRect {
                            cameraPosition = .rect(rect)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if !searchPlacemarks.isEmpty {
                    VStack(alignment: .trailing) {
                        Text("Circular route")
                            .foregroundStyle(Color("AppSecondary"), Color("AccentColor"))
                            .font(.headline)
                        Toggle("", isOn: $circularRoute)
                    }
                    .padding()
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomSafeAreaView
                    .padding(20)
            }
        }
    }

    @ViewBuilder var map: some View {
        Map(position: $cameraPosition) {
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
            if !routeSegments.isEmpty, routeDisplaying {
                Group {
                    ForEach(routeSegments, id: \.self) { routeSegment in
                        MapPolyline(routeSegment.polyline)
                            .stroke(.blue, lineWidth: 6)
                    }
                }
            }
        }
    }

    @ViewBuilder var bottomSafeAreaView: some View {
        HStack {
            VStack {
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($searchFieldFocus)
                    .overlay(alignment: .trailing) {
                        if searchFieldFocus {
                            Button {
                                searchText = ""
                                searchFieldFocus = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .offset(x: -5)
                        }
                    }
                    .onSubmit {
                        Task {
                            await MapManager.searchPlaces(modelContext,
                                                          searchText: searchText,
                                                          visibleRegion: visibleRegion)
                            searchText = ""
                        }
                    }
                if routeDisplaying {
                    VStack {
                        HStack {
                            Button("Clear Route", systemImage: "xmark.circle") {
                                removeRoute()
                            }
                            Button("Show Steps", systemImage: "location.north") {
                                showSteps.toggle()
                            }
                        }
                        Button("Go to route details", systemImage: "hand.point.up.braille") {
                            Task { @MainActor in
                                fetchingRoute = true
                                if (circularRoute ? routePlacemarks.count + 1 : routePlacemarks.count) != routeSegments.count {
                                    await fetchRoute()
                                }
                                designRoute.toggle()
                                fetchingRoute = false
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .fixedSize(horizontal: true, vertical: false)
                } else {
                    HStack(spacing: 20) {
                        if fetchingRoute {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .padding()
                        } else {
                            Button("\(!showRoute ? "Show" : "Hide") the route", systemImage: "hand.point.up.braille") {
                                Task { @MainActor in
                                    fetchingRoute = true
                                    if (circularRoute ? routePlacemarks.count + 1 : routePlacemarks.count) != routeSegments.count {
                                        await fetchRoute()
                                    }
                                    showRoute.toggle()
                                    fetchingRoute = false
                                }
                            }
                            .disabled(routePlacemarks.isEmpty)
                            .buttonStyle(.borderedProminent)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
            }

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
            .padding()
            .buttonBorderShape(.circle)
        }
        .padding(20)
    }

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
        if routePlacemarks.count == 1,
           let startingPlacemark,
           let finishingPlacemark = routePlacemarks.first {
            await fetchFirstRouteSegment(startingPoint: startingPlacemark, to: finishingPlacemark)
        } else {
            await routePlacemarks.enumerated().asyncForEach { index, routePoint in
                if index == 0, let startingPlacemark = routePlacemarks.first {
                    await fetchIntermediateRouteSegment(from: startingPlacemark, to: routePoint)
                } else {
                    await fetchIntermediateRouteSegment(from: routePlacemarks[index - 1], to: routePoint)
                }
            }
        }
        if circularRoute, let startingPoint = routePlacemarks.last, let finishPoint = startingPlacemark {
            await fetchCircularRouteLastSegment(from: startingPoint, to: finishPoint)
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
