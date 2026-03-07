import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct ShareCardView: View {
    let data: ShareService.ShareCardData
    var colorScheme: ColorScheme = .light

    private var theme: AuraTheme { AuraTheme(colorScheme: colorScheme) }

    var body: some View {
        ZStack {
            theme.background

            VStack(alignment: .leading, spacing: 24) {
                header

                HStack(spacing: 14) {
                    zodiacIcon

                    VStack(alignment: .leading, spacing: 6) {
                        Text(data.zodiacSign.rawValue.capitalized)
                            .font(.system(size: 28, weight: .semibold, design: .serif))
                            .foregroundStyle(textPrimaryColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text(data.mbtiType.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(textSecondaryColor)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(theme.fieldBackground)
                            .clipShape(Capsule())
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(data.zodiacSign.rawValue.capitalized), \(data.mbtiType.rawValue)")

                fortuneMeter

                Text(data.readingExcerpt)
                    .font(.body)
                    .lineSpacing(3)
                    .foregroundStyle(textPrimaryColor)
                    .multilineTextAlignment(.leading)
                    .lineLimit(6)

                mantraSection

                if presentationState.hasActiveRetrograde {
                    retrogradeIndicator
                }

                if !presentationState.displayedPowerColors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Power colors")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(textSecondaryColor)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { powerColorChips }
                            VStack(alignment: .leading, spacing: 8) { powerColorChips }
                        }
                    }
                }

                Spacer(minLength: 0)

                footer
            }
            .padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.cardBorder, lineWidth: 1)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Label(data.category.rawValue, systemImage: data.category.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(theme.accentFill())
                .clipShape(Capsule())

            Spacer()

            Text(data.date, format: .dateTime.month(.abbreviated).day())
                .font(.caption.weight(.medium))
                .foregroundStyle(textSecondaryColor)
        }
    }

    // MARK: - Fortune Meter

    private var fortuneMeter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Fortune")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(textSecondaryColor)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(data.fortuneScore)%")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(fortuneTint)
                        .monospacedDigit()

                    Text(presentationState.fortuneMomentumLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(textSecondaryColor)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Fortune score \(data.fortuneScore) percent, \(presentationState.fortuneMomentumLabel)")

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.fieldBackground)
                        .frame(height: 10)

                    Capsule()
                        .fill(fortuneTint)
                        .frame(
                            width: max(10, geo.size.width * CGFloat(data.fortuneScore) / 100),
                            height: 10
                        )
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Power Color Chips

    @ViewBuilder
    private var powerColorChips: some View {
        ForEach(presentationState.displayedPowerColors, id: \.self) { color in
            Text(color)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(theme.accentFill())
                .clipShape(Capsule())
                .foregroundStyle(textPrimaryColor)
        }
    }

    // MARK: - Zodiac Icon

    private var zodiacIcon: some View {
        Text(data.zodiacSign.symbol)
            .font(.system(size: 26))
            .frame(width: 48, height: 48)
            .background(
                Circle()
                    .fill(theme.accentFill())
            )
            .overlay {
                Circle()
                    .strokeBorder(theme.cardBorder, lineWidth: 1)
            }
            .accessibilityHidden(true)
    }

    // MARK: - Retrograde Indicator

    private var retrogradeIndicator: some View {
        let active = RetrogradeCatalog.activeRetrogrades
        return HStack(spacing: 8) {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(retrogradeAmberColor)

            Text(active.map { "\($0.symbol) \($0.planet)" }.joined(separator: " + ") + " Retrograde")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(textSecondaryColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(retrogradeAmberColor.opacity(0.10))
        .clipShape(Capsule())
        .accessibilityLabel(active.map { "\($0.planet) retrograde" }.joined(separator: " and "))
    }

    // MARK: - Mantra

    private var mantraSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today's intention".uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(textSecondaryColor)

            Text(data.dailyMantra)
                .font(.system(.subheadline, design: .serif))
                .italic()
                .foregroundStyle(textPrimaryColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accentFill())
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Aura")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(textSecondaryColor)

            Spacer()

            Text("See yours on Aura")
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.accent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Shared from Aura")
    }

    // MARK: - Presentation State

    private var presentationState: ShareCardPresentationState {
        ShareCardPresentationState(
            powerColors: data.powerColors,
            fortuneScore: data.fortuneScore,
            activeRetrogrades: RetrogradeCatalog.activeRetrogrades
        )
    }

    // MARK: - Colors

    private var textPrimaryColor: Color { theme.textPrimary }
    private var textSecondaryColor: Color { theme.textSecondary }
    private var retrogradeAmberColor: Color { AuraTheme.retrogradeAmber }

    private var fortuneTint: Color {
        AuraTheme.scoreTint(for: data.fortuneScore)
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct ShareCardPresentationState: Sendable {
    let powerColors: [String]
    let fortuneScore: Int
    let activeRetrogrades: [RetrogradeEvent]

    var hasActiveRetrograde: Bool {
        !activeRetrogrades.isEmpty
    }

    private static let maxPowerColorCount = 3

    var displayedPowerColors: [String] {
        var seen = Set<String>()
        var result: [String] = []

        for rawColor in powerColors {
            let cleaned = rawColor.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }

            let dedupeKey = cleaned.lowercased()
            guard seen.insert(dedupeKey).inserted else { continue }

            result.append(cleaned)
            if result.count == Self.maxPowerColorCount {
                break
            }
        }

        return result
    }

    var fortuneMomentumLabel: String {
        switch fortuneScore {
        case 85...:
            return "Strong momentum"
        case 70...:
            return "Steady momentum"
        default:
            return "Reflective momentum"
        }
    }
}
