//
//  PointOfInterestPlacemark.swift
//  Routes
//
//  Created by Xavi Roig Aznar on 15/11/24.
//

import SwiftData
import MapKit

@Model
class PointOfInterestPlacemark {
    let uuid = UUID()
    var type: String
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    @Relationship(deleteRule: .cascade)
    var route: Route?

    init(type: String, name: String, address: String, latitude: Double, longitude: Double) {
        self.type = type
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }

    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }
}
