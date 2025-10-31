//
//  SplashScreenView.swift
//  ScannerQ
//
//  Created by Serge Nes on 10/30/25.
//

import SwiftUI
import Combine
import CommonLibrary

enum AppScreen: Hashable {
    case discover
    case details
}

struct SplashScreenView: View {
    @EnvironmentObject var deps: AppDependencies
    @State private var showSplash = true
    @State var path = NavigationPath()
    
    @StateObject private var initViewModel = InitViewModel()
    @AppStorage(DetailsViewModel.prefsLastDeviceId) private var lastDeviceId: String?
    @AppStorage(DetailsViewModel.prefsLastServiceUUID) private var lastServiceUUID: String?
    
    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Text("No screen available")
                    .padding(.bottom, 200)
                    .foregroundColor(Color.blue)
                    .navigationDestination(for: AppScreen.self) { screen in
                        switch screen {
                        case .discover:
                            DiscoveryScreenView(onNavigateToDetails: {
                                path.append(AppScreen.details)
                            })
                        case .details:
                            DetailsScreenView()
                        }
                    }
                
                if showSplash {
                    splashContent
                        .transition(.opacity)
                        .onAppear {
                            initViewModel.attemptAutoReconnect(
                                lastDeviceId: lastDeviceId,
                                lastServiceUUID: lastServiceUUID,
                                deps: deps,
                                hideSplash: { destinations in
                                    var newPath = NavigationPath()
                                    for destination in destinations {
                                        newPath.append(destination)
                                    }
                                    withAnimation {
                                        self.showSplash = false
                                        self.path = newPath
                                    }
                                }
                            )
                        }
                }
            }
        }
    }
    
    private var splashContent: some View {
        ZStack {
            Color(Color.blue)
                .edgesIgnoringSafeArea(.all)
            VStack {
                Spacer()
                Text("BLE Interaction")
                    .font(.system(size: 44, design: .rounded))
                    .bold()
                    .foregroundColor(.white)
                Spacer()
            }
        }
    }
    
}

#Preview {
    let deps = AppDependencies()
    deps.discoveryViewModel.onPreviewAppear()
    return SplashScreenView()
        .environmentObject(deps)
}
