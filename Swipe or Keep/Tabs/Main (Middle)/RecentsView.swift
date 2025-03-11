import SwiftUI
import Photos

struct RecentsView: View {
    @State private var isLoading = true
    @State private var hasRecentMedia = false
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 10) {
            // Custom Back Button would go here
            
            if isLoading {
                ProgressView("Loading Recents...")
                    .onAppear(perform: checkForRecentAssets)
            } else if !hasRecentMedia {
                Text("No recent media found.")
                    .font(.title)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                FilteredSwipeStack(filterOptions: getRecentFilterOptions())
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarHidden(true)
    }
    
    /// Just check if there are ANY recent assets (faster than fetching all)
    private func checkForRecentAssets() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = getRecentFilterOptions()
            fetchOptions.fetchLimit = 1 // Only need to check if at least one exists
            
            let results = PHAsset.fetchAssets(with: fetchOptions)
            let hasRecentMedia = results.count > 0
            
            DispatchQueue.main.async {
                self.hasRecentMedia = hasRecentMedia
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
