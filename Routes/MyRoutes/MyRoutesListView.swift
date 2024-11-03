//
//  MyRoutesListView.swift
//  Routes
//
//  Created by Xavi Roig Aznar on 3/11/24.
//

import SwiftUI
import SwiftData

struct MyRoutesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Route.name) private var routes: [Route]
    @State private var newRoute = false
    @State private var routeName = ""
    @State private var path = NavigationPath()
    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !routes.isEmpty{
                    List(routes) { route in
                        NavigationLink(value: route){
                            HStack {
                                Image(systemName: "globe")
                                    .imageScale(.large)
                                    .foregroundStyle(.accent)
                                VStack(alignment: .leading) {
                                    Text(route.name)
                                    Text("^[\(route.placemarks.count) location](inflect: true)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                modelContext.delete(route)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .navigationDestination(for: Route.self) { route in
                        RouteLocationsMapView(route: route)
                    }
                } else {
                    ContentUnavailableView(
                        "No Destinations",
                        systemImage: "globe.desk",
                        description: Text("You have not set up any destinations yet.  Tap on the \(Image(systemName: "plus.circle.fill")) button in the toolbar to begin.")
                    )
                }
            }
            .navigationTitle("My Destinations")
            .toolbar {
                Button {
                    newRoute.toggle()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .alert(
                    "Enter Destination Name",
                    isPresented: $newRoute) {
                        TextField("Enter destination name", text: $routeName)
                            .autocorrectionDisabled()
                        Button("OK") {
                            if !routeName.isEmpty {
                                let route = Route(name: routeName.trimmingCharacters(in: .whitespacesAndNewlines))
                                modelContext.insert(route)
                                routeName = ""
                                path.append(route)
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Create a new destination")
                    }

            }
        }
    }
}

#Preview {
    MyRoutesListView()
        .modelContainer(Route.preview)
}
