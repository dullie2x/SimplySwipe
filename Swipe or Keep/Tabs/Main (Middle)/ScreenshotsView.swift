import SwiftUI
import Photos

struct ScreenshotsView: View {
    @State private var isLoading = true
    @State private var hasScreenshots = false
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            
            if isLoading {
                ProgressView("Loading Screenshots...")
                    .onAppear(perform: checkForScreenshots)
            } else if !hasScreenshots {
                VStack(spacing: 24) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 70))
                        .foregroundColor(.green)
                    
                    Text("All Done!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    // Return to Home button
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Return to Home")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 24)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(LinearGradient(
                                        gradient: Gradient(colors: [Color.green.opacity(0.7), Color.blue.opacity(0.7)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                            )
                            .shadow(color: Color.green.opacity(0.3), radius: 5, x: 0, y: 2)
                    }
                    .padding(.top, 20)
                }
                .padding(32)
            } else {
                // UPDATED: Use FilteredVertScroll instead of FilteredSwipeStack
                FilteredVertScroll(filterOptions: getScreenshotFilterOptions())
            }
            
            Spacer()
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
        
        // Get the swiped media identifiers from SwipedMediaManager
        let swipedIdentifiers = Array(SwipedMediaManager.shared.getSwipedMediaIdentifiers())
        
        // Create the appropriate predicate based on whether we have swiped assets
        if swipedIdentifiers.isEmpty {
            // If no swiped media yet, just filter by screenshot type
            fetchOptions.predicate = NSPredicate(format: "mediaSubtype == %d", PHAssetMediaSubtype.photoScreenshot.rawValue)
        } else {
            // Filter by screenshot type AND exclude already swiped media
            fetchOptions.predicate = NSPredicate(format: "mediaSubtype == %d AND NOT (localIdentifier IN %@)",
                                              PHAssetMediaSubtype.photoScreenshot.rawValue, swipedIdentifiers)
        }
        
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return fetchOptions
    }
}

#Preview {
    ScreenshotsView()
}
