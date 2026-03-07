import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

@available(iOS 17.0, macOS 14.0, *)
final class ShareService {
    static let appScheme = "aura"
    static let universalLinkHost = "aura.xadev.com"

    struct ShareCardData {
        let readingExcerpt: String
        let zodiacSign: ZodiacSign
        let mbtiType: MBTIType
        let fortuneScore: Int
        let category: SituationCategory
        let date: Date
        let powerColors: [String]
        let dailyMantra: String
    }

    func createShareData(from reading: DailyReading) -> ShareCardData? {
        guard let user = reading.user else { return nil }
        let words = reading.content.split(separator: " ")
        let excerpt = words.prefix(50).joined(separator: " ")
        return ShareCardData(
            readingExcerpt: excerpt + (words.count > 50 ? "..." : ""),
            zodiacSign: user.zodiacSign,
            mbtiType: user.mbtiType,
            fortuneScore: reading.fortuneScore,
            category: reading.category,
            date: reading.date,
            powerColors: reading.powerColors,
            dailyMantra: reading.dailyMantra()
        )
    }

    func shareText(for reading: DailyReading) -> String? {
        guard let data = createShareData(from: reading) else { return nil }
        return shareText(for: data)
    }

    func deepLink(for reading: DailyReading) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.universalLinkHost
        components.path = "/share/\(reading.id.uuidString)"
        components.queryItems = [
            URLQueryItem(name: "sign", value: reading.user?.zodiacSign.rawValue),
            URLQueryItem(name: "cat", value: reading.category.rawValue),
        ]
        return components.url ?? URL(string: "https://\(Self.universalLinkHost)")!
    }

    #if os(iOS)
    @MainActor
    func renderShareImage(data: ShareCardData, colorScheme: ColorScheme = .light, width: CGFloat = 390) -> UIImage? {
        let view = ShareCardView(data: data, colorScheme: colorScheme)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 480)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
    #endif

    func shareItems(for reading: DailyReading, colorScheme: ColorScheme = .light) async -> [Any] {
        guard let data = createShareData(from: reading) else { return [] }
        var items: [Any] = []

        let link = deepLink(for: reading)
        items.append(link)

        #if os(iOS)
        if let image = await renderShareImage(data: data, colorScheme: colorScheme) {
            items.append(image)
        }
        #endif

        let text = shareText(for: data)
        items.append(text)

        return items
    }

    private func shareText(for data: ShareCardData) -> String {
        "\(data.zodiacSign.symbol) My \(data.category.rawValue) fortune today: \(data.fortuneScore)%\n\"\(data.dailyMantra)\" \u{2728}\nSee yours on Aura"
    }
}
