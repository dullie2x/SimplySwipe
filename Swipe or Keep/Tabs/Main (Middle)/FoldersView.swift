import SwiftUI
import Photos

struct FoldersView: View {
    @State private var folders: [PHAssetCollection] = [] // Store folders as PHAssetCollections
    @State private var selectedFolder: PHAssetCollection? = nil // Selected folder for navigation
    @Environment(\.presentationMode) var presentationMode // To handle navigation

    var body: some View {
        VStack(spacing: 5) { // Reduced spacing between back button and tiles
            // Custom Back Button
            HStack {
                Button(action: {
                    presentationMode.wrappedValue.dismiss() // Navigate back
                }) {
                    Image(systemName: "arrow.left.circle") // Back arrow inside a circle
                        .resizable()
                        .frame(width: 30, height: 30) // Adjust the size of the icon
                        .foregroundColor(.white) // White color for the icon
                }
                .padding(.leading, 15) // Add some padding to the left
                .padding(.top, 10) // Add top padding for alignment
                Spacer()
            }

            if folders.isEmpty {
                ProgressView("Please Wait...")
                    .onAppear(perform: fetchFolders)
            } else {
                ZStack {
                    StackedBlocksView(
                        blockTitles: folders.map { $0.localizedTitle ?? "Unknown Folder" },
                        actionHandler: { index in
                            selectedFolder = folders[index]
                        }
                    )
                    .background(Color.black)

                    NavigationLink(
                        destination: selectedFolder.flatMap { folder in
                            FolderContentsView(folder: folder)
                        },
                        isActive: Binding(
                            get: { selectedFolder != nil },
                            set: { if !$0 { selectedFolder = nil } }
                        )
                    ) {
                        EmptyView() // Transparent navigation trigger
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea()) // Black background for the entire view
        .navigationBarHidden(true) // Hide the default navigation bar
        .navigationViewStyle(StackNavigationViewStyle()) // Consistent rendering
    }


    /// Fetch all folders (albums) on the device
    func fetchFolders() {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                print("Photo access denied")
                return
            }

            let allFolders = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            var tempFolders: [PHAssetCollection] = []

            allFolders.enumerateObjects { collection, _, _ in
                if PHAsset.fetchAssets(in: collection, options: nil).count > 0 {
                    tempFolders.append(collection)
                }
            }

            DispatchQueue.main.async {
                self.folders = tempFolders
            }
        }
    }
}

import SwiftUI
import Photos

struct FolderContentsView: View {
    let folder: PHAssetCollection
    @State private var isLoading = true
    @State private var assets: [PHAsset] = []
    @Environment(\.presentationMode) var presentationMode // To handle navigation

    var body: some View {
        VStack(spacing: 10) { // Reduced spacing between back button and content
            // Custom Back Button

            if isLoading {
                ProgressView("Loading \(folder.localizedTitle ?? "Folder")...")
                    .onAppear(perform: fetchAssets)
            } else if assets.isEmpty {
                Text("No media found in this folder.")
                    .font(.title)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                FilteredSwipeStack(filterOptions: createFilterOptions())
            }
        }
        .background(Color.black.ignoresSafeArea()) // Black background for the entire view
        .navigationBarHidden(true) // Hide the default navigation bar
    }

    /// Fetch assets for the selected folder
    private func fetchAssets() {
        DispatchQueue.global(qos: .userInitiated).async {
            let assetsResult = PHAsset.fetchAssets(in: folder, options: nil)
            var tempAssets: [PHAsset] = []
            assetsResult.enumerateObjects { asset, _, _ in
                tempAssets.append(asset)
            }

            DispatchQueue.main.async {
                self.assets = tempAssets
                self.isLoading = false
            }
        }
    }

    /// Generate a `PHFetchOptions` specific to this folder
    private func createFilterOptions() -> PHFetchOptions {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        // Use only the assets in the current folder
        fetchOptions.predicate = NSPredicate(format: "SELF IN %@", assets)
        return fetchOptions
    }
}
