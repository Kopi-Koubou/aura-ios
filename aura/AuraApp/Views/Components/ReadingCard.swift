import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct ReadingCard: View {
    let reading: DailyReading

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isExpanded = false

    var body: some View {
        let presentationState = readingPresentationState

        VStack(alignment: .leading, spacing: 16) {
            headerSection(presentationState: presentationState)

            Text(reading.content)
                .font(.body)
                .lineSpacing(3)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(presentationState.lineLimit)
                .overlay(alignment: .bottom) {
                    if presentationState.showsCollapsedFadeOverlay {
                        collapsedFadeOverlay
                    }
                }

            if presentationState.showsExpansionControl {
                Button {
                    toggleExpansion()
                } label: {
                    HStack(spacing: 6) {
                        Text(presentationState.toggleButtonTitle)
                        Image(systemName: presentationState.toggleButtonIcon)
                            .font(.caption.weight(.semibold))
                    }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accentColor)
                }
                .buttonStyle(AuraPressButtonStyle())
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityHint(presentationState.accessibilityHint)
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
        .onChange(of: reading.id) { _, _ in
            isExpanded = false
        }
    }

    @ViewBuilder
    private func headerSection(presentationState: ReadingCardPresentationState) -> some View {
        if presentationState.usesStackedHeaderLayout {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZodiacIcon(sign: reading.user?.zodiacSign ?? .aries)
                    profileSummary
                    Spacer(minLength: 0)
                }
                metadataSummary(alignment: .leading)
            }
        } else {
            HStack(spacing: 12) {
                ZodiacIcon(sign: reading.user?.zodiacSign ?? .aries)
                profileSummary
                Spacer()
                metadataSummary(alignment: .trailing)
            }
        }
    }

    private var profileSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reading.user?.zodiacSign.rawValue.capitalized ?? "")
                .font(.headline.weight(.semibold))
            Text(reading.user?.mbtiType.rawValue ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func metadataSummary(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(reading.category.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(reading.date, format: .dateTime.month(.abbreviated).day())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var theme: AuraTheme { AuraTheme(colorScheme: colorScheme) }

    private var accentColor: Color { theme.accent }

    private var cardBackground: Color { theme.cardBackground }

    private var cardBorder: Color { theme.cardBorder }

    private var readingPresentationState: ReadingCardPresentationState {
        ReadingCardPresentationState(
            isExpanded: isExpanded,
            contentWordCount: reading.content.split(whereSeparator: \.isWhitespace).count,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    private var collapsedFadeOverlay: some View {
        LinearGradient(
            colors: [cardBackground.opacity(0), cardBackground.opacity(0.92), cardBackground],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 40)
        .allowsHitTesting(false)
    }

    private func toggleExpansion() {
        triggerSelectionFeedback()

        if reduceMotion {
            isExpanded.toggle()
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    private func triggerSelectionFeedback() {
        AuraHaptics.selection()
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct ReadingCardPresentationState {
    let isExpanded: Bool
    let contentWordCount: Int
    let dynamicTypeSize: DynamicTypeSize

    private static let expansionWordThreshold = 44
    private static let standardCollapsedLineLimit = 6
    private static let accessibilityCollapsedLineLimit = 8

    var showsExpansionControl: Bool {
        contentWordCount > Self.expansionWordThreshold
    }

    var usesStackedHeaderLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var lineLimit: Int? {
        guard showsExpansionControl && !isExpanded else {
            return nil
        }

        return dynamicTypeSize.isAccessibilitySize
            ? Self.accessibilityCollapsedLineLimit
            : Self.standardCollapsedLineLimit
    }

    var showsCollapsedFadeOverlay: Bool {
        lineLimit != nil
    }

    var toggleButtonTitle: String {
        isExpanded ? "Show less" : "Read full reading"
    }

    var toggleButtonIcon: String {
        isExpanded ? "chevron.up" : "chevron.down"
    }

    var accessibilityHint: String {
        isExpanded
            ? "Collapses the horoscope details"
            : "Expands the horoscope details"
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct ZodiacIcon: View {
    let sign: ZodiacSign

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(sign.symbol)
            .font(.system(size: 28))
            .frame(width: 52, height: 52)
            .background(
                Circle()
                    .fill(theme.zodiacIconBackground)
            )
            .overlay {
                Circle()
                    .strokeBorder(circleBorder, lineWidth: 1)
            }
    }

    private var circleBorder: Color { theme.subtleBorder }
    private var theme: AuraTheme { AuraTheme(colorScheme: colorScheme) }
}
