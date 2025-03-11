import SwiftUI
import Photos

struct TrashView: View {
    @ObservedObject var swipedMediaManager = SwipedMediaManager.shared
    @State private var selectedItems: Set<String> = []
    @State private var isSelectionMode: Bool = false
    @State private var selectedAssetForFullScreen: PHAsset?
    @State private var isDeleting = false
    @State private var isRecovering = false
    
    // Use adaptive columns based on device size
    private var columns: [GridItem] {
        let width = UIScreen.main.bounds.width
        let columnCount = width > 700 ? 4 : 3  // More columns on iPad
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount)
    }

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
                            .disabled(isDeleting || isRecovering)
                            
                            Spacer()
                            
                            Button(action: recoverAll) {
                                if isRecovering {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                } else {
                                    Text("Recover")
                                        .foregroundColor(selectedItems.isEmpty ? .gray : .green)
                                }
                            }
                            .disabled(selectedItems.isEmpty || isDeleting || isRecovering)
                            
                            Spacer()
                            
                            Button(action: deleteAll) {
                                if isDeleting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                } else {
                                    Text("Delete")
                                        .foregroundColor(selectedItems.isEmpty ? .gray : .red)
                                }
                            }
                            .disabled(selectedItems.isEmpty || isDeleting || isRecovering)
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
            .navigationTitle("Trash")
            .toolbar {
                // Toggle for Viewing/Selection Mode
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !swipedMediaManager.trashedMediaAssets.isEmpty {
                        Button(action: toggleSelectionMode) {
                            Text(isSelectionMode ? "Cancel" : "Select")
                        }
                        .disabled(isDeleting || isRecovering)
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
            .disabled(isDeleting || isRecovering) // Disable interaction during operations
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
        
        isRecovering = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            swipedMediaManager.recoverItems(with: selectedItems)
            
            DispatchQueue.main.async {
                selectedItems.removeAll()
                isRecovering = false
                isSelectionMode = false // Exit selection mode after operation
            }
        }
    }

    // Delete all selected items
    private func deleteAll() {
        guard !selectedItems.isEmpty else { return }
        
        isDeleting = true

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
                    isSelectionMode = false // Exit selection mode after operation
                } else if let error = error {
                    print("Failed to delete assets: \(error)")
                }
                isDeleting = false
            }
        }
    }

    // Open full-screen viewer
    private func openFullScreen(for asset: PHAsset) {
        selectedAssetForFullScreen = asset
    }
}

extension PHAsset: @retroactive Identifiable {
    public var id: String {
        self.localIdentifier
    }
}
