//
//  TextProtocolParser.swift
//  CommonLibrary
//
//  Created by Serge Nes on 10/31/25.
//

import Foundation

// MARK: - Protocol keywords/constants
public enum TextProtocol {
    public static let imgBegin = "IMG_BEGIN"
    public static let imgEnd = "IMG_END"
    public static let imgError = "IMG_ERROR"
    // Commands
    public static let on = "ON"
    public static let off = "OFF"
    public static let get = "GET"
    public static let getImage = "GET_IMAGE"
}

// MARK: - Delegate for parsed events
public protocol TextMessageHandler: AnyObject {
    func didReceiveRegularMessage(_ line: String)
    func didStartImage(filename: String, expectedBytes: Int)
    func didReceiveImageProgress(bytesEstimated: Int, expectedBytes: Int)
    func didFinishImage(data: Data, filename: String)
    func didFailImage(reason: String)
}

// Default empty implementations to make methods optional in conformers
public extension TextMessageHandler {
    func didReceiveRegularMessage(_ line: String) {}
    func didStartImage(filename: String, expectedBytes: Int) {}
    func didReceiveImageProgress(bytesEstimated: Int, expectedBytes: Int) {}
    func didFinishImage(data: Data, filename: String) {}
    func didFailImage(reason: String) {}
}

// MARK: - Parser
public final class TextProtocolParser {
    public weak var delegate: TextMessageHandler?

    // Internal state for image reception
    private var receivingImage = false
    private var base64Buffer = ""
    private var expectedBytes = 0
    private var filename = ""

    // Safety: cap on base64 accumulation (~5MB decoded -> ~7MB base64)
    private let maxBase64Chars = 7_000_000

    public init(delegate: TextMessageHandler? = nil) {
        self.delegate = delegate
    }

    // Feed one textual line (already trimmed if desired)
    public func feed(line raw: String) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        
        // 1) If currently receiving image data, handle chunk or end marker
        if receivingImage {
            processImageChunkOrEnd(line)
            return
        }
        
        // 2) Check for image begin line
        if processImageBegin(line) {
            return
        }
        
        // 3) Fallback to regular or error line processing
        processRegularOrError(line)
    }
    
    // MARK: - Split handlers (extracted from feed)
    /// Handles image chunk accumulation and end marker while in image-receiving mode
    private func processImageChunkOrEnd(_ line: String) {
        if line == TextProtocol.imgEnd {
            completeImage()
            return
        }
        // Accumulate base64 chunk
        if base64Buffer.count + line.count <= maxBase64Chars {
            base64Buffer += line
            if expectedBytes > 0 {
                // Rough estimate: base64 expands data by ~33%
                let estimatedDecoded = Int(Double(base64Buffer.count) * 0.75)
                delegate?.didReceiveImageProgress(bytesEstimated: estimatedDecoded, expectedBytes: expectedBytes)
            }
        } else {
            failImage(reason: "too_large")
        }
    }
    
    /// Attempts to parse an IMG_BEGIN line. Returns true if handled.
    private func processImageBegin(_ line: String) -> Bool {
        guard line.hasPrefix(TextProtocol.imgBegin) else { return false }
        // parse: IMG_BEGIN <filename> <bytes>
        let parts = line.split(separator: " ")
        if parts.count >= 3 {
            filename = String(parts[1])
            let bytesStr = String(parts[2])
            expectedBytes = Int(bytesStr) ?? 0
            base64Buffer = ""
            receivingImage = true
            delegate?.didStartImage(filename: filename, expectedBytes: expectedBytes)
        } else {
            delegate?.didFailImage(reason: "begin_bad_format")
        }
        return true
    }
    
    /// Handles regular text lines and IMG_ERROR passthrough when not receiving an image
    private func processRegularOrError(_ line: String) {
        if line.hasPrefix(TextProtocol.imgError) {
            // Pass through error line and reset state just in case
            delegate?.didReceiveRegularMessage(line)
            resetImageState()
            return
        }
        // Default: regular message
        delegate?.didReceiveRegularMessage(line)
    }

    // MARK: - Private helpers
    private func completeImage() {
        defer { resetImageState() }
        guard let data = Data(base64Encoded: base64Buffer, options: [.ignoreUnknownCharacters]) else {
            delegate?.didFailImage(reason: "base64_invalid")
            return
        }
        if expectedBytes > 0 && data.count != expectedBytes {
            delegate?.didFailImage(reason: "size_mismatch exp=\(expectedBytes) got=\(data.count)")
            return
        }
        delegate?.didFinishImage(data: data, filename: filename)
    }

    private func failImage(reason: String) {
        delegate?.didFailImage(reason: reason)
        resetImageState()
    }

    private func resetImageState() {
        receivingImage = false
        base64Buffer = ""
        expectedBytes = 0
        filename = ""
    }
}
