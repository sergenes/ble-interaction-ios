//
//  Extensions.swift
//  BLEInteraction
//
//  Created by Serge Nes on 10/30/25.
//
import CommonLibrary
import SwiftUI

extension BluetoothDevice {
    /// An array of sample devices for SwiftUI Previews.
    static var previewStubs: [BluetoothDevice] {
        [
            BluetoothDevice(
                id: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A407234")!,
                name: "Smart Watch ⌚️",
                rssi: -45, // Strong signal
                isConnectable: true
            ),
            BluetoothDevice(
                id: UUID(uuidString: "7864B24B-E60D-47C7-99E4-2998634B0B7F")!,
                name: "Headphones",
                rssi: -78, // Weak signal
                isConnectable: true
            ),
            BluetoothDevice(
                id: UUID(uuidString: "A91F6D2C-7C4E-4A42-B9E4-3A8398C7F0D0")!,
                name: "Tile Tracker",
                rssi: -60, // Moderate signal
                isConnectable: false, // Not connectable (e.g., just broadcasting)
            )
        ]
    }
}

extension Data {
    var hex: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }
    
    func manufacturerSummary() -> String {
        if self.count >= 2 {
            let id = UInt16(littleEndian: self.withUnsafeBytes { $0.load(as: UInt16.self) })
            let rest = self.dropFirst(2)
            let hex = rest.hex
            return String(String(format: "ID 0x%04X, %@", id, hex.isEmpty ? "no data" : hex).prefix(30))
        } else {
            return String(self.hex.prefix(30))
        }
    }
}
