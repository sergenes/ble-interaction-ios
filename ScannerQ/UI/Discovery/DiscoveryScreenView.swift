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
    var onNavigateToDetails: () -> Void = { }
    
    @State private var searchText: String = ""
    
    private var viewModel: DiscoveryViewModel { deps.discoveryViewModel }
    
    // Filtered devices according to search text (by name, case-insensitive)
    private var filteredDevices: [BluetoothDevice] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return viewModel.devices }
        return viewModel.devices.filter { $0.name.localizedCaseInsensitiveContains(q) }
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
                                       deps.detailsViewModel.selectedDevice = device
                                       onNavigateToDetails()
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
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: { viewModel.toggleScanning() }) {
                    HStack(spacing: 6) {
                        if viewModel.isScanning { ProgressView().scaleEffect(0.8) }
                        Text(viewModel.isScanning ? "Scanning" : "Scan")
                    }
                }
                .disabled(viewModel.powerState != .poweredOn)
            }
        }
        .onAppear {
            viewModel.setup(repository: deps.repository)
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
    }
}

#Preview {
    let deps = AppDependencies()
    NavigationStack {
        DiscoveryScreenView(onNavigateToDetails: {})
        .onAppear {
            deps.discoveryViewModel.onPreviewAppear()
        }
        .environmentObject(deps)
    }
}
