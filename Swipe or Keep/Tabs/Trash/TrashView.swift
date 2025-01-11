import SwiftUI
import Photos

struct TrashView: View {
    @ObservedObject var swipedMediaManager = SwipedMediaManager.shared
    @State private var selectedItems: Set<String> = []
    @State private var isSelectionMode: Bool = false
    @State private var selectedAssetForFullScreen: PHAsset?

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationView {
            VStack {
                if swipedMediaManager.trashedMediaAssets.isEmpty {
                    VStack {
                        Text("Nothing to see here...")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                } else {
                    if isSelectionMode {
                        // Toolbar for Selection Mode Actions
                        HStack {
                            Button(action: toggleSelectAll) {
                                Text(selectedItems.count == swipedMediaManager.trashedMediaAssets.count ? "Deselect All" : "Select All")
                            }
                            Spacer()
                            Button(action: recoverAll) {
                                Text("Recover")
                                    .foregroundColor(selectedItems.isEmpty ? .gray : .green)
                            }
                            Spacer()
                            Button(action: deleteAll) {
                                Text("Delete")
                                    .foregroundColor(selectedItems.isEmpty ? .gray : .red)
                            }
                        }
                        .padding()
                    }

                    // Grid of thumbnails
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(swipedMediaManager.trashedMediaAssets, id: \.localIdentifier) { asset in
                                MediaThumbnailView(
                                    asset: asset,
                                    isSelected: selectedItems.contains(asset.localIdentifier),
                                    isSelectionMode: isSelectionMode
                                ) {
                                    if isSelectionMode {
                                        toggleSelection(for: asset.localIdentifier)
                                    } else {
                                        openFullScreen(for: asset)
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .toolbar {
                // Toggle for Viewing/Selection Mode
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !swipedMediaManager.trashedMediaAssets.isEmpty {
                        Button(action: toggleSelectionMode) {
                            Text(isSelectionMode ? "Cancel" : "Select")
                        }
                    }
                }
            }
            .sheet(item: $selectedAssetForFullScreen) { asset in
                FullScreenMediaView(
                    initialAsset: asset,
                    allAssets: swipedMediaManager.trashedMediaAssets,
                    onClose: { selectedAssetForFullScreen = nil }
                )
            }
        }
    }

    // Toggle Selection Mode
    private func toggleSelectionMode() {
        isSelectionMode.toggle()
        selectedItems.removeAll() // Clear selection when switching modes
    }

    // Toggle selection for a single thumbnail
    private func toggleSelection(for id: String) {
        if selectedItems.contains(id) {
            selectedItems.remove(id)
        } else {
            selectedItems.insert(id)
        }
    }

    // Select/Deselect all items
    private func toggleSelectAll() {
        if selectedItems.count == swipedMediaManager.trashedMediaAssets.count {
            selectedItems.removeAll()
        } else {
            selectedItems = Set(swipedMediaManager.trashedMediaAssets.map { $0.localIdentifier })
        }
    }

    // Recover all selected items
    private func recoverAll() {
        guard !selectedItems.isEmpty else { return }
        swipedMediaManager.recoverItems(with: selectedItems)
        selectedItems.removeAll()
    }

    // Delete all selected items
    private func deleteAll() {
        guard !selectedItems.isEmpty else { return }

        // Fetch the PHAssets corresponding to the selected identifiers
        let assetsToDelete = swipedMediaManager.trashedMediaAssets.filter { selectedItems.contains($0.localIdentifier) }

        // Perform the deletion
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    // Update the manager and UI
                    let deletedIdentifiers = Set(assetsToDelete.map { $0.localIdentifier })
                    swipedMediaManager.deleteItems(with: deletedIdentifiers)
                    selectedItems.removeAll()
                } else if let error = error {
                    print("Failed to delete assets: \(error)")
                }
            }
        }
    }

    // Open full-screen viewer
    private func openFullScreen(for asset: PHAsset) {
        selectedAssetForFullScreen = asset
    }
}



    private func getThumbnail(from asset: PHAsset) -> UIImage? {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat // Request high-quality images
        options.resizeMode = .exact // Ensures images match the requested size
        options.isSynchronous = true // Synchronous to simplify this implementation

        var thumbnail: UIImage?
        manager.requestImage(for: asset,
                             targetSize: CGSize(width: 300, height: 300), // Higher resolution target
                             contentMode: .aspectFill, // Crops to fill the target size
                             options: options) { result, _ in
            thumbnail = result
        }
        return thumbnail
    }

    private func getFullResolutionImage(from asset: PHAsset) -> UIImage? {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = true

        var fullResolutionImage: UIImage?
        manager.requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) { result, _ in
            fullResolutionImage = result
        }
        return fullResolutionImage
    }


extension PHAsset: @retroactive Identifiable {
    public var id: String {
        self.localIdentifier
    }
}

