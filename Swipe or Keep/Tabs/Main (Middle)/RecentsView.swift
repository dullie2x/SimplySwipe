import SwiftUI
import Photos

struct RecentsView: View {
    @State private var isLoading = true
    @State private var hasRecentMedia = false
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            
            if isLoading {
                ProgressView("Loading Recents...")
                    .onAppear(perform: checkForRecentAssets)
            } else if !hasRecentMedia {
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
                FilteredVertScroll(filterOptions: getRecentFilterOptions())
            }
            
            Spacer()
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
    
    /// Generate a PHFetchOptions instance for the last 7 days
    private func getRecentFilterOptions() -> PHFetchOptions {
        let fetchOptions = PHFetchOptions()
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        // Get the swiped media identifiers from SwipedMediaManager
        let swipedIdentifiers = Array(SwipedMediaManager.shared.getSwipedMediaIdentifiers())
        
        // Create the appropriate predicate based on whether we have swiped assets
        if swipedIdentifiers.isEmpty {
            // If no swiped media yet, just filter by recent date
            fetchOptions.predicate = NSPredicate(format: "creationDate >= %@", sevenDaysAgo as NSDate)
        } else {
            // Filter by recent date AND exclude already swiped media
            fetchOptions.predicate = NSPredicate(format: "creationDate >= %@ AND NOT (localIdentifier IN %@)",
                                              sevenDaysAgo as NSDate, swipedIdentifiers)
        }
        
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return fetchOptions
    }
}
