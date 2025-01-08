import SwiftUI
import Photos

struct RecentsView: View {
    @State private var isLoading = true
    @State private var recentAssets: [PHAsset] = []
    @Environment(\.presentationMode) var presentationMode // To handle navigation

    var body: some View {
        VStack(spacing: 10) { // Reduced spacing between back button and content
            // Custom Back Button

            if isLoading {
                ProgressView("Loading Recents...")
                    .onAppear(perform: fetchRecentAssets)
            } else if recentAssets.isEmpty {
                Text("No recent media found.")
                    .font(.title)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                FilteredSwipeStack(filterOptions: getRecentFilterOptions())
            }
        }
        .background(Color.black.ignoresSafeArea()) // Black background for the entire view
        .navigationBarHidden(true) // Hide the default navigation bar
    }

    /// Fetch media assets from the last 48 hours
    private func fetchRecentAssets() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
            fetchOptions.predicate = NSPredicate(format: "creationDate >= %@", twoDaysAgo as NSDate)
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let results = PHAsset.fetchAssets(with: fetchOptions)
            var assets: [PHAsset] = []
            results.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }

            DispatchQueue.main.async {
                self.recentAssets = assets
                self.isLoading = false
            }
        }
    }

    /// Generate a PHFetchOptions instance for the last 48 hours
    private func getRecentFilterOptions() -> PHFetchOptions {
        let fetchOptions = PHFetchOptions()
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        fetchOptions.predicate = NSPredicate(format: "creationDate >= %@", twoDaysAgo as NSDate)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return fetchOptions
    }
}

#Preview {
    RecentsView()
}
