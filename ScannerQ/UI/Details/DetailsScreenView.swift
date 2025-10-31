//
//  DetailsScreenView.swift
//  ScannerQ
//
//  Created by Serge Nes on 10/30/25.
//

import SwiftUI
import CommonLibrary

struct DetailsScreenView: View {
    @EnvironmentObject var deps: AppDependencies
    @AppStorage(DetailsViewModel.prefsLastDeviceId) private var lastDeviceId: String = ""
    @AppStorage(DetailsViewModel.prefsLastServiceUUID) private var lastServiceUUID: String = ""
    
    private var viewModel: DetailsViewModel { deps.detailsViewModel }
    private var toggleOnBinding: Binding<Bool> {
        Binding(get: { viewModel.toggleOn }, set: { viewModel.toggleOn = $0 })
    }
    
    private var inputTextBinding: Binding<String> {
        Binding(get: { viewModel.inputText }, set: { viewModel.inputText = $0 })
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            if let img = viewModel.receivedImage {
                VStack(alignment: .leading, spacing: 6) {
                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 160, maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    HStack(spacing: 8) {
                        if let name = viewModel.receivedImageFilename { Text(name).font(.caption).lineLimit(1) }
                        if let bytes = viewModel.receivedImageBytes { Text("(\(bytes) bytes)").font(.caption2).foregroundStyle(.secondary) }
                        Spacer()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            Divider()
            messagesList
            Divider()
            composer
        }
        .navigationTitle(viewModel.detail?.device.name ?? "Device")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.setup(repository: deps.repository)
            viewModel.onAppear()
        }
        .onDisappear { viewModel.onDisappear() }
        .onChange(of: viewModel.detail) { _, newDetail in
            if let d = newDetail {
                lastDeviceId = d.device.id.uuidString
                if let svc = d.services.first { lastServiceUUID = svc.uuidString }
            }
        }
        .padding(.top, 8)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(!isConnected ? "Reconnect" :"Disconnect") {
                    if isConnected {
                        viewModel.disconnect()
                    } else {
                        viewModel.onAppear()
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                statusBadge
                Spacer()
            }
            if let d = viewModel.detail {
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.device.id.uuidString).font(.caption).foregroundStyle(.secondary)
                    if let n = d.services.first { Text("Service1: \(n.uuidString)").font(.caption2).foregroundStyle(.secondary) }
                    if let rssi = d.device.rssi { Text("RSSI: \(rssi)").font(.caption).monospacedDigit() }
                    if let n = d.notifyCharacteristic { Text("Notify: \(n.uuidString)").font(.caption2).foregroundStyle(.secondary) }
                    if let w = d.writeCharacteristic { Text("Write: \(w.uuidString)").font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var statusBadge: some View {
        let (text, color): (String, Color) = {
            switch viewModel.state {
            case .idle: return ("Idle", .gray)
            case .connecting: return ("Connecting…", .yellow)
            case .connected: return ("Connected", .green)
            case .failed(let reason): return ("Failed=>\(reason)", .red)
            case .disconnected: return ("Disconnected", .orange)
            }
        }()
        return Text(text)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
    }

    private var messagesList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(viewModel.messages.enumerated()), id: \.offset) { _, msg in
                    Text(msg)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack {
                Toggle(isOn: toggleOnBinding) {
                    Text("ON/OFF")
                }
                .labelsHidden()
                Button("Send Toggle") { viewModel.sendToggle() }
                    .buttonStyle(.bordered)
                    .disabled(!isConnected)
                Spacer()
                Button(action: { viewModel.getImage() }) {
                    if viewModel.isImageDownloading {
                        HStack(spacing: 6) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                            Text("Getting… \(Int(viewModel.imageDownloadProgress * 100))%")
                        }
                    } else {
                        Text("Get Image")
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isConnected || viewModel.isImageDownloading)
            }
            HStack(spacing: 8) {
                TextField("Type message…", text: inputTextBinding, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                Button("Send") { viewModel.send() }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.inputText.isEmpty || !isConnected)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var isConnected: Bool {
        if case .connected = viewModel.state { return true }
        return false
    }

    private var canDisconnect: Bool {
        switch viewModel.state {
        case .connected, .connecting:
            return true
        default:
            return false
        }
    }
}

#Preview {
    let deps = AppDependencies()
    deps.detailsViewModel.selectedDevice = BluetoothDevice.previewStubs.first!
    return DetailsScreenView()
        .environmentObject(deps)
}
