//
//  BluetoothDevice.swift
//  CommonLibrary
//
//  Created by Serge Nes on 10/30/25.
//

import Foundation

public struct BluetoothDevice: Identifiable, Equatable, Hashable {
    public let id: UUID
    public let name: String
    public let rssi: Int?
    public let isConnectable: Bool?
    // Preferred advertised service UUID (e.g., NUS) when available
    public let preferredServiceUUID: UUID?

    public init(id: UUID, name: String, rssi: Int?, isConnectable: Bool?, preferredServiceUUID: UUID? = nil) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.isConnectable = isConnectable
        self.preferredServiceUUID = preferredServiceUUID
    }
}
