import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct ReadingCard: View {
    let reading: DailyReading
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ZodiacIcon(sign: reading.user?.zodiacSign ?? .aries)
                VStack(alignment: .leading) {
                    Text(reading.user?.zodiacSign.rawValue.capitalized ?? "")
                        .font(.headline)
                    Text(reading.user?.mbtiType.rawValue ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(reading.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Text(reading.content)
                .font(.body)
                .lineLimit(isExpanded ? nil : 4)
                .onTapGesture { isExpanded.toggle() }
            
            if !isExpanded {
                Text("Tap to read more...")
                    .font(.caption)
                    .foregroundStyle(.purple)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct ZodiacIcon: View {
    let sign: ZodiacSign
    
    var body: some View {
        Text(sign.symbol)
            .font(.system(size: 32))
            .frame(width: 56, height: 56)
            .background(.purple.opacity(0.1))
            .clipShape(Circle())
    }
}
