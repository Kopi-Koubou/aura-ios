//
//  DemoRecorder.swift
//  Aura - Demo Automation Helper
//
//  Helper for auto-navigating app flows during demo recording.
//  Use this to pre-populate state or trigger specific UI flows.
//

import SwiftUI
import SwiftData

#if DEBUG
/// Demo mode configuration for hackathon recordings
enum DemoMode {
    static let isEnabled = UserDefaults.standard.bool(forKey: "aura_demo_mode")
    static let autoNavigate = UserDefaults.standard.bool(forKey: "aura_demo_auto_navigate")
    static let speedMultiplier = UserDefaults.standard.double(forKey: "aura_demo_speed") // 0.5 = 2x faster
    
    /// Enable demo mode via launch arguments or user defaults
    static func enable(autoNavigate: Bool = true, speed: Double = 0.5) {
        UserDefaults.standard.set(true, forKey: "aura_demo_mode")
        UserDefaults.standard.set(autoNavigate, forKey: "aura_demo_auto_navigate")
        UserDefaults.standard.set(speed, forKey: "aura_demo_speed")
    }
    
    /// Reset all demo settings
    static func reset() {
        UserDefaults.standard.removeObject(forKey: "aura_demo_mode")
        UserDefaults.standard.removeObject(forKey: "aura_demo_auto_navigate")
        UserDefaults.standard.removeObject(forKey: "aura_demo_speed")
        UserDefaults.standard.removeObject(forKey: "aura_demo_step")
    }
}

/// Predefined demo flows for recording
enum DemoFlow {
    case onboarding
    case mbtiTest
    case dailyReading
    case fullJourney  // 60-90 second complete flow
    
    var steps: [DemoStep] {
        switch self {
        case .onboarding:
            return [
                .wait(1),
                .tap("Begin Journey"),
                .wait(0.5),
                .type("Alex", in: "Your name"),
                .wait(0.3),
                .tap("Continue"),
                .wait(0.5),
                .tap("Continue"), // Birthdate screen
                .wait(0.5),
                .tap("Start Assessment")
            ]
            
        case .mbtiTest:
            return [
                .wait(0.5),
                // Answer 5 sample questions quickly
                .tap(optionContaining: "Energized"),
                .wait(0.3),
                .tap("Next"),
                .tap(optionContaining: "Details"),
                .wait(0.3),
                .tap("Next"),
                .tap(optionContaining: "Logic"),
                .wait(0.3),
                .tap("Next"),
                .tap(optionContaining: "Planned"),
                .wait(0.3),
                .tap("Next"),
                .tap(optionContaining: "Social"),
                .wait(0.3),
                .tap("See Results"),
                .wait(2) // Show result screen
            ]
            
        case .dailyReading:
            return [
                .wait(1),
                .swipe(.up),
                .wait(0.5),
                .swipe(.up),
                .wait(0.5),
                .tap("Week"),
                .wait(1),
                .swipe(.up),
                .wait(0.5),
                .tap("Profile"),
                .wait(1)
            ]
            
        case .fullJourney:
            // Optimized 75-second complete demo flow
            return [
                // Welcome screen (0-3s)
                .wait(2),
                .highlightFeature("MBTI Personality Assessment", duration: 0.8),
                .wait(0.5),
                .tap("Begin Journey"),
                
                // Name input (3-6s)
                .wait(0.5),
                .type("Alex", in: "Your name"),
                .wait(0.3),
                .tap("Continue"),
                
                // Birthdate (6-9s)
                .wait(0.5),
                .showZodiac("Aquarius"),
                .wait(0.3),
                .tap("Continue"),
                
                // MBTI Intro (9-12s)
                .wait(1),
                .tap("Start Assessment"),
                
                // MBTI Questions (12-35s) - answer 8 quickly
                .answerMBTIQuestions(count: 8),
                .wait(0.5),
                .tap("See Results"),
                
                // MBTI Result (35-45s)
                .wait(3),
                .swipe(.up),
                .wait(0.5),
                .tap("Continue to Cosmos"),
                
                // Main App - Daily Reading (45-60s)
                .wait(1),
                .highlightFeature("Today's Cosmic Energy", duration: 1),
                .swipe(.up),
                .wait(0.5),
                .highlightFeature("Daily Affirmation", duration: 1),
                
                // Weekly tab (60-70s)
                .tap("Week"),
                .wait(1),
                .swipe(.up),
                .wait(0.5),
                
                // Profile tab (70-75s)
                .tap("Profile"),
                .wait(2),
                .highlightFeature("Your Cosmic Profile", duration: 1),
                .wait(2) // End on profile
            ]
        }
    }
}

