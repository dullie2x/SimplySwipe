//
//  ScreenshotsView.swift
//  Swipe or Keep
//
//  Created by Gbolade Ariyo on 12/28/24.
//

import SwiftUI
import Photos

struct ScreenshotsView: View {
    @State private var isLoading = true
    @State private var screenshotAssets: [PHAsset] = []
    @Environment(\.presentationMode) var presentationMode // To handle navigation

    var body: some View {
        VStack(spacing: 10) { // Reduced spacing between back button and content
            // Custom Back Button

            if isLoading {
                ProgressView("Please Wait...")
                    .onAppear(perform: fetchScreenshotAssets)
            } else if screenshotAssets.isEmpty {
                Text("No screenshots found.")
                    .font(.title)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                FilteredSwipeStack(filterOptions: getScreenshotFilterOptions())
            }
        }
        .background(Color.black.ignoresSafeArea()) // Black background for the entire view
        .navigationBarHidden(true) // Hide the default navigation bar
    }

    /// Fetch all screenshots from the photo library
    private func fetchScreenshotAssets() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "mediaSubtype == %d", PHAssetMediaSubtype.photoScreenshot.rawValue)
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let results = PHAsset.fetchAssets(with: fetchOptions)
            var assets: [PHAsset] = []
            results.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }

            DispatchQueue.main.async {
                self.screenshotAssets = assets
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
