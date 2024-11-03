//
//  RoutesApp.swift
//  Routes
//
//  Created by Xavi Roig Aznar on 2/11/24.
//

import SwiftUI
import SwiftData

@main
struct RoutesApp: App {
    @State private var locationManager = LocationManager()

    var body: some Scene {
        WindowGroup {
            StartTabView()
        }
        .modelContainer(for: Route.self)
        .environment(locationManager)
    }
}
