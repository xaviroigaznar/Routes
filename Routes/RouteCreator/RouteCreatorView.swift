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
    @Query private var listPlacemarks: [Placemark]
    @Query(filter: #Predicate<Placemark> {$0.route == nil}) private var searchPlacemarks: [Placemark]

    @State private var visibleRegion: MKCoordinateRegion?
    @State var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    // Search
    @State private var searchText = ""
    @FocusState private var searchFieldFocus: Bool

    // Route
    @State private var startingPlacemark: Placemark?
    @State private var routePlacemarks: [Placemark] = []
    @State private var showDetail = false
    @State private var circularRoute = true
    @State private var designRoute = false
    @State private var fetchingRoute = false
    @State private var showRoute = false
    @State private var routeDisplaying = false
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
                    let placemark: Placemark
                    if startingPlacemark == nil  {
                        placemark = Placemark(name: "Starting point",
                                              address: "",
                                              latitude: coordinate.latitude,
                                              longitude: coordinate.longitude)
                        startingPlacemark = placemark
                    } else {
                        placemark = Placemark(name: "Route point \(routePlacemarks.count + 1)",
                                              address: "",
                                              latitude: coordinate.latitude,
                                              longitude: coordinate.longitude)
                        routePlacemarks.append(placemark)
                    }
                    modelContext.insert(placemark)
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
                    startPlacemark: startingPlacemark,
                    routeSegments: routeSegments,
                    showRoute: $showRoute,
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
            ForEach(listPlacemarks, id: \.self) { placemark in
                if !showRoute {
                    Group {
                        if placemark.route != nil {
                            Marker(coordinate: placemark.coordinate) {
                                Label(placemark.name, systemImage: "star")
                            }
                            .tint(.yellow)
                        } else {
                            Marker(coordinate: placemark.coordinate) {
                                Label(placemark.name, systemImage: placemark.name == "Starting point" ?
                                      circularRoute ? "point.forward.to.point.capsulepath.fill" : "location.north.line" : designRoute && !circularRoute && listPlacemarks.last == placemark ? "stop.circle" : "point.topleft.filled.down.to.point.bottomright.curvepath")
                            }
                            .tint(placemark.name == "Starting point" ? .green : designRoute && !circularRoute && listPlacemarks.last == placemark ? .red : .blue)
                        }
                    }.tag(placemark)
                } else {
                    if let routeDestination {
                        Marker(item: routeDestination)
                            .tint(.green)
                    }
                }
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
                            if let placemark = await MapManager.getPlaces(searchText: searchText,
                                                                          visibleRegion: visibleRegion) {
                                let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: placemark.latitude,
                                                                                               longitude: placemark.longitude),
                                                                span: MKCoordinateSpan(latitudeDelta: 0.15,
                                                                                       longitudeDelta: 0.15))
                                cameraPosition = .region(region)
                            }
                            searchText = ""
                        }
                    }
                if routeDisplaying {
                    HStack {
                        Button("Clear Route", systemImage: "xmark.circle") {
                            removeRoute()
                        }
                        .buttonStyle(.borderedProminent)
                        .fixedSize(horizontal: true, vertical: false)
                        Button("Show Steps", systemImage: "location.north") {
                            showSteps.toggle()
                        }
                        .buttonStyle(.borderedProminent)
                        .fixedSize(horizontal: true, vertical: false)
                        .sheet(isPresented: $showSteps) {
                            if !routeSegments.isEmpty {
                                NavigationStack {
//                                    List {
//                                        HStack {
//                                            Image(systemName: "mappin.circle.fill")
//                                                .foregroundStyle(.red)
//                                            Text("From my location")
//                                            Spacer()
//                                        }
//                                        ForEach(1..<route.steps.count, id: \.self) { idx in
//                                            VStack(alignment: .leading) {
//                                                Text("Ride \(MapManager.distance(meters: route.steps[idx].distance))")
//                                                    .bold()
//                                                Text(" - \(route.steps[idx].instructions)")
//                                            }
//                                        }
//                                    }
//                                    .listStyle(.plain)
//                                    .navigationTitle("Steps")
//                                    .navigationBarTitleDisplayMode(.inline)
                                }
                            }
                        }
                    }
                } else {
                    HStack(spacing: 20) {
                        if fetchingRoute {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .padding()
                        } else {
                            VStack {
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
                            .disabled(startingPlacemark == nil && searchPlacemarks.isEmpty)
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
        if routePlacemarks.count == 1, let startingPlacemark, let finishPoint = routePlacemarks.first {
            await fetchRouteSegment(startingPoint: startingPlacemark, finishPoint: finishPoint)
        } else {
            await routePlacemarks.enumerated().asyncForEach { index, routePoint in
                if index == 0, let startingPlacemark {
                    await fetchRouteSegment(startingPoint: startingPlacemark, finishPoint: routePoint)
                } else {
                    await fetchRouteSegment(startingPoint: routePlacemarks[index - 1], finishPoint: routePoint)
                }
            }
        }
        if circularRoute, let startingPoint = routePlacemarks.last, let finishPoint = startingPlacemark {
            await fetchRouteSegment(startingPoint: startingPoint, finishPoint: finishPoint)
        }
//        showRoute = true
    }

    func fetchRouteSegment(startingPoint: Placemark, finishPoint: Placemark) async {
        let request = MKDirections.Request()
        request.tollPreference = .avoid
        request.highwayPreference = .avoid
        request.transportType = .automobile
        let sourcePlacemark = MKPlacemark(coordinate: startingPoint.coordinate)
        let routeSource = MKMapItem(placemark: sourcePlacemark)
        let destinationPlacemark = MKPlacemark(coordinate: finishPoint.coordinate)
        routeDestination = MKMapItem(placemark: destinationPlacemark)
        routeDestination?.name = finishPoint.name
        request.source = routeSource
        request.destination = routeDestination
        let directions = MKDirections(request: request)
        let result = try? await directions.calculate()
        if let routeSegment = result?.routes.first {
            routeSegments.append(routeSegment)
            travelInterval = routeSegment.expectedTravelTime
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
