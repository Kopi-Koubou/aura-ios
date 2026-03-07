import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct FortuneCard: View {
    let reading: DailyReading

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var animatedScore = 0

    var body: some View {
        let presentationState = fortunePresentationState

        VStack(alignment: .leading, spacing: 16) {
            if presentationState.usesStackedHeaderLayout {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fortune")
                        .font(.headline.weight(.semibold))
                    scoreText
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("Fortune")
                        .font(.headline.weight(.semibold))

                    Spacer()
                    scoreText
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(trackColor)
                        .frame(height: 10)

                    Capsule()
                        .fill(fortuneTint)
                        .frame(width: max(10, geo.size.width * CGFloat(displayScore) / 100), height: 10)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.7), value: displayScore)
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)

            mantraSection

            if presentationState.usesStackedDetailLayout {
                VStack(alignment: .leading, spacing: 12) {
                    detailColumn(
                        title: "Lucky numbers",
                        value: reading.luckyNumbers.map(String.init).joined(separator: ", ")
                    )
                    detailColumn(
                        title: "Power colors",
                        value: reading.powerColors.joined(separator: ", ")
                    )
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    detailColumn(
                        title: "Lucky numbers",
                        value: reading.luckyNumbers.map(String.init).joined(separator: ", ")
                    )

                    Spacer(minLength: 12)

                    detailColumn(
                        title: "Power colors",
                        value: reading.powerColors.joined(separator: ", "),
                        trailing: true
                    )
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        }
        .onAppear {
            animateScoreTransition(to: reading.fortuneScore)
        }
        .onChange(of: reading.id) { _, _ in
            animateScoreTransition(to: reading.fortuneScore)
        }
        .onChange(of: reading.fortuneScore) { _, updatedScore in
            animateScoreTransition(to: updatedScore)
        }
    }

    private var scoreText: some View {
        Text("\(displayScore)%")
            .font(.title3.weight(.semibold))
            .foregroundStyle(fortuneTint)
            .monospacedDigit()
            .accessibilityLabel("Fortune score")
            .accessibilityValue("\(displayScore) percent")
    }

    private var mantraSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today's intention".uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            Text(reading.dailyMantra())
                .font(.system(.subheadline, design: .serif))
                .italic()
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.subtleFill())
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's intention: \(reading.dailyMantra())")
    }

    private var displayScore: Int {
        reduceMotion ? reading.fortuneScore : animatedScore
    }

    private func detailColumn(title: String, value: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(trailing ? .trailing : .leading)
                .foregroundStyle(.primary)
        }
    }

    private var fortunePresentationState: FortuneCardPresentationState {
        FortuneCardPresentationState(dynamicTypeSize: dynamicTypeSize)
    }

    private var fortuneTint: Color {
        AuraTheme.scoreTint(for: reading.fortuneScore)
    }

    private var trackColor: Color { theme.fieldBackground }

    private var theme: AuraTheme { AuraTheme(colorScheme: colorScheme) }

    private var cardBackground: Color { theme.cardBackground }

    private var cardBorder: Color { theme.cardBorder }

    private func animateScoreTransition(to targetScore: Int) {
        if reduceMotion {
            animatedScore = targetScore
            return
        }

        guard animatedScore != targetScore else { return }
        withAnimation(.easeOut(duration: 0.8).delay(0.15)) {
            animatedScore = targetScore
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct FortuneCardPresentationState {
    let dynamicTypeSize: DynamicTypeSize

    var usesStackedHeaderLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var usesStackedDetailLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }
}
