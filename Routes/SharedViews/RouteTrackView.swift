//
//  RouteTrackView.swift
//  Routes
//
//  Created by Xavi Roig Aznar on 3/11/24.
//

import SwiftUI
import MapKit
import SwiftData

struct RouteTrackView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedRoute: Route?
    @Binding var cameraPosition: MapCameraPosition

    @State private var routeSegments: [MKRoute] = []
    @State private var fetchingRoute = true

    var body: some View {
        VStack {
            VStack(alignment: .leading) {
                Text(selectedRoute?.startingPlacemark?.name ?? "")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(selectedRoute?.startingPlacemark?.address ?? "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing)
            }
            if !fetchingRoute {
                Map(position: $cameraPosition, bounds: nil, interactionModes: .zoom, scope: nil, content: {
                    Group {
                        ForEach(routeSegments, id: \.self) { routeSegment in
                            MapPolyline(routeSegment.polyline)
                                .stroke(.blue, lineWidth: 6)
                        }
                    }
                })
                .frame(height: 500)
                .padding()
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding()
            }
            Button("Open in maps", systemImage: "map") {
                if let selectedPlacemark = selectedRoute?.startingPlacemark {
                    let placemark = MKPlacemark(coordinate: selectedPlacemark.coordinate)
                    let mapItem = MKMapItem(placemark: placemark)
                    mapItem.name = selectedPlacemark.name
                    mapItem.openInMaps()
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .buttonStyle(.bordered)
        }
        .padding()
        .onAppear {
            Task {
                defer {
                    fetchingRoute = false
                }
                await fetchRoute()
            }
        }
        .onDisappear {
            selectedRoute = nil
        }
    }

    func fetchRoute() async {
        guard let route = selectedRoute else { return }
        if route.routeIntermediatePlacemarks.count == 1,
           let startingPlacemark = route.startingPlacemark,
           let finishingPlacemark = route.routeIntermediatePlacemarks.first {
            await fetchFirstRouteSegment(startingPoint: startingPlacemark, to: finishingPlacemark)
        } else {
            await route.routeIntermediatePlacemarks.enumerated().asyncForEach { index, routePoint in
                if index == 0, let startingPlacemark = route.routeIntermediatePlacemarks.first {
                    await fetchIntermediateRouteSegment(from: startingPlacemark, to: routePoint)
                } else {
                    await fetchIntermediateRouteSegment(from: route.routeIntermediatePlacemarks[index - 1], to: routePoint)
                }
            }
        }
        if route.circularRoute, let startingPoint = route.routeIntermediatePlacemarks.last, let finishPoint = route.startingPlacemark {
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
        let routeDestination = MKMapItem(placemark: destinationPlacemark)
        routeDestination.name = to.name
        request.source = routeSource
        request.destination = routeDestination
        let directions = MKDirections(request: request)
        let result = try? await directions.calculate()
        if let routeSegment = result?.routes.first {
            routeSegments.append(routeSegment)
        }
    }
}

#Preview("Route Tab") {
    let container = Route.preview
    let fetchDescriptor = FetchDescriptor<Route>()
    let selectedRoute = try! container.mainContext.fetch(fetchDescriptor)[0]
    return RouteTrackView(
        selectedRoute: .constant(selectedRoute),
        cameraPosition: .constant(.automatic)
    )
}

#Preview("TripMap Tab") {
    let container = Route.preview
    let fetchDescriptor = FetchDescriptor<Route>()
    let routes = try! container.mainContext.fetch(fetchDescriptor)
    let selectedRoute = routes[0]
    return RouteTrackView(
        selectedRoute: .constant(selectedRoute),
        cameraPosition: .constant(.automatic)
    )
}
