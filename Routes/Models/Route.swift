//
//  Route.swift
//  Routes
//
//  Created by Xavi Roig Aznar on 2/11/24.
//

import MapKit
import SwiftData

@Model
class Route {
    var name: String
    var latitude: Double?
    var longitude: Double?
    var latitudeDelta: Double?
    var longitudeDelta: Double?
    var distance: Double?
    var unevenness: Double?
    @Relationship(deleteRule: .cascade)
    var placemarks: [Placemark] = []

    init(name: String,
         latitude: Double? = nil,
         longitude: Double? = nil,
         latitudeDelta: Double? = nil,
         longitudeDelta: Double? = nil,
         distance: Double? = nil,
         unevenness: Double? = nil) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
        self.distance = distance
        self.unevenness = unevenness
    }

    var region: MKCoordinateRegion? {
        if let latitude, let longitude, let latitudeDelta, let longitudeDelta {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
            )
        } else {
            return nil
        }
    }
}

extension Route {
    @MainActor
    static var preview: ModelContainer {
        let container = try! ModelContainer(
            for: Route.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true
            )
        )

        let paris = Route(
            name: "Paris",
            latitude: 48.856788,
            longitude: 2.351077,
            latitudeDelta: 0.15,
            longitudeDelta: 0.15
        )
        container.mainContext.insert(paris)
        var placeMarks: [Placemark] {
            [
                Placemark(name: "Louvre Museum", address: "93 Rue de Rivoli, 75001 Paris, France", latitude: 48.861950, longitude: 2.336902),
                Placemark(name: "Sacré-Coeur Basilica", address: "Parvis du Sacré-Cœur, 75018 Paris, France", latitude: 48.886634, longitude: 2.343048),
                Placemark(name: "Eiffel Tower", address: "5 Avenue Anatole France, 75007 Paris, France", latitude: 48.858258, longitude: 2.294488),
                Placemark(name: "Moulin Rouge", address: "82 Boulevard de Clichy, 75018 Paris, France", latitude: 48.884134, longitude: 2.332196),
                Placemark(name: "Arc de Triomphe", address: "Place Charles de Gaulle, 75017 Paris, France", latitude: 48.873776, longitude: 2.295043),
                Placemark(name: "Gare Du Nord", address: "Paris, France", latitude: 48.880071, longitude: 2.354977),
                Placemark(name: "Notre Dame Cathedral", address: "6 Rue du Cloître Notre-Dame, 75004 Paris, France", latitude: 48.852972, longitude: 2.350004),
                Placemark(name: "Panthéon", address: "Place du Panthéon, 75005 Paris, France", latitude: 48.845616, longitude: 2.345996),
            ]
        }
        placeMarks.forEach {placemark in
            paris.placemarks.append(placemark)
        }
        return container
    }
}
