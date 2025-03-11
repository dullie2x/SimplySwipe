import SwiftUI
import Photos

struct FavoritesView: View {
    @State private var isLoading = true
    @State private var hasFavorites = false
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 10) {
            // Custom Back Button would go here
            
            if isLoading {
                ProgressView("Loading Favorites...")
                    .onAppear(perform: checkForFavorites)
            } else if !hasFavorites {
                Text("No favorite media found.")
                    .font(.title)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                FilteredSwipeStack(filterOptions: getFavoriteFilterOptions())
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarHidden(true)
    }
    
    /// Just check if there are ANY favorites (faster than fetching all)
    private func checkForFavorites() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "isFavorite == YES")
            fetchOptions.fetchLimit = 1 // Only need to check if at least one exists
            
            let results = PHAsset.fetchAssets(with: fetchOptions)
            let hasFavorites = results.count > 0
            
            DispatchQueue.main.async {
                self.hasFavorites = hasFavorites
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
