//
//  RouteWithPlacemarksMap.swift
//  Routes
//
//  Created by Xavi Roig Aznar on 25/11/24.
//

import SwiftUI
import MapKit

struct RouteWithPlacemarksMap: UIViewRepresentable {
    var polylineCoordinates: [CLLocationCoordinate2D]
    var annotations: [CLLocationCoordinate2D]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator

        // Configure the map view
        mapView.mapType = .standard

        // Add the polyline
        let polyline = MKPolyline(coordinates: polylineCoordinates, count: polylineCoordinates.count)
        mapView.addOverlay(polyline)

        // Add annotations (placemarks)
        annotations.forEach { coordinate in
            let annotation = MKPointAnnotation()
            annotation.coordinate = coordinate
            mapView.addAnnotation(annotation)
        }

        // Center the map
        if let firstCoordinate = polylineCoordinates.first {
            mapView.setRegion(MKCoordinateRegion(
                center: firstCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            ), animated: true)
        }

        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // You can update the map view if needed here.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RouteWithPlacemarksMap

        init(_ parent: RouteWithPlacemarksMap) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .blue
                renderer.lineWidth = 3
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
