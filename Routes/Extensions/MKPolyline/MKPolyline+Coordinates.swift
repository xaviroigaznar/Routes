//
//  MKPolyline+Coordinates.swift
//  Routes
//
//  Created by Xavi Roig Aznar on 27/11/24.
//

import MapKit

extension MKPolyline {
    /// Helper to extract coordinates from an MKPolyline
    var coordinates: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}
