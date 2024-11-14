//
//  RouteDetailView.swift
//  Routes
//
//  Created by Xavi Roig Aznar on 5/11/24.
//

import Charts
import MapKit
import SwiftData
import SwiftUI

struct RouteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var route: Route?
    var startPlacemark: Placemark?
    var routePlacemarks: [Placemark]
    var routeSegments: [MKRoute]
    @Binding var showRoute: Bool
    @Binding var circularRoute: Bool
    @Binding var cameraPosition: MapCameraPosition

    @State private var name = ""
    @State private var startAddress = ""
    @State private var finishAddress = ""

    @State private var unevenness: Double = 0
    @State private var elevations: [Double] = []
    @State private var kilometers: [Double] = []
    @State private var fetchingUnevenness = false

    @State private var lookaroundScene: MKLookAroundScene?

    var isChanged: Bool {
        guard let startPlacemark else { return false }
        return name != startPlacemark.name || startAddress != startPlacemark.address
    }

    var distance: String {
        var distance: Double = 0
        routeSegments.forEach { routeSegment in
            distance += routeSegment.distance.magnitude
        }
        return String(format: "%.2f", distance / 1000)
    }

    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading) {
                    TextField("Name", text: $name)
                        .font(.title)
                    TextField("Start address", text: $startAddress, axis: .vertical)
                    Text("Distance: \(distance)km")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor, .appSecondary)
                    if isChanged {
                        Button("Update") {
                            startPlacemark?.name = name
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            startPlacemark?.address = startAddress
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                Spacer()
                Button {
                   dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.large)
                        .foregroundStyle(.gray)
                }
            }
            if unevenness != 0 {
                Text("Unevennesss: \(String(format: "%.2f", unevenness))m+")
                    .font(.headline)
                    .foregroundStyle(.appSecondary, Color.accentColor)
                Chart {
                    ForEach(Array(elevations.enumerated()), id: \.1) { index, elevation in
                        BarMark(x: .value("Distance", kilometers[index]), y: .value("Elevation", elevation))
                    }
                }
                .frame(height: 200)
                .padding()
            }
            if let lookaroundScene {
                LookAroundPreview(initialScene: lookaroundScene)
                    .frame(height: 200)
                    .padding()
            } else {
                ContentUnavailableView("No preview available", systemImage: "eye.slash")
            }
            HStack {
                Spacer()
                if let route {
                    let inList = (startPlacemark != nil && startPlacemark?.route != nil)
                    Button {
                        if let startPlacemark {
                            if startPlacemark.route == nil {
                                route.placemarks.append(startPlacemark)
                                route.placemarks.append(contentsOf: routePlacemarks)
                            } else {
                                startPlacemark.route = nil
                            }
                            dismiss()
                        }
                    } label: {
                        Label(inList ? "Remove" : "Add", systemImage: inList ? "minus.circle" : "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(inList ? .red : .green)
                    .disabled((name.isEmpty || isChanged))
                } else {
                    if !fetchingUnevenness {
                        HStack {
                            Button("Display unevenness", systemImage: "mountain.2") {
                                fetchingUnevenness = true
                                Task {
                                    try await calculateUnevenness()
                                    fetchingUnevenness = false
                                }
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            Button("Create Route", systemImage: "location.north") {
                                route = Route(name: name,
                                              latitude: startPlacemark?.latitude,
                                              longitude: startPlacemark?.longitude,
                                              distance: Double(distance),
                                              unevenness: unevenness)
                                route?.circularRoute = circularRoute
                                if let startPlacemark {
                                    route?.placemarks.append(startPlacemark)
                                    route?.placemarks.append(contentsOf: routePlacemarks)
                                    startPlacemark.route = route
                                }
                            }
                            .disabled(name.isEmpty)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding()
                            .frame(alignment: .center)
                    }
                }
            }
            Spacer()
        }
        .padding()
        .task(id: startPlacemark) {
            await fetchLookaroundPreview()
        }
        .onAppear {
            if let startPlacemark, route != nil {
                name = startPlacemark.name
                startAddress = startPlacemark.address
            }
        }
    }
}

private extension RouteDetailView {
    func calculateUnevenness() async throws {
        guard routeSegments.count > 0 else {
            return // No unevenness if only one or zero coordinates
        }

        var totalElevationChange: Double = 0
        var totalDistance: Double = 0
        var previousElevation: Double? = nil

        try await routeSegments.enumerated().asyncForEach { index, routeSegment in
            var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: routeSegment.polyline.pointCount)
            routeSegment.polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: routeSegment.polyline.pointCount))
            try await coordinates.enumerated().asyncForEach { index, coordinate in
                if index == 0 {
                    // Insert 0.0 at the start for the initial point
                    kilometers.insert(0.0, at: 0)
                } else {
                    totalDistance += calculateKilometers(from: coordinates[index - 1], to: coordinate)

                    // Append the cumulative distance in kilometers
                    kilometers.append(totalDistance / 1000.0)
                }
                let elevation = try await getElevation(latitude: coordinate.latitude, longitude: coordinate.longitude)

                if let previousElevation = previousElevation, elevation > previousElevation {
                    // Calculate elevation difference between consecutive points
                    let elevationDifference = elevation - previousElevation
                    totalElevationChange += elevationDifference
                }

                // Update previous elevation for the next comparison
                previousElevation = elevation
            }
        }

        unevenness = totalElevationChange
    }

    func calculateKilometers(from startCoordinate: CLLocationCoordinate2D, to finalCoordinate: CLLocationCoordinate2D) -> Double {
        // Convert coordinates to CLLocation to calculate distance between them
        let start = CLLocation(latitude: startCoordinate.latitude, longitude: startCoordinate.longitude)
        let end = CLLocation(latitude: finalCoordinate.latitude, longitude: finalCoordinate.longitude)

        // Calculate the distance between consecutive points
        return start.distance(from: end) // distance in meters
    }

    func getElevation(latitude: Double, longitude: Double) async throws -> Double {
        let apiKey = "AIzaSyC5MyFG43XdKJMV26CP_IWYU1cNPH361rQ"
        // Construct the URL for the Elevation API request
        let urlString = "https://maps.googleapis.com/maps/api/elevation/json?locations=\(latitude),\(longitude)&key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Invalid URL", code: 400, userInfo: nil)
        }

        // Perform the data task with async/await
        let (data, _) = try await URLSession.shared.data(from: url)

        // Decode the JSON response
        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           let results = json["results"] as? [[String: Any]],
           let elevation = results.first?["elevation"] as? Double {
            elevations.append(elevation)
            return elevation
        } else {
            throw NSError(domain: "Parsing error", code: 500, userInfo: nil)
        }
    }

    func fetchLookaroundPreview() async {
        if let startPlacemark {
            lookaroundScene = nil
            let lookaroundRequest = MKLookAroundSceneRequest(coordinate: startPlacemark.coordinate)
            lookaroundScene = try? await lookaroundRequest.scene
        }
    }
}

#Preview("Route Tab") {
    let container = Route.preview
    let fetchDescriptor = FetchDescriptor<Route>()
    let route = try! container.mainContext.fetch(fetchDescriptor)[0]
    let startPlacemark = route.placemarks[0]
    return RouteDetailView(
        route: .constant(route),
        startPlacemark: startPlacemark,
        routePlacemarks: [],
        routeSegments: [],
        showRoute: .constant(false),
        circularRoute: .constant(true),
        cameraPosition: .constant(.userLocation(fallback: .automatic))
    )
}

#Preview("TripMap Tab") {
    let container = Route.preview
    let fetchDescriptor = FetchDescriptor<Placemark>()
    let placemarks = try! container.mainContext.fetch(fetchDescriptor)
    let startPlacemark = placemarks[0]
    return RouteDetailView(
        route: .constant(nil),
        startPlacemark: startPlacemark,
        routePlacemarks: [],
        routeSegments: [],
        showRoute: .constant(false),
        circularRoute: .constant(true),
        cameraPosition: .constant(.userLocation(fallback: .automatic))
    )
}

