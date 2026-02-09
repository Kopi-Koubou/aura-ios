import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct CategorySelector: View {
    @Binding var selectedCategory: SituationCategory
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SituationCategory.allCases, id: \.self) { category in
                    CategoryChip(
                        category: category,
                        isSelected: selectedCategory == category
                    )
                    .onTapGesture {
                        withAnimation(.spring(duration: 0.2)) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct CategoryChip: View {
    let category: SituationCategory
    let isSelected: Bool
    
    var body: some View {
        Label(category.rawValue, systemImage: category.icon)
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
    }
}
