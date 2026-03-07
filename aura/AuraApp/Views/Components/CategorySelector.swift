import SwiftUI
#if os(iOS)
import UIKit
#endif

@available(iOS 17.0, macOS 14.0, *)
struct CategorySelector: View {
    @Binding var selectedCategory: SituationCategory
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var scrollState = CategoryScrollAffordanceState()

    var body: some View {
        let presentationState = selectorPresentationState

        return Group {
            if presentationState.usesStackedLayout {
                stackedSelector
            } else {
                scrollableSelector
            }
        }
    }

    private var scrollableSelector: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(SituationCategory.allCases, id: \.self) { category in
                            CategoryChip(
                                category: category,
                                isSelected: selectedCategory == category,
                                accentColor: accentColor,
                                layout: .rail
                            ) {
                                selectCategory(category)
                            }
                            .id(category)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 2)
                    .background {
                        GeometryReader { proxy in
                            Color.clear
                                .preference(
                                    key: CategoryContentWidthPreferenceKey.self,
                                    value: proxy.size.width
                                )
                                .preference(
                                    key: CategoryContentMinXPreferenceKey.self,
                                    value: proxy.frame(in: .named("category-selector-scroll")).minX
                                )
                        }
                    }
                }
                .coordinateSpace(name: "category-selector-scroll")
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: CategoryViewportWidthPreferenceKey.self,
                            value: proxy.size.width
                        )
                    }
                }
                .onAppear {
                    proxy.scrollTo(selectedCategory, anchor: .center)
                }
                .onChange(of: selectedCategory) { _, category in
                    scrollTo(category, with: proxy)
                }
            }
            .accessibilityLabel("Situation categories")
            .accessibilityHint(selectorPresentationState.containerAccessibilityHint)

            if scrollState.showsLeadingAffordance {
                scrollAffordance(edge: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            if scrollState.showsTrailingAffordance {
                scrollAffordance(edge: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity)
            }
        }
        .animation(affordanceAnimation, value: scrollState.showsLeadingAffordance)
        .animation(affordanceAnimation, value: scrollState.showsTrailingAffordance)
        .onPreferenceChange(CategoryViewportWidthPreferenceKey.self) { width in
            scrollState.updateViewportWidth(width)
        }
        .onPreferenceChange(CategoryContentWidthPreferenceKey.self) { width in
            scrollState.updateContentWidth(width)
        }
        .onPreferenceChange(CategoryContentMinXPreferenceKey.self) { minX in
            scrollState.updateContentMinX(minX)
        }
    }

    private var stackedSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(SituationCategory.allCases, id: \.self) { category in
                CategoryChip(
                    category: category,
                    isSelected: selectedCategory == category,
                    accentColor: accentColor,
                    layout: .stacked
                ) {
                    selectCategory(category)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Situation categories")
        .accessibilityHint(selectorPresentationState.containerAccessibilityHint)
    }

    private var selectorPresentationState: CategorySelectorPresentationState {
        CategorySelectorPresentationState(dynamicTypeSize: dynamicTypeSize)
    }

    private func scrollAffordance(edge: CategoryScrollAffordanceEdge) -> some View {
        HStack(spacing: 4) {
            if edge == .leading {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LinearGradient(
                    colors: [backgroundColor, Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 24)
            } else {
                LinearGradient(
                    colors: [Color.clear, backgroundColor],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 24)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(edge == .leading ? .leading : .trailing, 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var theme: AuraTheme { AuraTheme(colorScheme: colorScheme) }

    private var accentColor: Color { theme.accent }

    private var backgroundColor: Color { theme.background }

    private var affordanceAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.2)
    }

    private func selectCategory(_ category: SituationCategory) {
        guard selectedCategory != category else { return }

        if reduceMotion {
            selectedCategory = category
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                selectedCategory = category
            }
        }

        triggerSelectionFeedback()
    }

    private func scrollTo(_ category: SituationCategory, with proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(category, anchor: .center)
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(category, anchor: .center)
            }
        }
    }

    private func triggerSelectionFeedback() { AuraHaptics.selection() }
}

@available(iOS 17.0, macOS 14.0, *)
enum CategoryScrollAffordanceEdge {
    case leading
    case trailing
}

@available(iOS 17.0, macOS 14.0, *)
struct CategorySelectorPresentationState: Sendable {
    let dynamicTypeSize: DynamicTypeSize

    var usesStackedLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var containerAccessibilityHint: String {
        usesStackedLayout
            ? "Browse categories in a vertical list."
            : "Swipe horizontally to browse categories."
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct CategoryScrollAffordanceState: Sendable {
    private(set) var viewportWidth: CGFloat = 0
    private(set) var contentWidth: CGFloat = 0
    private(set) var contentMinX: CGFloat = 0
    private let threshold: CGFloat = 10

    mutating func updateViewportWidth(_ width: CGFloat) {
        viewportWidth = max(0, width)
    }

    mutating func updateContentWidth(_ width: CGFloat) {
        contentWidth = max(0, width)
    }

    mutating func updateContentMinX(_ minX: CGFloat) {
        contentMinX = minX
    }

    var overflowWidth: CGFloat {
        max(0, contentWidth - viewportWidth)
    }

    var hasOverflow: Bool {
        overflowWidth > threshold
    }

    var showsLeadingAffordance: Bool {
        hasOverflow && contentMinX < -threshold
    }

    var showsTrailingAffordance: Bool {
        guard hasOverflow else { return false }
        let trailingLimit = -(overflowWidth - threshold)
        return contentMinX > trailingLimit
    }
}

private struct CategoryViewportWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CategoryContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CategoryContentMinXPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

@available(iOS 17.0, macOS 14.0, *)
enum CategoryChipLayout: Sendable {
    case rail
    case stacked
}

@available(iOS 17.0, macOS 14.0, *)
struct CategoryChip: View {
    let category: SituationCategory
    let isSelected: Bool
    let accentColor: Color
    let layout: CategoryChipLayout
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onSelect) {
            if layout == .stacked {
                chipLabel
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .background(chipBackground)
                    .foregroundStyle(chipForeground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(chipBorder, lineWidth: isSelected ? 0 : 1)
                    }
            } else {
                chipLabel
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(chipBackground)
                    .foregroundStyle(chipForeground)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(chipBorder, lineWidth: isSelected ? 0 : 1)
                    }
            }
        }
        .buttonStyle(AuraPressButtonStyle())
        .accessibilityLabel("\(category.rawValue) category")
        .accessibilityHint("Loads your \(category.rawValue.lowercased()) reading")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var chipLabel: some View {
        Label(category.rawValue, systemImage: category.icon)
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .lineLimit(layout == .stacked ? 2 : 1)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chipBackground: Color {
        if isSelected {
            return accentColor
        }

        return theme.chipSurface(stacked: layout == .stacked)
    }

    private var chipForeground: Color {
        isSelected ? .white : .primary
    }

    private var chipBorder: Color {
        if isSelected {
            return .clear
        }

        return theme.chipBorder
    }

    private var theme: AuraTheme { AuraTheme(colorScheme: colorScheme) }
}

