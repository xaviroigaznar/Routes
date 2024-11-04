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
    @State var routes = [Route]()

    // Search
    @State private var searchText = ""
    @FocusState private var searchFieldFocus: Bool

    // Route
    @State private var startingPlacemark: Placemark?
    @State private var routePlacemarks: [Placemark] = []
    @State private var circularRoute = true
    @State private var designRoute = false
    @State private var showRoute = false
    @State private var routeDisplaying = false
    @State private var route: MKRoute?
    @State private var routeDestination: MKMapItem?
    @State private var travelInterval: TimeInterval?
    @State private var showSteps = false
    @Namespace private var mapScope
    @State private var mapStyleConfig = MapStyleConfig()

    var body: some View {
        MapReader { proxy in
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
                if let route, routeDisplaying {
                    MapPolyline(route.polyline)
                        .stroke(.blue, lineWidth: 6)
                }
            }
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
            .task(id: startingPlacemark) {
                if startingPlacemark != nil {
                    routeDisplaying = false
                    showRoute = false
                    route = nil
//                    await fetchRoute()
                }
            }
            .onChange(of: showRoute) {
                startingPlacemark = nil
                if showRoute {
                    withAnimation {
                        routeDisplaying = true
                        if let rect = route?.polyline.boundingMapRect {
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
                                    if let route {
                                        NavigationStack {
                                            List {
                                                HStack {
                                                    Image(systemName: "mappin.circle.fill")
                                                        .foregroundStyle(.red)
                                                    Text("From my location")
                                                    Spacer()
                                                }
                                                ForEach(1..<route.steps.count, id: \.self) { idx in
                                                    VStack(alignment: .leading) {
                                                        Text("Ride \(MapManager.distance(meters: route.steps[idx].distance))")
                                                            .bold()
                                                        Text(" - \(route.steps[idx].instructions)")
                                                    }
                                                }
                                            }
                                            .listStyle(.plain)
                                            .navigationTitle("Steps")
                                            .navigationBarTitleDisplayMode(.inline)
                                        }
                                    }
                                }
                            }
                        } else {
                            Button("Design the route", systemImage: "hand.point.up.braille") {
                                designRoute.toggle()
                            }
                            .disabled(startingPlacemark == nil && searchPlacemarks.isEmpty)
                            .buttonStyle(.borderedProminent)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .padding()
                    VStack {
                        if !searchPlacemarks.isEmpty {
                            Button {
                                MapManager.removeSearchResults(modelContext)
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
            }
        }
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
        if let userLocation = locationManager.userLocation, let startingPlacemark {
            let request = MKDirections.Request()
            let sourcePlacemark = MKPlacemark(coordinate: userLocation.coordinate)
            let routeSource = MKMapItem(placemark: sourcePlacemark)
            let destinationPlacemark = MKPlacemark(coordinate: startingPlacemark.coordinate)
            routeDestination = MKMapItem(placemark: destinationPlacemark)
            routeDestination?.name = startingPlacemark.name
            request.source = routeSource
            request.tollPreference = .avoid
            request.highwayPreference = .avoid
            request.destination = routeDestination
            request.transportType = .automobile
            let directions = MKDirections(request: request)
            let result = try? await directions.calculate()
            route = result?.routes.first
            travelInterval = route?.expectedTravelTime
        }
    }
    
    func removeRoute() {
        routeDisplaying = false
        showRoute = false
        route = nil
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

