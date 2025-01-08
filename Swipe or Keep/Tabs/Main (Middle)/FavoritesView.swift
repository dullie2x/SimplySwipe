import SwiftUI
import Photos

struct FavoritesView: View {
    @State private var isLoading = true
    @State private var favoriteAssets: [PHAsset] = []
    @Environment(\.presentationMode) var presentationMode // To handle navigation

    var body: some View {
        VStack(spacing: 10) { // Reduced spacing between back button and content
            // Custom Back Button

            if isLoading {
                ProgressView("Loading Favorites...")
                    .onAppear(perform: fetchFavoriteAssets)
            } else if favoriteAssets.isEmpty {
                Text("No favorite media found.")
                    .font(.title)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                FilteredSwipeStack(filterOptions: getFavoriteFilterOptions())
            }
        }
        .background(Color.black.ignoresSafeArea()) // Black background for the entire view
        .navigationBarHidden(true) // Hide the default navigation bar
    }

    /// Fetch media assets marked as favorites
    private func fetchFavoriteAssets() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "isFavorite == YES")
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let results = PHAsset.fetchAssets(with: fetchOptions)
            var assets: [PHAsset] = []
            results.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }

            DispatchQueue.main.async {
                self.favoriteAssets = assets
                self.isLoading = false
            }
        }
    }

    /// Generate a PHFetchOptions instance for favorites
    private func getFavoriteFilterOptions() -> PHFetchOptions {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "isFavorite == YES")
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return fetchOptions
    }
}

#Preview {
    FavoritesView()
}
