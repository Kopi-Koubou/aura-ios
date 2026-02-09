import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
struct OnboardingView: View {
    @State private var currentStep = 0
    @State private var name = ""
    @State private var birthdate = Date()
    @State private var selectedMBTI: MBTIType?
    
    var body: some View {
        NavigationStack {
            VStack {
                switch currentStep {
                case 0:
                    WelcomeView { currentStep += 1 }
                case 1:
                    NameEntryView(name: $name) { currentStep += 1 }
                case 2:
                    BirthdateView(birthdate: $birthdate) { currentStep += 1 }
                case 3:
                    MBTIPathView(selectedType: $selectedMBTI) { currentStep += 1 }
                default:
                    CompletionView()
                }
            }
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct WelcomeView: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "sparkles")
                .font(.system(size: 80))
                .foregroundStyle(.purple)
            
            Text("Welcome to Aura")
                .font(.largeTitle.bold())
            
            Text("Daily horoscope and MBTI insights personalized for you")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            Button("Get Started", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
        }
        .padding()
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct NameEntryView: View {
    @Binding var name: String
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Text("What's your name?")
                .font(.title2.bold())
            
            TextField("Enter your name", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding()
            
            Spacer()
            
            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
                .padding()
        }
        .padding()
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct BirthdateView: View {
    @Binding var birthdate: Date
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Text("When's your birthday?")
                .font(.title2.bold())
            
            DatePicker("Birthdate", selection: $birthdate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
            
            Spacer()
            
            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .padding()
        }
        .padding()
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct MBTIPathView: View {
    @Binding var selectedType: MBTIType?
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Text("What's your MBTI type?")
                .font(.title2.bold())
            
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 12) {
                    ForEach(MBTIType.allCases, id: \.self) { type in
                        Button(type.rawValue) {
                            selectedType = type
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedType == type ? .purple : .secondary)
                    }
                }
                .padding()
            }
            
            Button("Continue") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedType == nil)
            .padding()
        }
        .padding()
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct CompletionView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)
            
            Text("You're all set!")
                .font(.largeTitle.bold())
            
            Text("Your personalized horoscope awaits")
                .font(.body)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
        .padding()
    }
}
