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
    func hexString(maxLen: Int) -> String {
        let full = self.map { String(format: "%02X", $0) }.joined()
        if full.count > maxLen {
            let idx = full.index(full.startIndex, offsetBy: maxLen)
            return String(full[..<idx]) + "…"
        }
        return full
    }
    
    func manufacturerSummary() -> String {
        if self.count >= 2 {
            let id = UInt16(littleEndian: self.withUnsafeBytes { $0.load(as: UInt16.self) })
            let rest = self.dropFirst(2)
            let hex = rest.hexString(maxLen: 24)
            return String(format: "ID 0x%04X, %@", id, hex.isEmpty ? "no data" : hex)
        } else {
            return self.hexString(maxLen: 24)
        }
    }
    
    func parseNameFromManufacturer() -> String? {
       guard self.count >= 4 else { return nil }
       let companyLE0 = self[0]
       let companyLE1 = self[1]
       // 0xFFFF little-endian marker for our private schema
       guard companyLE0 == 0xFF && companyLE1 == 0xFF else { return nil }
       let type = self[2]
       guard type == 0x01 else { return nil }
       let len = Int(self[3])
       guard self.count >= 4 + len, len > 0 else { return nil }
       let nameBytes = self.subdata(in: 4..<(4+len))
       return String(data: nameBytes, encoding: .utf8)
   }
}
