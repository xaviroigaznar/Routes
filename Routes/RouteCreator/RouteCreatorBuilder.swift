//
//  RouteCreatorBuilder.swift
//  Routes
//
//  Created by Xavi Roig Aznar on 28/11/24.
//

import SwiftUI

class RouteCreatorBuilder {
    func build() -> some View {
        RouteCreatorView(viewModel: RouteCreatorViewModel())
    }
}
