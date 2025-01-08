//
//  TrashView.swift
//  Swipe or Keep
//
//  Created by Gbolade Ariyo on 12/22/24.
//

import SwiftUI
import Photos

struct TrashView: View {
    @ObservedObject var trashManager = TrashManager.shared

    var body: some View {
        NavigationView {
            List {
                ForEach(trashManager.trashedItems, id: \.localIdentifier) { asset in
                    MediaThumbnailView(asset: asset)
                }
            }
            .navigationTitle("Trash")
        }
    }
}

struct MediaThumbnailView: View {
    let asset: PHAsset

    var body: some View {
        HStack {
            if let thumbnail = getThumbnail(from: asset) {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
            }
            Text(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown Date")
        }
    }

    private func getThumbnail(from asset: PHAsset) -> UIImage? {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isSynchronous = true

        var thumbnail: UIImage?
        manager.requestImage(for: asset, targetSize: CGSize(width: 60, height: 60), contentMode: .aspectFit, options: options) { result, _ in
            thumbnail = result
        }
        return thumbnail
    }
}