enum DemoStep {
    case wait(Double)
    case tap(String)
    case tapButton(String)
    case tapOption(Int)
    case tapOptionContaining(String)
    case type(String, in: String)
    case swipe(SwipeDirection)
    case setDate(Date)
    case highlightFeature(String, duration: Double)
    case showZodiac(String)
    case answerMBTIQuestions(count: Int)
    case callback(() -> Void)
    
    enum SwipeDirection {
        case up, down, left, right
    }
}

// MARK: - Demo Coordinator

@Observable
class DemoCoordinator {
    static let shared = DemoCoordinator()
    
    var isRunning = false
    var currentStep = 0
    var currentFlow: DemoFlow?
    
    private var timer: Timer?
    
    func start(flow: DemoFlow = .fullJourney) {
        guard DemoMode.isEnabled else { return }
        
        isRunning = true
        currentFlow = flow
        currentStep = 0
        
        executeSteps(flow.steps)
    }
    
    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    private func executeSteps(_ steps: [DemoStep]) {
        var index = 0
        
        func processNext() {
            guard index < steps.count, isRunning else {
                isRunning = false
                return
            }
            
            let step = steps[index]
            index += 1
            currentStep = index
            
            execute(step) {
                processNext()
            }
        }
        
        processNext()
    }
    
    private func execute(_ step: DemoStep, completion: @escaping () -> Void) {
        let speedMultiplier = DemoMode.speedMultiplier > 0 ? DemoMode.speedMultiplier : 0.5
        
        switch step {
        case .wait(let duration):
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * speedMultiplier) {
                completion()
            }
            
        case .tap(let label):
            DemoTouchHelper.tap(label: label)
            completion()
            
        case .tapButton(let label):
            DemoTouchHelper.tapButton(label: label)
            completion()
            
        case .tapOption(let index):
            DemoTouchHelper.tapOption(at: index)
            completion()
            
        case .tapOptionContaining(let text):
            DemoTouchHelper.tapOption(containing: text)
            completion()
            
        case .type(let text, let field):
            DemoTouchHelper.type(text: text, in: field)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 * speedMultiplier) {
                completion()
            }
            
        case .swipe(let direction):
            DemoTouchHelper.swipe(direction)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 * speedMultiplier) {
                completion()
            }
            
        case .setDate(let date):
            DemoTouchHelper.setDate(date)
            completion()
            
        case .highlightFeature(let feature, let duration):
            DemoTouchHelper.highlight(feature: feature)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration * speedMultiplier) {
                completion()
            }
            
        case .showZodiac(let sign):
            DemoTouchHelper.showZodiac(sign)
            completion()
            
        case .answerMBTIQuestions(let count):
            DemoTouchHelper.answerMBTI(count: count) {
                completion()
            }
            return // completion called in callback
            
        case .callback(let action):
            action()
            completion()
        }
    }
}

// MARK: - Demo Touch Helper

/// Simulates user interactions for demo purposes
enum DemoTouchHelper {
    /// Post notifications that views can observe to trigger actions
    static func tap(label: String) {
        NotificationCenter.default.post(
            name: .demoTap,
            object: nil,
            userInfo: ["label": label]
        )
    }
    
    static func tapButton(label: String) {
        tap(label: label)
    }
    
    static func tapOption(at index: Int) {
        NotificationCenter.default.post(
            name: .demoTapOption,
            object: nil,
            userInfo: ["index": index]
        )
    }
    
