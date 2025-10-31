//
//  ScannerQApp.swift
//  ScannerQ
//
//  Created by Serge Nes on 10/30/25.
//

import SwiftUI

@main
struct ScannerQApp: App {
    @StateObject var navigationViewModel = NavigationViewModel()
    @StateObject var discoveryViewModel = DiscoveryViewModel()
    @StateObject var detailsViewModel = DetailsViewModel()
    
    @StateObject private var deps = AppDependencies()
    
    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .environmentObject(navigationViewModel)
                .environmentObject(discoveryViewModel)
                .environmentObject(detailsViewModel)
                .environmentObject(deps)
        }
    }
}
