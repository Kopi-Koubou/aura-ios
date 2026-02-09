import Foundation
import SwiftUI

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
            powerColors: reading.powerColors
        )
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

    @MainActor
    func renderShareImage(data: ShareCardData, size: CGSize = CGSize(width: 390, height: 520)) -> UIImage? {
        let view = ShareCardView(data: data)
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }

    func shareItems(for reading: DailyReading) async -> [Any] {
        guard let data = createShareData(from: reading) else { return [] }
        var items: [Any] = []

        let link = deepLink(for: reading)
        items.append(link)

        if let image = await renderShareImage(data: data) {
            items.append(image)
        }

        let text = "\(data.zodiacSign.symbol) My \(data.category.rawValue) fortune today: \(data.fortuneScore)% \u{2728}\nSee yours on Aura"
        items.append(text)

        return items
    }
}
