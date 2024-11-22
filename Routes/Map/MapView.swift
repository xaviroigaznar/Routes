//
//  ContentView.swift
//  Routes
//
//  Created by Xavi Roig Aznar on 2/11/24.
//

import MapKit
import SwiftUI
import SwiftData

struct MapView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationManager.self) var locationManager
    @Query private var listPlacemarks: [Placemark]
    @Query private var listPoisPlacemarks: [PointOfInterestPlacemark]
    @Query(filter: #Predicate<Placemark> {$0.route == nil}) private var searchPlacemarks: [Placemark]

    @State private var visibleRegion: MKCoordinateRegion?
    @State private var selectedPlacemark: Placemark?
    @State private var selectedPlacemarkId: UUID?
    @State var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State var routes = [Route]()

    // Search
    @State private var searchText = ""
    @FocusState private var searchFieldFocus: Bool

    // Route
    @State private var showRoute = false
    @State private var routeDisplaying = false
    @State private var route: MKRoute?
    @State private var routeDestination: MKMapItem?
    @State private var travelInterval: TimeInterval?
    @State private var showSteps = false
    @Namespace private var mapScope
    @State private var mapStyleConfig = MapStyleConfig()
    @State private var pickMapStyle = false

    // Track
    @State private var showTrack = false

    // Points of Interest
    @State private var showPoisPicker = false
    @State private var selectedPointOfInterest: PointOfInterestPlacemark?
    @State private var poiSelectedIndex = 0
    private var pointsOfInterest: [PointOfInterestModel] = [.cafe, .gasStation, .hotel, .mechanic]

    // Bindings
    var isPlacemarkSelected: Binding<Bool> {
        Binding(
            get: { selectedPlacemark != nil },
            set: { _ in }
        )
    }

    var body: some View {
        VStack {
            MapReader { proxy in
                mapView
                    .alert("What do you want?", isPresented: isPlacemarkSelected) {
                        Button("Show track") {
                            showTrack = true
                        }
                        Button("Search Points of Interest during the route") {
                            showPoisPicker = true
                        }
                        Button("Dismiss", role: .cancel) {
                            selectedPlacemark = nil
                        }
                    }
                    .sheet(isPresented: $showTrack) {
                        RouteTrackView(selectedPlacemark: selectedPlacemark, cameraPosition: $cameraPosition)
                            .presentationDetents([.large])
                    }
                    .onMapCameraChange { context in
                        visibleRegion = context.region
                    }
                    .onAppear {
                        MapManager.removeSearchResults(modelContext)
                        updateCameraPosition()
                    }
                    .mapStyle(mapStyleConfig.mapStyle)
                    .task(id: selectedPlacemark) {
                        if selectedPlacemark != nil {
                            routeDisplaying = false
                            showRoute = false
                            route = nil
                            await fetchRoute()
                        }
                    }
                    .task(id: selectedPlacemarkId) {
                        if selectedPlacemark == nil {
                            selectedPlacemark = listPlacemarks.first { placemark in
                                placemark.uuid == selectedPlacemarkId
                            }
                        }
                        selectedPointOfInterest = listPoisPlacemarks.first { placemark in
                            placemark.uuid == selectedPlacemarkId
                        }
                        if let selectedPointOfInterest {
                            selectedPlacemark?.route?.pointOfInterestPlacemarks.append(selectedPointOfInterest)
                        }
                    }
                    .onChange(of: showRoute) {
                        selectedPlacemark = nil
                        if showRoute {
                            withAnimation {
                                routeDisplaying = true
                                if let rect = route?.polyline.boundingMapRect {
                                    cameraPosition = .rect(rect)
                                }
                            }
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        safeAreaInsetView
                    }
            }
            if showPoisPicker {
                poisPickerView
            }
        }
    }
}

// MARK: - Inner Views
private extension MapView {
    @ViewBuilder var mapView: some View {
        Map(position: $cameraPosition, selection: $selectedPlacemarkId) {
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
                            Marker(placemark.name, coordinate: placemark.coordinate)
                        }
                    }.tag(placemark.uuid)
                } else {
                    if let routeDestination {
                        Marker(item: routeDestination)
                            .tint(.green)
                    }
                }
            }
            ForEach(listPoisPlacemarks, id: \.self) { placemark in
                Marker(coordinate: placemark.coordinate) {
                    Label(placemark.name, systemImage: "star")
                }
                .tint(.green)
                .tag(placemark.uuid)
            }
            if let route, routeDisplaying {
                MapPolyline(route.polyline)
                    .stroke(.blue, lineWidth: 6)
            }
        }
    }

    @ViewBuilder var poisPickerView: some View {
        NavigationView {
            Picker("Select a Point of Interest", selection: $poiSelectedIndex) {
                ForEach(0..<pointsOfInterest.count, id: \.self) { index in
                    HStack {
                        Text(pointsOfInterest[index].name)
                            .font(.headline)
                    }
                }
            }
            .pickerStyle(WheelPickerStyle())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showPoisPicker = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showPoisPicker = false
                        Task {
                            await MapManager.searchPointsOfInterest(
                                modelContext,
                                searchText: pointsOfInterest[poiSelectedIndex].name,
                                visibleRegion: visibleRegion
                            )
                            poiSelectedIndex = 0
                        }
                    }
                }
            }
        }
        .frame(height: 200)
    }

    @ViewBuilder var safeAreaInsetView: some View {
        HStack {
            Spacer()
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
                                            Text("Bike \(MapManager.distance(meters: route.steps[idx].distance))")
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
            }
            VStack(alignment: .trailing) {
                if !searchPlacemarks.isEmpty {
                    Button {
                        MapManager.removeSearchResults(modelContext)
                    } label: {
                        Image(systemName: "mappin.slash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                Button {
                    pickMapStyle.toggle()
                } label: {
                    Image(systemName: "globe.americas.fill")
                        .imageScale(.large)
                }
                .padding(8)
                .background(.thickMaterial)
                .clipShape(.circle)
                .sheet(isPresented: $pickMapStyle) {
                    MapStyleView(mapStyleConfig: $mapStyleConfig)
                        .presentationDetents([.height(275)])
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
        .padding()
    }
}

// MARK: - Private methods
private extension MapView {
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
        if let userLocation = locationManager.userLocation, let selectedPlacemark {
            let request = MKDirections.Request()
            let sourcePlacemark = MKPlacemark(coordinate: userLocation.coordinate)
            let routeSource = MKMapItem(placemark: sourcePlacemark)
            let destinationPlacemark = MKPlacemark(coordinate: selectedPlacemark.coordinate)
            routeDestination = MKMapItem(placemark: destinationPlacemark)
            routeDestination?.name = selectedPlacemark.name
            request.source = routeSource
            request.tollPreference = .avoid
            request.highwayPreference = .avoid
            request.destination = routeDestination
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
        selectedPlacemark = nil
        updateCameraPosition()
    }
}

#Preview {
    MapView()
        .environment(LocationManager())
        .modelContainer(Route.preview)
}
