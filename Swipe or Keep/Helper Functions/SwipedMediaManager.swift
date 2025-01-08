//
//  SwipedMediaManager.swift
//  Swipe or Keep
//
//  Created by Gbolade Ariyo on 1/7/25.
//

import SwiftUI
import Photos

class SwipedMediaManager {
    static let shared = SwipedMediaManager()
    private let swipedKey = "swipedMedia"

    private init() {}

    func addSwipedMedia(_ media: PHAsset) {
        var swipedMedia = getSwipedMedia()
        swipedMedia.insert(media.localIdentifier)
        UserDefaults.standard.set(Array(swipedMedia), forKey: swipedKey)
    }

    func getSwipedMedia() -> Set<String> {
        let saved = UserDefaults.standard.array(forKey: swipedKey) as? [String] ?? []
        return Set(saved)
    }
}
