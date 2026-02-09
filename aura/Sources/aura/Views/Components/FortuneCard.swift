import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct FortuneCard: View {
    let reading: DailyReading
    @State private var animatedScore = 0
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Fortune")
                    .font(.headline)
                Spacer()
                Text("\(animatedScore)%")
                    .font(.title2.bold())
                    .foregroundStyle(fortuneColor)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.secondary.opacity(0.2))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(fortuneGradient)
                        .frame(width: geo.size.width * CGFloat(animatedScore) / 100, height: 8)
                        .animation(.easeInOut(duration: 0.8), value: animatedScore)
                }
            }
            .frame(height: 8)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Lucky Numbers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(reading.luckyNumbers.map(String.init).joined(separator: ", "))
                        .font(.subheadline)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("Power Colors")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(reading.powerColors.joined(separator: ", "))
                        .font(.subheadline)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).delay(0.3)) {
                animatedScore = reading.fortuneScore
            }
        }
    }
    
    var fortuneColor: Color {
        switch reading.fortuneScore {
        case 80...100: return .green
        case 60...79: return .yellow
        default: return .orange
        }
    }
    
    var fortuneGradient: LinearGradient {
        LinearGradient(
            colors: [.yellow, .orange, .red],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
