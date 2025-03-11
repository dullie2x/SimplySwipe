import Foundation
import Photos

@MainActor
class SwipedMediaManager: NSObject, ObservableObject {
    static let shared = SwipedMediaManager()
    
    private let swipedKey = "swipedMedia"
    private let trashKey = "trashedItems"

    private var swipedMedia: Set<String> = []
    private var trashedItems: Set<String> = []

    @Published var trashedMediaAssets: [PHAsset] = []
    
    // Add a background queue for photo fetching
    private let fetchQueue = DispatchQueue(label: "com.app.swipedMediaManager.fetch", qos: .utility)

    private override init() {
        super.init()
        loadSwipedMedia()
        loadTrashedItems()
        
        // Register for photo library change notifications
        PHPhotoLibrary.shared().register(self)
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func addSwipedMedia(_ asset: PHAsset, toTrash: Bool = false) {
        let identifier = asset.localIdentifier
        if toTrash {
            trashedItems.insert(identifier)
            saveTrashedItems()
        }
        swipedMedia.insert(identifier)
        saveSwipedMedia()
        updateTrashedMediaAssets()
    }

    func recoverItems(with identifiers: Set<String>) {
        trashedItems.subtract(identifiers)
        saveTrashedItems()
        updateTrashedMediaAssets()
    }

    func deleteItems(with identifiers: Set<String>) {
        trashedItems.subtract(identifiers)
        saveTrashedItems()
        updateTrashedMediaAssets()
    }

    func isMediaSwiped(_ asset: PHAsset) -> Bool {
        swipedMedia.contains(asset.localIdentifier)
    }

    private func saveSwipedMedia() {
        UserDefaults.standard.set(Array(swipedMedia), forKey: swipedKey)
    }

    private func loadSwipedMedia() {
        swipedMedia = Set(UserDefaults.standard.stringArray(forKey: swipedKey) ?? [])
    }

    private func saveTrashedItems() {
        UserDefaults.standard.set(Array(trashedItems), forKey: trashKey)
    }

    private func loadTrashedItems() {
        trashedItems = Set(UserDefaults.standard.stringArray(forKey: trashKey) ?? [])
        updateTrashedMediaAssets()
    }

    private func updateTrashedMediaAssets() {
        // Skip updating if there are no trashed items
        guard !trashedItems.isEmpty else {
            self.trashedMediaAssets = []
            return
        }
        
        // Use fetchQueue to avoid blocking the main thread
        fetchQueue.async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "localIdentifier IN %@", Array(self.trashedItems))
            let fetchedAssets = PHAsset.fetchAssets(with: fetchOptions)
            
            // Process in batches to avoid creating large arrays
            var assets: [PHAsset] = []
            assets.reserveCapacity(fetchedAssets.count)
            
            // Use autoreleasepool to minimize memory pressure during enumeration
            autoreleasepool {
                fetchedAssets.enumerateObjects { asset, _, _ in
                    assets.append(asset)
                }
            }
            
            // Clean up any identifiers for assets that no longer exist
            let existingIdentifiers = Set(assets.map { $0.localIdentifier })
            let nonExistentIdentifiers = self.trashedItems.subtracting(existingIdentifiers)
            
            // Update on main thread
            Task { @MainActor in
                // Remove identifiers for assets that no longer exist
                if !nonExistentIdentifiers.isEmpty {
                    self.trashedItems.subtract(nonExistentIdentifiers)
                    self.saveTrashedItems()
                }
                
                self.trashedMediaAssets = assets
            }
        }
    }
}

// Photo library change observer implementation
extension SwipedMediaManager: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        // Check if we need to update our asset list
        var needsUpdate = false
        
        // Check if any of our tracked assets have changed
        for (index, asset) in trashedMediaAssets.enumerated() {
            if let details = changeInstance.changeDetails(for: asset) {
                if details.objectWasDeleted {
                    needsUpdate = true
                    break
                }
            }
        }
        
        // Update asset list when photo library changes
        if needsUpdate {
            Task { @MainActor in
                self.updateTrashedMediaAssets()
            }
        }
    }
}
