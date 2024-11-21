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
    @Query(filter: #Predicate<Placemark> {$0.route == nil}) private var searchPlacemarks: [Placemark]

    @State private var visibleRegion: MKCoordinateRegion?
    @State private var selectedPlacemark: Placemark?
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
    @State private var pointOfInterest: String?
    @State private var poiSelectedIndex = 0
    private var pointsOfInterest = ["Cafetería", "Gasolinera", "Taller de bicis"]

    // Bindings
    var isPlacemarkSelected: Binding<Bool> {
        Binding(
            get: { selectedPlacemark != nil },
            set: { newValue in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !newValue {
                        selectedPlacemark = nil
                    }
                }
            }
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
                    .onChange(of: poiSelectedIndex) {
                        print("POI Selected \(pointsOfInterest[poiSelectedIndex])")
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
        Map(position: $cameraPosition, selection: $selectedPlacemark) {
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
    }

    @ViewBuilder var poisPickerView: some View {
        NavigationView {
            Picker("Select a Point of Interest", selection: $poiSelectedIndex) {
                ForEach(0..<pointsOfInterest.count, id: \.self) { index in
                    HStack {
                        Text(pointsOfInterest[index])
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
                    }
                }
            }
        }
        .frame(height: 200)
    }

    @ViewBuilder var safeAreaInsetView: some View {
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
                            await MapManager.searchPlaces(
                                modelContext,
                                searchText: searchText,
                                visibleRegion: visibleRegion
                            )
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
