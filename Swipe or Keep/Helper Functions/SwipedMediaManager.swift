import Foundation
import Photos

class SwipedMediaManager: ObservableObject {
    static let shared = SwipedMediaManager()
    
    private let swipedKey = "swipedMedia"
    private let trashKey = "trashedItems"

    // Properties to track swiped and trashed items
    private var swipedMedia: Set<String> = []
    private var trashedItems: Set<String> = []

    // Observable arrays for UI updates
    @Published var trashedMediaAssets: [PHAsset] = []

    private init() {
        loadSwipedMedia()
        loadTrashedItems()
    }

    // MARK: - Public Methods

    // Add media to swiped list
    func addSwipedMedia(_ asset: PHAsset, toTrash: Bool = false) {
        let identifier = asset.localIdentifier
        
        // If swiping left, move to trash
        if toTrash {
            trashedItems.insert(identifier)
            saveTrashedItems()
            updateTrashedMediaAssets()
        }

        // Add to general swiped list to ensure it doesn't reappear
        swipedMedia.insert(identifier)
        saveSwipedMedia()
    }

    // Recover items from trash
    func recoverItems(with identifiers: Set<String>) {
        trashedItems.subtract(identifiers)
        saveTrashedItems()
        updateTrashedMediaAssets()
    }

    // Permanently delete items from trash
    func deleteItems(with identifiers: Set<String>) {
        trashedItems.subtract(identifiers)
        saveTrashedItems()
        updateTrashedMediaAssets()
    }

    // Check if media is swiped (either kept or trashed)
    func isMediaSwiped(_ asset: PHAsset) -> Bool {
        let identifier = asset.localIdentifier
        return swipedMedia.contains(identifier)
    }

    // MARK: - Private Persistence Logic

    // Save swiped media to UserDefaults
    private func saveSwipedMedia() {
        UserDefaults.standard.set(Array(swipedMedia), forKey: swipedKey)
    }

    // Load swiped media from UserDefaults
    private func loadSwipedMedia() {
        let saved = UserDefaults.standard.array(forKey: swipedKey) as? [String] ?? []
        swipedMedia = Set(saved)
    }

    // Save trashed items to UserDefaults
    private func saveTrashedItems() {
        UserDefaults.standard.set(Array(trashedItems), forKey: trashKey)
    }

    // Load trashed items from UserDefaults
    private func loadTrashedItems() {
        let saved = UserDefaults.standard.array(forKey: trashKey) as? [String] ?? []
        trashedItems = Set(saved)
        updateTrashedMediaAssets()
    }

    // Update trashed media assets for UI
    private func updateTrashedMediaAssets() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "localIdentifier IN %@", Array(trashedItems))
        let fetchedAssets = PHAsset.fetchAssets(with: fetchOptions)

        var assets: [PHAsset] = []
        fetchedAssets.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        DispatchQueue.main.async {
            self.trashedMediaAssets = assets
        }
    }
}
