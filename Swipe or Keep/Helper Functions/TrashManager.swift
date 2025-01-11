//import Foundation
//import Photos
//
//class TrashManager: ObservableObject {
//    static let shared = TrashManager()
//    private let trashKey = "trashedItems"
//
//    @Published var trashedItems: [PHAsset] = [] {
//        didSet {
//            saveTrashedItems()
//        }
//    }
//
//    private init() {
//        loadTrashedItems()
//    }
//
//    // Add item to trash
//    func addToTrash(_ asset: PHAsset) {
//        if !trashedItems.contains(where: { $0.localIdentifier == asset.localIdentifier }) {
//            trashedItems.append(asset)
//        }
//    }
//
//    // Remove item from trash
//    func removeFromTrash(_ asset: PHAsset) {
//        trashedItems.removeAll { $0.localIdentifier == asset.localIdentifier }
//    }
//
//    // Recover multiple items
//    func recoverItems(with ids: Set<String>) {
//        trashedItems.removeAll { ids.contains($0.localIdentifier) }
//    }
//
//    // Delete multiple items
//    func deleteItems(with ids: Set<String>) {
//        trashedItems.removeAll { ids.contains($0.localIdentifier) }
//    }
//
//    // Save trashed items to UserDefaults
//    private func saveTrashedItems() {
//        let identifiers = trashedItems.map { $0.localIdentifier }
//        UserDefaults.standard.set(identifiers, forKey: trashKey)
//    }
//
//    // Load trashed items from UserDefaults
//    private func loadTrashedItems() {
//        guard let savedIdentifiers = UserDefaults.standard.array(forKey: trashKey) as? [String] else { return }
//
//        let fetchOptions = PHFetchOptions()
//        fetchOptions.predicate = NSPredicate(format: "localIdentifier IN %@", savedIdentifiers)
//
//        let fetchedAssets = PHAsset.fetchAssets(with: fetchOptions)
//        var loadedItems: [PHAsset] = []
//        fetchedAssets.enumerateObjects { asset, _, _ in
//            loadedItems.append(asset)
//        }
//        trashedItems = loadedItems
//    }
//}
