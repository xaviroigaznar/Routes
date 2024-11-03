//
//  LocationDetailView.swift
//  Routes
//
//  Created by Xavi Roig Aznar on 3/11/24.
//

import SwiftUI
import MapKit
import SwiftData

struct LocationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    var route: Route?
    var selectedPlacemark: Placemark?
    @Binding var showRoute: Bool
    @Binding var travelInterval: TimeInterval?
    @Binding var transportType: MKDirectionsTransportType

    var travelTime: String? {
        guard let travelInterval else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        return formatter.string(from: travelInterval)
    }

    @State private var name = ""
    @State private var address = ""

    @State private var lookaroundScene: MKLookAroundScene?

    var isChanged: Bool {
        guard let selectedPlacemark else { return false }
        return (name != selectedPlacemark.name || address != selectedPlacemark.address)
    }

    var body: some View {
        VStack {
            HStack {
                VStack(alignment: .leading) {
                    if route != nil {
                        TextField("Name", text: $name)
                            .font(.title)
                        TextField("address", text: $address, axis: .vertical)
                        if isChanged {
                            Button("Update") {
                                selectedPlacemark?.name = name
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                selectedPlacemark?.address = address
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        Text(selectedPlacemark?.name ?? "")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(selectedPlacemark?.address ?? "")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.trailing)
                    }
                    if route == nil {
                        HStack {
                            Button {
                                transportType = .automobile
                            }label: {
                                Image(systemName: "car")
                                    .symbolVariant(transportType == .automobile ? .circle : .none)
                                    .imageScale(.large)
                            }
                            Button {
                                transportType = .walking
                            }label: {
                                Image(systemName: "figure.walk")
                                    .symbolVariant(transportType == .walking ? .circle : .none)
                                    .imageScale(.large)
                            }
                            if let travelTime {
                                let prefix = transportType == .automobile ? "Driving" : "Walking"
                                Text("\(prefix) time: \(travelTime)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
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
                    let inList = (selectedPlacemark != nil && selectedPlacemark?.route != nil)
                    Button {
                        if let selectedPlacemark {
                            if selectedPlacemark.route == nil {
                                route.placemarks.append(selectedPlacemark)
                            } else {
                                selectedPlacemark.route = nil
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
                            if let selectedPlacemark {
                                let placemark = MKPlacemark(coordinate: selectedPlacemark.coordinate)
                                let mapItem = MKMapItem(placemark: placemark)
                                mapItem.name = selectedPlacemark.name
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
        .task(id: selectedPlacemark) {
            await fetchLookaroundPreview()
        }
        .onAppear {
            if let selectedPlacemark, route != nil {
                name = selectedPlacemark.name
                address = selectedPlacemark.address
            }
        }
    }

    func fetchLookaroundPreview() async {
        if let selectedPlacemark {
            lookaroundScene = nil
            let lookaroundRequest = MKLookAroundSceneRequest(coordinate: selectedPlacemark.coordinate)
            lookaroundScene = try? await lookaroundRequest.scene
        }
    }
}

#Preview("Route Tab") {
    let container = Route.preview
    let fetchDescriptor = FetchDescriptor<Route>()
    let route = try! container.mainContext.fetch(fetchDescriptor)[0]
    let selectedPlacemark = route.placemarks[0]
    return LocationDetailView(
        route: route,
        selectedPlacemark: selectedPlacemark,
        showRoute: .constant(false),
        travelInterval: .constant(nil),
        transportType: .constant(.automobile)
    )
}

#Preview("TripMap Tab") {
    let container = Route.preview
    let fetchDescriptor = FetchDescriptor<Placemark>()
    let placemarks = try! container.mainContext.fetch(fetchDescriptor)
    let selectedPlacemark = placemarks[0]
    return LocationDetailView(
        selectedPlacemark: selectedPlacemark,
        showRoute: .constant(false),
        travelInterval: .constant(TimeInterval(1000)),
        transportType: .constant(.automobile)
    )
}