//
//  ShareController.swift
//  Media App
//
//  Created on [Date]
//
//  Optimized for instant sheet presentation, lazy loading,
//  background processing, and caching. iOS 15+ compatible.
//  (Watermark removed from shared images.)
//

import SwiftUI
import Photos
import AVFoundation
import UniformTypeIdentifiers
import UIKit

// MARK: - Public API

final class ShareController {

    /// Present the share sheet immediately. Heavy work (fetching/exporting) happens lazily.
    static func shareMedia(asset: PHAsset, from view: UIView, completion: @escaping () -> Void) {
        let source = ShareItemSource(asset: asset)

        let activityVC = UIActivityViewController(activityItems: [source], applicationActivities: nil)
        activityVC.completionWithItemsHandler = { _, _, _, _ in completion() }

        if let top = topViewController() {
            if let pop = activityVC.popoverPresentationController, UIDevice.current.userInterfaceIdiom == .pad {
                pop.sourceView = view
                pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
                pop.permittedArrowDirections = [.up, .down]
            }
            top.present(activityVC, animated: true, completion: nil)
        } else {
            completion()
        }
    }

    // MARK: - Top VC helper

    private static func topViewController(root: UIViewController? = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first(where: { $0.isKeyWindow })?
        .rootViewController) -> UIViewController? {

        if let nav = root as? UINavigationController { return topViewController(root: nav.visibleViewController) }
        if let tab = root as? UITabBarController { return topViewController(root: tab.selectedViewController) }
        if let presented = root?.presentedViewController { return topViewController(root: presented) }
        return root
    }
}

// MARK: - UIActivityItemSource (Lazy, background-friendly)

private final class ShareItemSource: NSObject, UIActivityItemSource {

    private let asset: PHAsset

    // Promo text shows up in some destinations (e.g., Messages)
    private let promoText = "✨Shared from Simply Swipe✨ https://apps.apple.com/us/app/simply-swipe-photo-cleaner/id6743370618"

    // In-memory cache for images; temp-file cache for videos
    private static let imageCache = NSCache<NSString, NSData>()
    private static var videoURLCache = [String: URL]()   // assetID → temp file

    init(asset: PHAsset) {
        self.asset = asset
        super.init()
    }

