import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.purple)
                .frame(width: 32)
            
            Text(text)
                .font(.body)
            
            Spacer()
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct PackageButton: View {
    let title: String
    let description: String
    let price: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(price)
                    .font(.title3.bold())
            }
            .padding()
            .background(.purple.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
