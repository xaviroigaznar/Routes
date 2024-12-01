//
//  RouteCreatorViewModel.swift
//  Routes
//
//  Created by Xavi Roig Aznar on 28/11/24.
//

import Combine
import MapKit

class RouteCreatorViewModel: ObservableObject {
    @Published var showRoute = false
    @Published var circularRoute = true
    @Published var routeSegments: [MKRoute] = []

    private var startingPlacemark: Placemark?
    private var routePlacemarks: [RouteIntermediatePlacemark] = []

    func setStartingPlacemark(_ startingPlacemark: Placemark?) {
        self.startingPlacemark = startingPlacemark
    }

    func setRoutePlacemarks(_ routePlacemarks: [RouteIntermediatePlacemark]) {
        self.routePlacemarks = routePlacemarks
    }

    @MainActor
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
        showRoute = true
    }

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
    func removeRoute() {
        showRoute = false
        routeSegments = []
        startingPlacemark = nil
        routePlacemarks = []
    }

    @MainActor
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
