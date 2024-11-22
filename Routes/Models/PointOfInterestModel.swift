//
//  PointOfInterestModel.swift
//  Routes
//
//  Created by Xavi Roig Aznar on 22/11/24.
//

import Foundation

final class PointOfInterestModel {
    let type: PoiType
    let name: String

    enum PoiType {
        case cafe
        case gasStation
        case hotel
        case mechanic
    }

    private init(type: PoiType, name: String) {
        self.type = type
        self.name = name
    }

    public static var cafe: PointOfInterestModel {
        PointOfInterestModel(type: .cafe, name: "Cafetería")
    }

    public static var gasStation: PointOfInterestModel {
        PointOfInterestModel(type: .gasStation, name: "Gasolinera")
    }

    public static var hotel: PointOfInterestModel {
        PointOfInterestModel(type: .hotel, name: "Hotel")
    }

    public static var mechanic: PointOfInterestModel {
        PointOfInterestModel(type: .mechanic, name: "Taller de bicis")
    }
}
