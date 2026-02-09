import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct ShareCardView: View {
    let data: ShareService.ShareCardData

    private var gradientColors: [Color] {
        switch data.category {
        case .career: return [Color(red: 0.4, green: 0.2, blue: 0.6), Color(red: 0.2, green: 0.1, blue: 0.4)]
        case .love: return [Color(red: 0.7, green: 0.2, blue: 0.3), Color(red: 0.5, green: 0.1, blue: 0.2)]
        case .social: return [Color(red: 0.2, green: 0.4, blue: 0.6), Color(red: 0.1, green: 0.2, blue: 0.4)]
        case .health: return [Color(red: 0.2, green: 0.5, blue: 0.3), Color(red: 0.1, green: 0.3, blue: 0.2)]
        case .personalGrowth: return [Color(red: 0.6, green: 0.4, blue: 0.1), Color(red: 0.4, green: 0.2, blue: 0.1)]
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text(data.zodiacSign.symbol)
                    .font(.system(size: 48))

                Text(data.zodiacSign.rawValue.capitalized)
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Text(data.mbtiType.rawValue)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.top, 32)
            .padding(.bottom, 16)

            // Fortune score
            HStack {
                Text("Fortune")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("\(data.fortuneScore)%")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)

            // Score bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.2))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .frame(width: geo.size.width * CGFloat(data.fortuneScore) / 100, height: 6)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            // Reading excerpt
            Text(data.readingExcerpt)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(5)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 20)

            Spacer()

            // Category + date
            HStack {
                Label(data.category.rawValue, systemImage: data.category.icon)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(data.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 24)

            // Power colors
            HStack(spacing: 8) {
                ForEach(data.powerColors, id: \.self) { color in
                    Text(color)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.top, 8)

            // Branding
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                Text("Aura")
                    .font(.caption.bold())
            }
            .foregroundStyle(.white.opacity(0.5))
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .background(
            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}
