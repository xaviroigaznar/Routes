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
    @Query(filter: #Predicate<Route> { $0.startingPlacemark != nil }) private var listRoutes: [Route]
    @Query(filter: #Predicate<Placemark> {$0.route == nil}) private var searchPlacemarks: [Placemark]

    @State private var visibleRegion: MKCoordinateRegion?
    @State private var selectedRoute: Route?
    @State private var isRouteSelected = false
    @State private var selectedPlacemarkId: UUID?
    @State var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State var routes = [Route]()

    // Search
    @State private var searchText = ""
    @FocusState private var searchFieldFocus: Bool

    // Route
    @Namespace private var mapScope
    @State private var mapStyleConfig = MapStyleConfig()
    @State private var pickMapStyle = false

    // Track
    @State private var showTrack = false

    var body: some View {
        VStack {
            MapReader { proxy in
                mapView
                    .alert("What do you want?", isPresented: $isRouteSelected) {
                        Button("Show track") {
                            showTrack = true
                        }
                        Button("Dismiss", role: .cancel) {
                            selectedRoute = nil
                        }
                    }
                    .sheet(isPresented: $showTrack) {
                        RouteTrackView(selectedRoute: selectedRoute, cameraPosition: $cameraPosition)
                            .presentationDetents([.large])
                    }
                    .onMapCameraChange { context in
                        visibleRegion = context.region
                    }
                    .onAppear {
                        MapManager.removeSearchResults(modelContext)
                        updateCameraPosition()
                    }
                    .onDisappear {
                        selectedRoute = nil
                    }
                    .mapStyle(mapStyleConfig.mapStyle)
                    .task(id: selectedPlacemarkId) {
                        if selectedRoute == nil {
                            selectedRoute = listRoutes.first { route in
                                route.startingPlacemark?.uuid == selectedPlacemarkId
                            }
                            if selectedRoute != nil {
                                isRouteSelected = true
                            }
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        safeAreaInsetView
                    }
            }
        }
    }
}

// MARK: - Inner Views
private extension MapView {
    @ViewBuilder var mapView: some View {
        Map(position: $cameraPosition, selection: $selectedPlacemarkId) {
            UserAnnotation()
            ForEach(listRoutes, id: \.self) { route in
                if let placemark = route.startingPlacemark {
                    Marker(coordinate:  placemark.coordinate) {
                        Label(placemark.name, systemImage: "star")
                    }
                    .tint(.yellow)
                    .tag(placemark.uuid)
                }
            }
        }
    }

    @ViewBuilder var safeAreaInsetView: some View {
        HStack {
            Spacer()
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
}

#Preview {
    MapView()
        .environment(LocationManager())
        .modelContainer(Route.preview)
}
