#!/usr/bin/env swift

import CryptoKit
import CoreGraphics
import Foundation
import ImageIO

enum PixelHashError: Error, LocalizedError {
    case missingInput
    case invalidIgnoreBottom(String)
    case failedToLoadImage(String)
    case failedToCreateContext(String)

    var errorDescription: String? {
        switch self {
        case .missingInput:
            return "Usage: ./Scripts/hash-png-pixels.swift [--ignore-bottom <pixels>] <png> [<png> ...]"
        case .invalidIgnoreBottom(let value):
            return "Invalid --ignore-bottom value: \(value)"
        case .failedToLoadImage(let path):
            return "Failed to load PNG at \(path)"
        case .failedToCreateContext(let path):
            return "Failed to create bitmap context for \(path)"
        }
    }
}

func pixelHash(for path: String, ignoreBottomPixels: Int) throws -> String {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw PixelHashError.failedToLoadImage(path)
    }

    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    var pixelData = Data(count: bytesPerRow * height)

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    let created = pixelData.withUnsafeMutableBytes { buffer -> Bool in
        guard let baseAddress = buffer.baseAddress,
              let context = CGContext(
                data: baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
              )
        else {
            return false
        }

        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }

    guard created else {
        throw PixelHashError.failedToCreateContext(path)
    }

    let effectiveHeight = max(0, height - ignoreBottomPixels)
    let effectiveData = pixelData.prefix(bytesPerRow * effectiveHeight)
    let digest = SHA256.hash(data: effectiveData)
    return digest.map { String(format: "%02x", $0) }.joined()
}

do {
    var ignoreBottomPixels = 0
    var inputs: [String] = []
    var iterator = CommandLine.arguments.dropFirst().makeIterator()

    while let argument = iterator.next() {
        if argument == "--ignore-bottom" {
            guard let value = iterator.next() else {
                throw PixelHashError.invalidIgnoreBottom("<missing>")
            }
            guard let parsed = Int(value), parsed >= 0 else {
                throw PixelHashError.invalidIgnoreBottom(value)
            }
            ignoreBottomPixels = parsed
            continue
        }

        inputs.append(argument)
    }

    guard !inputs.isEmpty else {
        throw PixelHashError.missingInput
    }

    for path in inputs {
        let hash = try pixelHash(for: path, ignoreBottomPixels: ignoreBottomPixels)
        print("\(hash)  \((path as NSString).lastPathComponent)")
    }
} catch {
    fputs((error as? LocalizedError)?.errorDescription ?? "\(error)\n", stderr)
    fputs("\n", stderr)
    exit(1)
}
