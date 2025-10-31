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

class NavigationViewModel: ObservableObject {
    @Published  var path = NavigationPath()
    
    func navigateTo(_ screen: AppScreen) {
        path.append(screen)
    }
}

struct SplashScreenView: View {
    @EnvironmentObject var navigationViewModel: NavigationViewModel
    @EnvironmentObject var deps: AppDependencies
    @EnvironmentObject var discoveryViewModel: DiscoveryViewModel
    @EnvironmentObject var detailsViewModel: DetailsViewModel
    @State private var showSplash = true
    @StateObject private var initViewModel = InitViewModel()
    @AppStorage(DetailsViewModel.prefsLastDeviceId) private var lastDeviceId: String?
    @AppStorage(DetailsViewModel.prefsLastServiceUUID) private var lastServiceUUID: String?
    
    var body: some View {
        NavigationStack(path: $navigationViewModel.path) {
            ZStack {
                Text("No screen available")
                    .foregroundColor(.gray)
                    .navigationDestination(for: AppScreen.self) { screen in
                        switch screen {
                        case .discover:
                            DiscoveryScreenView()
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
                                discoveryViewModel: discoveryViewModel,
                                detailsViewModel: detailsViewModel,
                                navigationViewModel: navigationViewModel,
                                hideSplash: { withAnimation { self.showSplash = false } }
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
    var viewModel = DiscoveryViewModel()
    SplashScreenView()
        .onAppear {
            viewModel.onPreviewAppear()
        }
        .environmentObject(NavigationViewModel())
        .environmentObject(viewModel)
        .environmentObject(NavigationViewModel())
        .environmentObject(DetailsViewModel())
}
