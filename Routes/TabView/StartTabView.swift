//
//  StartTabView.swift
//  Routes
//
//  Created by Xavi Roig Aznar on 3/11/24.
//

import SwiftUI

struct StartTabView: View {
    var body: some View {
        TabView {
            Group {
                MapView()
                    .tabItem {
                    Label("Map", systemImage: "map")
                }
                RouteCreatorBuilder().build()
                    .tabItem {
                        Label("Route Creator", systemImage: "location.fill.viewfinder")
                    }
                MyRoutesListView()
                    .tabItem {
                        Label("My Routes", systemImage: "figure.outdoor.cycle")
                    }
            }
            .toolbarBackground(.appSecondary, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.dark, for: .tabBar)
        }
    }
}

#Preview {
    StartTabView()
        .modelContainer(Route.preview)
        .environment(LocationManager())
}
