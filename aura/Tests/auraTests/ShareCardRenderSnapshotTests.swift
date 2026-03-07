import CoreGraphics
import CryptoKit
import Foundation
import SwiftUI
import XCTest
@testable import aura

@available(iOS 17.0, macOS 14.0, *)
@MainActor
final class ShareCardRenderSnapshotTests: XCTestCase {
    func testShareCardFixturesMatchReferenceSignatures() throws {
        for fixture in Self.fixtures {
            let image = try XCTUnwrap(
                renderImage(for: fixture),
                "Expected share card render to produce a CGImage for fixture '\(fixture.name)'."
            )

            XCTAssertEqual(image.width, Int(Self.renderSize.width), "Unexpected width for fixture '\(fixture.name)'.")
            XCTAssertEqual(image.height, Int(Self.renderSize.height), "Unexpected height for fixture '\(fixture.name)'.")

            let signature = try makeVisualSignature(from: image)
            XCTAssertEqual(
                signature,
                fixture.expectedSignature,
                "Unexpected visual signature for fixture '\(fixture.name)'."
            )
        }
    }

    private func renderImage(for fixture: SnapshotFixture) -> CGImage? {
        let card = ShareCardView(data: fixture.data)
            .frame(width: Self.renderSize.width, height: Self.renderSize.height)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.calendar, Calendar(identifier: .gregorian))
            .environment(\.layoutDirection, .leftToRight)
            .environment(\.dynamicTypeSize, fixture.dynamicTypeSize)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
        return renderer.cgImage
    }

    private func makeVisualSignature(from image: CGImage) throws -> String {
        let sampleWidth = 78
        let sampleHeight = 104
        let bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        let totalBytes = sampleHeight * bytesPerRow

        var sampleBuffer = [UInt8](repeating: 0, count: totalBytes)
        guard let context = CGContext(
            data: &sampleBuffer,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SnapshotError.couldNotCreateContext
        }

        context.interpolationQuality = .medium
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: CGFloat(sampleWidth), height: CGFloat(sampleHeight))
        )

        // Ignore the date text region (top-right) to keep locale/timezone differences from causing churn.
        for row in 0..<12 {
            for column in 52..<sampleWidth {
                let offset = row * bytesPerRow + column * bytesPerPixel
                sampleBuffer[offset] = 0
                sampleBuffer[offset + 1] = 0
                sampleBuffer[offset + 2] = 0
                sampleBuffer[offset + 3] = 255
            }
        }

        var quantized = [UInt8]()
        quantized.reserveCapacity(sampleWidth * sampleHeight * 3)

        for offset in stride(from: 0, to: sampleBuffer.count, by: bytesPerPixel) {
            quantized.append(sampleBuffer[offset] & 0xF0)
            quantized.append(sampleBuffer[offset + 1] & 0xF0)
            quantized.append(sampleBuffer[offset + 2] & 0xF0)
        }

        let digest = SHA256.hash(data: Data(quantized))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private enum SnapshotError: Error {
        case couldNotCreateContext
    }

    private struct SnapshotFixture {
        let name: String
        let data: ShareService.ShareCardData
        let dynamicTypeSize: DynamicTypeSize
        let expectedSignature: String
    }

    private static let renderSize = CGSize(width: 390, height: 520)

    private static let fixtures: [SnapshotFixture] = [
        SnapshotFixture(
            name: "canonical",
            data: ShareService.ShareCardData(
                readingExcerpt: "You are entering a focused season for strategic bets. Keep one bold priority in motion, protect your calendar from noise, and say yes only to opportunities that match your long-term direction. Consistency is your edge today.",
                zodiacSign: .virgo,
                mbtiType: .INTJ,
                fortuneScore: 88,
                category: .career,
                date: Date(timeIntervalSince1970: 1_740_355_200),
                powerColors: ["Gold", "Sea Green", "Lavender"]
            ),
            dynamicTypeSize: .large,
            expectedSignature: "51544c1a9b7102c13015a3a3bb2a6fb282633551920748805fb7c92585cecf24"
        ),
        SnapshotFixture(
            name: "long-copy-low-fortune",
            data: ShareService.ShareCardData(
                readingExcerpt: "Progress is still progress, even when it is quiet. Today favors patient calibration over dramatic moves, so reduce unnecessary commitments, protect your energy window, and finish the one conversation you have been postponing. A measured response now avoids rework later and gives your next decision real traction.",
                zodiacSign: .scorpio,
                mbtiType: .ENFP,
                fortuneScore: 63,
                category: .love,
                date: Date(timeIntervalSince1970: 1_741_392_000),
                powerColors: ["Charcoal", "Rosewood", "Mist Blue", "Rosewood"]
            ),
            dynamicTypeSize: .large,
            expectedSignature: "13970cef384b8c4aa61f369b88a5ee3a5080242ce643a44f1a4ede8155e13b05"
        ),
        SnapshotFixture(
            name: "accessibility-size-stress",
            data: ShareService.ShareCardData(
                readingExcerpt: "Lead with one clear ask, then keep the rest simple. Your best outcomes come from narrowing scope and making each next step obvious for everyone involved.",
                zodiacSign: .aquarius,
                mbtiType: .ISTJ,
                fortuneScore: 74,
                category: .personalGrowth,
                date: Date(timeIntervalSince1970: 1_742_860_800),
                powerColors: ["Sage", "Amber", "Slate"]
            ),
            dynamicTypeSize: .accessibility3,
            expectedSignature: "eeeb445b2615ebd29b8e76b49a3107c110e1b0fa08f1ad940842ed743f13ca9c"
        )
    ]
}
