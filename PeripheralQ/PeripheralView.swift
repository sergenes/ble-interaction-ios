//
//  PeripheralView.swift
//  PeripheralQ
//
//  Created by Serge Nes on 10/30/25.
//

import SwiftUI
import Combine
import CommonLibrary
import AppKit
import UniformTypeIdentifiers

@MainActor
final class MacHostViewModel: ObservableObject {
    @Published var localName: String = "QDevice1"

    @Published private(set) var stateText: String = "Idle"
    @Published private(set) var stateColor: Color = .gray
    @Published private(set) var connectedCentralID: String?
    @Published private(set) var messages: [String] = []
    @Published private(set) var remoteToggleOn: Bool = false
    @Published var selectedImageURL: URL? = nil

    private let host = MacHostPeripheral()
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Bridge state
        host.$state
            .sink { [weak self] st in
                guard let self = self else { return }
                switch st {
                case .idle: self.stateText = "Idle"; self.stateColor = .gray; self.connectedCentralID = nil
                case .ready: self.stateText = "Ready"; self.stateColor = .blue; self.connectedCentralID = nil
                case .advertising: self.stateText = "Advertising…"; self.stateColor = .yellow; self.connectedCentralID = nil
                case .connected(let id): self.stateText = "Connected"; self.stateColor = .green; self.connectedCentralID = id?.uuidString
                case .failed(let reason): self.stateText = "Failed: \(reason)"; self.stateColor = .red
                case .disconnected: self.stateText = "Disconnected"; self.stateColor = .orange; self.connectedCentralID = nil
                }
            }
            .store(in: &cancellables)
        host.$inboundMessages
            .sink { [weak self] in self?.messages = $0 }
            .store(in: &cancellables)
        host.$remoteToggleOn
            .sink { [weak self] in self?.remoteToggleOn = $0 }
            .store(in: &cancellables)
    }

    func applyConfig() {
        // BLE legacy advertising payload is very limited (31 bytes total). We also advertise
        // a 128-bit Service UUID, which leaves only a small budget for Local Name. Keep it
        // conservative to improve reliability on macOS by truncating the Local Name to 12 UTF-8 bytes.
        let safeName = truncateToUTF8Bytes(localName, maxBytes: 12)
        let cfg = MacHostPeripheral.Config(localName: safeName, serviceUUID: Gatt.Service.nusServiceUUID.toUUID())
        host.update(config: cfg)
    }

    func startHosting() {
        applyConfig()
        host.startHosting()
    }

    func stopHosting() {
        host.stopHosting()
    }

    func send(text: String) { host.send(text: text) }

    private func dataFromHex(_ hex: String) -> Data? {
        let cleaned = hex.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "0x", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        var data = Data(); var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            let byteStr = String(cleaned[idx..<next])
            if byteStr.count == 1 { break }
            if let b = UInt8(byteStr, radix: 16) { data.append(b) } else { return nil }
            idx = next
        }
        return data
    }

    // Truncate a string to a maximum number of UTF‑8 bytes, without splitting multi‑byte characters.
    private func truncateToUTF8Bytes(_ s: String, maxBytes: Int) -> String {
        guard maxBytes > 0 else { return "" }
        var out = Data(); out.reserveCapacity(maxBytes)
        for ch in s {
            if let d = String(ch).data(using: .utf8) {
                if out.count + d.count > maxBytes { break }
                out.append(d)
            }
        }
        return String(data: out, encoding: .utf8) ?? ""
    }
    // MARK: - File Selection (macOS)
    func selectImage() {
        let panel = NSOpenPanel()
        panel.title = "Select PNG Image"
        panel.allowedContentTypes = [UTType.png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            selectedImageURL = url
            host.setSelectedImageURL(url)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var vm: MacHostViewModel
    @State private var outboundText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            configEditor
            Divider()
            messagesList
            Divider()
            composer
        }
        .frame(minWidth: 520, minHeight: 520)
        .navigationTitle("Host Simulator (macOS)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(vm.stateText)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(vm.stateColor)
                    .clipShape(Capsule())
                Spacer()
            }
            if let id = vm.connectedCentralID {
                Text("Connected Central: \(id)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Advertising as: \(vm.localName)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var configEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Local Name", text: $vm.localName)
                    .textFieldStyle(.roundedBorder)
                Button("Apply") { vm.applyConfig() }
            }
            HStack(spacing: 12) {
                Button("Start Hosting") { vm.startHosting() }
                    .buttonStyle(.borderedProminent)
                Button("Stop") { vm.stopHosting() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Select Image…") { vm.selectImage() }
            }
            if let url = vm.selectedImageURL {
                Text("Selected image: \(url.path)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Selected image: none")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }

    private var messagesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Incoming Messages")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(vm.messages.enumerated()), id: \.offset) { _, msg in
                        Text(msg)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(nsColor: .windowBackgroundColor))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            HStack {
                Text("Remote Toggle:")
                Spacer()
                HStack(spacing: 6) {
                    Text(vm.remoteToggleOn ? "ON" : "OFF")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(vm.remoteToggleOn ? Color.green : Color.red)
                        .frame(width: 16, height: 16)
                        .cornerRadius(2)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Type message to notify…", text: $outboundText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            Button("Send") {
                let text = outboundText
                outboundText = ""
                guard !text.isEmpty else { return }
                vm.send(text: text)
            }
            .buttonStyle(.borderedProminent)
            .disabled(outboundText.isEmpty)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

#Preview {
    ContentView()
}
