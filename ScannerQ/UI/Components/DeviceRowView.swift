//
//  DeviceRowView.swift
//  ScannerQ
//
//  Created by Serge Nes on 10/30/25.
//

import SwiftUI
import CommonLibrary

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.gray.opacity(0.6) : Color.clear)
    }
}

struct DeviceRowView: View {
    let device: BluetoothDevice
    let action: (() -> Void)

    private func tail(from uuid: UUID) -> String {
        let s = uuid.uuidString.uppercased()
        if let last = s.split(separator: "-").last { return String(last) }
        return s
    }

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name.isEmpty ? "Unknown" : device.name)
                        .font(.headline)
                    Text(device.preferredServiceUUID.map { tail(from: $0) } ?? device.id.uuidString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let rssi = device.rssi {
                        Text("RSSI: \(rssi)")
                            .font(.subheadline)
                            .monospacedDigit()
                    } else {
                        Text("RSSI: —")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let c = device.isConnectable {
                        Text(c ? "Connectable" : "Not Connectable")
                            .font(.caption2)
                            .foregroundStyle(c ? .green : .secondary)
                    }
                }
                if device.isConnectable == true {
                    Image(systemName: "arrow.forward")
                        .font(.body)
                        .foregroundStyle(.green)
                }
            }
            .padding()
        }
    }
    

}

#Preview {
    DeviceRowView(device: BluetoothDevice.previewStubs.first!) {
    }.buttonStyle(PressableButtonStyle())
}
