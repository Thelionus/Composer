import SwiftUI

// MARK: - ContentView

/// Root navigation container. Uses NavigationStack with ProjectListView as root.
struct ContentView: View {
    @EnvironmentObject private var projectViewModel: ProjectViewModel

    var body: some View {
        NavigationStack {
            ProjectListView()
        }
        .tint(.purple)
    }
}

#Preview {
    ContentView()
        .environmentObject(ProjectViewModel())
}
