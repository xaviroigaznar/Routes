//
//  RouteIntermediatePoint.swift
//  Routes
//
//  Created by Xavi Roig Aznar on 15/11/24.
//

import SwiftData
import MapKit

@Model
class RouteIntermediatePlacemark {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var route: Route?
    
    init(name: String, address: String, latitude: Double, longitude: Double) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }
    
    var coordinate: CLLocationCoordinate2D {
        .init(latitude: latitude, longitude: longitude)
    }
}
