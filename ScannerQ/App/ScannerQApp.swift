//
//  ScannerQApp.swift
//  ScannerQ
//
//  Created by Serge Nes on 10/30/25.
//

import SwiftUI

@main
struct ScannerQApp: App {
    @StateObject private var deps = AppDependencies()
    
    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .environmentObject(deps)
        }
    }
}
