//
//  ContentView.swift
//  ScannerQ
//
//  Created by Serge Nes on 10/30/25.
//

import SwiftUI
import CommonLibrary

struct DiscoveryScreenView: View {
    @EnvironmentObject var deps: AppDependencies
    @EnvironmentObject var navigationViewModel: NavigationViewModel
    @EnvironmentObject var discoveryViewModel: DiscoveryViewModel
    @EnvironmentObject var detailsViewModel: DetailsViewModel
    
    @State private var searchText: String = ""
    
    // Filtered devices according to search text (by name, case-insensitive)
    private var filteredDevices: [BluetoothDevice] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return discoveryViewModel.devices }
        return discoveryViewModel.devices.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }
    
    var body: some View {
        ZStack (alignment: .top) {
            VStack {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search by name", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding([.horizontal])
               ScrollView {
                   LazyVStack(alignment: .leading, spacing: 0) {
                       ForEach(filteredDevices, id: \.id) { device in
                           VStack(spacing: 0)  {
                               DeviceRowView(device: device) {
                                   if device.isConnectable == true {
                                       detailsViewModel.selectedDevice = device
                                       navigationViewModel.navigateTo(.details)
                                   }
                               }
                               .buttonStyle(PressableButtonStyle())
                               Divider()
                           }
                           .id(device.id)
                       }
                   }
                   .listStyle(.plain)
               }
            }
        }
        .navigationTitle("Discovery")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: { discoveryViewModel.toggleScanning() }) {
                    HStack(spacing: 6) {
                        if discoveryViewModel.isScanning { ProgressView().scaleEffect(0.8) }
                        Text(discoveryViewModel.isScanning ? "Scanning" : "Scan")
                    }
                }
                .disabled(discoveryViewModel.powerState != .poweredOn)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            discoveryViewModel.setup(repository: deps.repository)
            discoveryViewModel.onAppear()
        }
        .onDisappear {
            discoveryViewModel.onDisappear()
        }
    }
}

private struct Banner: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(color)
    }
}

#Preview {
    var viewModel = DiscoveryViewModel()
    NavigationView {
        DiscoveryScreenView()
            .onAppear {
                viewModel.onPreviewAppear()
            }
            .environmentObject(viewModel)
            .environmentObject(NavigationViewModel())
            .environmentObject(DetailsViewModel())
            .environmentObject(AppDependencies())
    }
}
