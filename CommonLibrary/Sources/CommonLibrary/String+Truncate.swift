//
//  String+Truncate.swift
//  CommonLibrary
//
//  Created by Serge Nes on 10/30/25.
//

import Foundation

public extension String {
    func truncated(to max: Int) -> String {
        guard max >= 0 else { return self }
        if self.count <= max { return self }
        let idx = self.index(self.startIndex, offsetBy: max)
        return String(self[..<idx]) + "…"
    }
}