    // Placeholder is lightweight and shown immediately
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        // a tiny string is enough; real content is delivered lazily via NSItemProvider
        return promoText
    }

    // Return an NSItemProvider so the system fetches the data lazily off the main thread.
    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        switch asset.mediaType {
        case .image:
            return makeImageProvider()   // NSItemProvider
        case .video:
            return makeVideoProvider()   // NSItemProvider
        default:
            return promoText             // String
        }
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        "Shared from Simply Swipe"
    }

    // MARK: - NSItemProvider builders

    private func makeImageProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        let type = UTType.jpeg.identifier

        provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .all) { completion in
            // Background work: fetch image data (optionally downscale), then return Data
            self.provideJPEG { data in
                if let data = data {
                    completion(data, nil)
                } else {
                    completion(nil, NSError(domain: "ShareController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare image"]))
                }
            }
            return nil
        }

        provider.suggestedName = self.filenameBase() + ".jpg"
        return provider
    }

    private func makeVideoProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        let type = UTType.movie.identifier

        provider.registerFileRepresentation(forTypeIdentifier: type, fileOptions: [], visibility: .all) { completion in
            // Background work: ensure local movie URL (export if needed), then pass a temp URL
            self.provideMovieURL { url in
                if let url = url {
                    completion(url, true, nil)
                } else {
                    completion(nil, false, NSError(domain: "ShareController", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare video"]))
                }
            }
            return nil
        }

        provider.suggestedName = self.filenameBase() + ".mov"
        return provider
    }

    // MARK: - Image Pipeline (Background, no watermark)

    /// Fetch original image data, optionally downscale for performance, return JPEG data.
    private func provideJPEG(maxLongSide: CGFloat = 3072, completion: @escaping (Data?) -> Void) {
        let key = asset.localIdentifier as NSString
        if let cached = Self.imageCache.object(forKey: key) {
            completion(Data(referencing: cached))
            return
        }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current

        // Grab the original data; we'll downscale off-main if needed
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            guard let data = data, let baseImage = UIImage(data: data) else {
                completion(nil); return
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let result = autoreleasepool(invoking: { () -> Data? in
                    // Downscale if the image is extremely large to speed up sharing
                    let finalImage = self.downscaledIfNeeded(image: baseImage, maxLongSide: maxLongSide)
                    return finalImage.jpegData(compressionQuality: 0.95)
                })

                if let result = result {
                    Self.imageCache.setObject(result as NSData, forKey: key)
                    completion(result)
                } else {
                    completion(nil)
                }
            }
        }
    }

    private func downscaledIfNeeded(image: UIImage, maxLongSide: CGFloat) -> UIImage {
        let size = image.size
        let longSide = max(size.width, size.height)
        guard longSide > maxLongSide, longSide > 0 else { return image }

        let scaleRatio = maxLongSide / longSide
        let targetSize = CGSize(width: size.width * scaleRatio, height: size.height * scaleRatio)

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: {
            let f = UIGraphicsImageRendererFormat()
            f.scale = image.scale // maintain scale
            f.opaque = false
            return f
        }())

        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    // MARK: - Video Pipeline (Background)

    /// Ensure a local movie URL for the asset (export if needed), cache in /tmp, return URL.
    private func provideMovieURL(completion: @escaping (URL?) -> Void) {
        // Return cached temp URL if present
        if let cached = Self.videoURLCache[asset.localIdentifier], FileManager.default.fileExists(atPath: cached.path) {
            completion(cached); return
        }

        let vopts = PHVideoRequestOptions()
        vopts.isNetworkAccessAllowed = true
        vopts.deliveryMode = .highQualityFormat
        vopts.version = .current

        PHImageManager.default().requestAVAsset(forVideo: asset, options: vopts) { avAsset, _, _ in
            guard let avAsset = avAsset else {
                completion(nil); return
            }

            // If it's already a local AVURLAsset and file exists, use it directly
            if let urlAsset = avAsset as? AVURLAsset, urlAsset.url.isFileURL {
                completion(urlAsset.url)
                return
            }

            // Export to a temp .mov using passthrough (fast, no re-encode)
            let preset = AVAssetExportPresetPassthrough
            guard let export = AVAssetExportSession(asset: avAsset, presetName: preset) else {
                completion(nil); return
            }

            let outURL = self.makeTempMovieURL()
            export.outputURL = outURL
            export.outputFileType = .mov
            export.shouldOptimizeForNetworkUse = true

            export.exportAsynchronously {
                switch export.status {
                case .completed:
                    Self.videoURLCache[self.asset.localIdentifier] = outURL
                    completion(outURL)
                default:
                    completion(nil)
                }
            }
        }
    }

    private func makeTempMovieURL() -> URL {
        let name = filenameBase() + "_\(Int(Date().timeIntervalSince1970)).mov"
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
    }

    // MARK: - Helpers

    private func filenameBase() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        let datePart = asset.creationDate.map { df.string(from: $0) } ?? "shared"
        return "simply_swipe_\(datePart)"
    }
}

// MARK: - SwiftUI bridge button (unchanged public API, snappier UX)

struct ShareButton: UIViewRepresentable {
    var asset: PHAsset

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        let boldConfig = UIImage.SymbolConfiguration(weight: .bold)
        let boldImage = UIImage(systemName: "square.and.arrow.up")?.withConfiguration(boldConfig)
        button.setImage(boldImage, for: .normal)
        button.tintColor = .yellow
        button.addTarget(context.coordinator, action: #selector(Coordinator.share), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        context.coordinator.asset = asset
        context.coordinator.button = uiView
    }

    func makeCoordinator() -> Coordinator { Coordinator(asset: asset) }

    final class Coordinator: NSObject {
        var asset: PHAsset
        weak var button: UIButton?

        init(asset: PHAsset) { self.asset = asset }

        @objc func share() {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            guard let button = button else { return }
            button.isEnabled = false

            // Present instantly; heavy work is lazy via NSItemProvider
            ShareController.shareMedia(asset: asset, from: button) { [weak self] in
                DispatchQueue.main.async {
                    self?.button?.isEnabled = true
                }
            }
        }
    }
}
