import SwiftUI

@main
struct ComposerApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @StateObject private var projectViewModel = ProjectViewModel()

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                ContentView()
                    .environmentObject(projectViewModel)
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .environmentObject(projectViewModel)
            }
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.15), Color(red: 0.1, green: 0.05, blue: 0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // App icon placeholder
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.purple, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)

                    Image(systemName: "music.mic")
                        .font(.system(size: 52, weight: .light))
                        .foregroundColor(.white)
                }

                VStack(spacing: 12) {
                    Text("VocalScore Pro")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("Transform your voice into\norchestral music scores")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 20) {
                    OnboardingFeatureRow(icon: "mic.fill", color: .red,
                        title: "Sing Your Ideas",
                        description: "Record your melody and rhythm naturally")

                    OnboardingFeatureRow(icon: "waveform", color: .purple,
                        title: "AI Transcription",
                        description: "Automatic pitch & rhythm detection")

                    OnboardingFeatureRow(icon: "pianokeys", color: .blue,
                        title: "Full Orchestra",
                        description: "25+ orchestral instruments at your fingertips")

                    OnboardingFeatureRow(icon: "square.and.arrow.up", color: .green,
                        title: "Export Anywhere",
                        description: "MusicXML, MIDI and more")
                }
                .padding(.horizontal, 32)

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        hasCompletedOnboarding = true
                    }
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: [Color.purple, Color.blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .padding(.horizontal, 32)
                }

                Text("By continuing you agree to our Privacy Policy")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.bottom, 32)
            }
        }
    }
}

struct OnboardingFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
            }

            Spacer()
        }
    }
}
