import SwiftUI
import Photos

struct ScreenshotsView: View {
    @State private var isLoading = true
    @State private var hasScreenshots = false
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 10) {
            if isLoading {
                ProgressView("Loading Screenshots...")
                    .onAppear(perform: checkForScreenshots)
            } else if !hasScreenshots {
                Text("No screenshots found.")
                    .font(.title)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                FilteredSwipeStack(filterOptions: getScreenshotFilterOptions())
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarHidden(true)
    }
    
    /// Check if there are ANY screenshots (faster than fetching all)
    private func checkForScreenshots() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = getScreenshotFilterOptions()
            fetchOptions.fetchLimit = 1 // Only need to check if at least one exists
            
            let results = PHAsset.fetchAssets(with: fetchOptions)
            let hasScreenshots = results.count > 0
            
            DispatchQueue.main.async {
                self.hasScreenshots = hasScreenshots
                self.isLoading = false
            }
        }
    }
    
    /// Generate a PHFetchOptions instance for screenshots
    private func getScreenshotFilterOptions() -> PHFetchOptions {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "mediaSubtype == %d", PHAssetMediaSubtype.photoScreenshot.rawValue)
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return fetchOptions
    }
}

#Preview {
    ScreenshotsView()
}