    static func tapOption(containing text: String) {
        NotificationCenter.default.post(
            name: .demoTapOptionContaining,
            object: nil,
            userInfo: ["text": text]
        )
    }
    
    static func type(text: String, in field: String) {
        NotificationCenter.default.post(
            name: .demoType,
            object: nil,
            userInfo: ["text": text, "field": field]
        )
    }
    
    static func swipe(_ direction: DemoStep.SwipeDirection) {
        NotificationCenter.default.post(
            name: .demoSwipe,
            object: nil,
            userInfo: ["direction": direction]
        )
    }
    
    static func setDate(_ date: Date) {
        NotificationCenter.default.post(
            name: .demoSetDate,
            object: nil,
            userInfo: ["date": date]
        )
    }
    
    static func highlight(feature: String) {
        NotificationCenter.default.post(
            name: .demoHighlight,
            object: nil,
            userInfo: ["feature": feature]
        )
    }
    
    static func showZodiac(_ sign: String) {
        NotificationCenter.default.post(
            name: .demoShowZodiac,
            object: nil,
            userInfo: ["sign": sign]
        )
    }
    
    static func answerMBTI(count: Int, completion: @escaping () -> Void) {
        NotificationCenter.default.post(
            name: .demoAnswerMBTI,
            object: nil,
            userInfo: ["count": count, "completion": completion]
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let demoTap = Notification.Name("aura.demo.tap")
    static let demoTapOption = Notification.Name("aura.demo.tapOption")
    static let demoTapOptionContaining = Notification.Name("aura.demo.tapOptionContaining")
    static let demoType = Notification.Name("aura.demo.type")
    static let demoSwipe = Notification.Name("aura.demo.swipe")
    static let demoSetDate = Notification.Name("aura.demo.setDate")
    static let demoHighlight = Notification.Name("aura.demo.highlight")
    static let demoShowZodiac = Notification.Name("aura.demo.showZodiac")
    static let demoAnswerMBTI = Notification.Name("aura.demo.answerMBTI")
}

// MARK: - View Modifiers

extension View {
    /// Enables demo automation for this view
    func demoTap(_ label: String, action: @escaping () -> Void) -> some View {
        self.onReceive(NotificationCenter.default.publisher(for: .demoTap)) { notification in
            if let tapLabel = notification.userInfo?["label"] as? String,
               tapLabel == label {
                action()
            }
        }
    }
    
    /// Auto-type text binding when demo mode is active
    func demoAutoType(_ text: Binding<String>, field: String) -> some View {
        self.onReceive(NotificationCenter.default.publisher(for: .demoType)) { notification in
            if let fieldName = notification.userInfo?["field"] as? String,
               fieldName == field,
               let input = notification.userInfo?["text"] as? String {
                // Animate typing
                let characters = Array(input)
                for (index, char) in characters.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.05) {
                        text.wrappedValue.append(char)
                    }
                }
            }
        }
    }
}

// MARK: - Quick Actions Overlay

/// Optional overlay for manual demo control
struct DemoControlOverlay: View {
    @State private var showControls = false
    
    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: { showControls.toggle() }) {
                    Image(systemName: "film.fill")
                        .font(.title2)
                        .padding()
                        .background(Color.purple.opacity(0.8))
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
                .padding()
            }
            Spacer()
        }
        .sheet(isPresented: $showControls) {
            DemoControlsView()
        }
    }
}

struct DemoControlsView: View {
    var body: some View {
        NavigationView {
            List {
                Section("Quick Flows") {
                    Button("Full Journey (75s)") {
                        DemoCoordinator.shared.start(flow: .fullJourney)
                    }
                    Button("Onboarding Only") {
                        DemoCoordinator.shared.start(flow: .onboarding)
                    }
                    Button("MBTI Test") {
                        DemoCoordinator.shared.start(flow: .mbtiTest)
                    }
                    Button("Daily Reading") {
                        DemoCoordinator.shared.start(flow: .dailyReading)
                    }
                }
                
                Section("Settings") {
                    Button("Reset Demo State") {
                        DemoMode.reset()
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Demo Recorder")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#endif
