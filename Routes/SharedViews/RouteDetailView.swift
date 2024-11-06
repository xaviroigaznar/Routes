//
//  RouteDetailView.swift
//  Routes
//
//  Created by Xavi Roig Aznar on 5/11/24.
//

import SwiftUI
import MapKit
import SwiftData

struct RouteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    var route: Route?
    var startPlacemark: Placemark?
    var routeSegments: [MKRoute]
    @Binding var showRoute: Bool
    @Binding var cameraPosition: MapCameraPosition

    @State private var name = ""
    @State private var startAddress = ""
    @State private var finishAddress = ""

    @State private var lookaroundScene: MKLookAroundScene?

    var isChanged: Bool {
        guard let startPlacemark else { return false }
        return name != startPlacemark.name || startAddress != startPlacemark.address
    }

    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading) {
                    TextField("Name", text: $name)
                        .font(.title)
                    TextField("Start address", text: $startAddress, axis: .vertical)
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
            Map(position: $cameraPosition) {
                UserAnnotation()
                if !routeSegments.isEmpty {
                    Group {
                        ForEach(routeSegments, id: \.self) { routeSegment in
                            MapPolyline(routeSegment.polyline)
                                .stroke(.blue, lineWidth: 6)
                        }
                    }
                }
            }
            .frame(height: 200)
            .padding()
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
                    HStack {
                        Button("Open in maps", systemImage: "map") {
                            if let startPlacemark {
                                let placemark = MKPlacemark(coordinate: startPlacemark.coordinate)
                                let mapItem = MKMapItem(placemark: placemark)
                                mapItem.name = startPlacemark.name
                                mapItem.openInMaps()
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        Button("Show Route", systemImage: "location.north") {
                            showRoute.toggle()
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(.bordered)
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
        route: route,
        startPlacemark: startPlacemark,
        routeSegments: [],
        showRoute: .constant(false),
        cameraPosition: .constant(.userLocation(fallback: .automatic))
    )
}

#Preview("TripMap Tab") {
    let container = Route.preview
    let fetchDescriptor = FetchDescriptor<Placemark>()
    let placemarks = try! container.mainContext.fetch(fetchDescriptor)
    let startPlacemark = placemarks[0]
    return RouteDetailView(
        startPlacemark: startPlacemark,
        routeSegments: [],
        showRoute: .constant(false),
        cameraPosition: .constant(.userLocation(fallback: .automatic))
    )
}

