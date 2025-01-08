import SwiftUI
import Photos


class TrashManager: ObservableObject {
    static let shared = TrashManager() // Singleton instance

    @Published var trashedItems: [PHAsset] = []

    private init() {}

    func addToTrash(_ asset: PHAsset) {
        trashedItems.append(asset)
    }

    func removeFromTrash(_ asset: PHAsset) {
        trashedItems.removeAll { $0.localIdentifier == asset.localIdentifier }
    }
}
