import SwiftUI

struct MainView: View {
    var body: some View {
        NavigationView {
            VStack {
                // App Name Header
                Text("Simply Swipe")
                    .font(.largeTitle.bold()) // Bold and large font
                    .foregroundColor(.white) // White text color
                    .padding(.top, 20) // Add some top padding
                    .padding(.bottom, 10) // Add spacing below the title

                // Navigation Blocks
                NavStackedBlocksView(
                    blockTitles: ["Recents", "Year", "Screenshots", "Folders", "Favorites"]
                )
            }
            .background(Color.black.ignoresSafeArea()) // Black background for the entire view
            .navigationBarHidden(true) // Hide the navigation bar
            .toolbar {
                // Ensure the back button is explicitly disabled
                ToolbarItem(placement: .navigationBarLeading) {
                    EmptyView() // Removes the back button
                }
            }
        }
    }
}

#Preview {
    MainView()
}
