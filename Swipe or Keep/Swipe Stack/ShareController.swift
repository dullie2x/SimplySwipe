import SwiftUI
import Photos
import AVKit

class ShareController {
    static func shareMedia(asset: PHAsset, from view: UIView, completion: @escaping () -> Void) {
        if asset.mediaType == .image {
            shareImage(asset: asset, from: view, completion: completion)
        } else if asset.mediaType == .video {
            shareVideo(asset: asset, from: view, completion: completion)
        } else {
            print("Unsupported media type")
            completion()
        }
    }
    
    private static func shareImage(asset: PHAsset, from view: UIView, completion: @escaping () -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .default,
            options: options
        ) { image, info in
            guard let image = image else {
                print("Could not load image")
                completion()
                return
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d, yyyy"
            let dateString = asset.creationDate != nil ? dateFormatter.string(from: asset.creationDate!) : ""
            
            guard let watermarkedImage = addWatermark(to: image, date: dateString) else {
                shareOriginalImage(image: image, from: view, completion: completion)
                return
            }
            
            let shareText = "✨Shared from Simply Swipe✨ https://apps.apple.com/us/app/profit-flip/id6451086664"
            let items: [Any] = [watermarkedImage, shareText]
            
            presentShareSheet(items: items, from: view, completion: completion)
        }
    }
    
    private static func shareOriginalImage(image: UIImage, from view: UIView, completion: @escaping () -> Void) {
        let shareText = "✨Shared from Simply Swipe✨ https://apps.apple.com/us/app/profit-flip/id6451086664"
        let items: [Any] = [image, shareText]
        
        presentShareSheet(items: items, from: view, completion: completion)
    }
    
    private static func addWatermark(to image: UIImage, date: String) -> UIImage? {
        let imageSize = image.size
        let scale = image.scale
        
        UIGraphicsBeginImageContextWithOptions(imageSize, false, scale)
        defer { UIGraphicsEndImageContext() }
        
        image.draw(in: CGRect(origin: .zero, size: imageSize))
        
        let gradientRect = CGRect(x: 0, y: imageSize.height - 100, width: imageSize.width, height: 100)
        let gradient = createBottomGradient(in: gradientRect)
        gradient?.fill()
        
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        
        let appAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.8)
        ]
        
        let dateString = date
        let dateStringSize = dateString.size(withAttributes: dateAttributes)
        let dateRect = CGRect(
            x: 20,
            y: imageSize.height - dateStringSize.height - 20,
            width: dateStringSize.width,
            height: dateStringSize.height
        )
        
        let appString = "Simply Swipe"
        let appStringSize = appString.size(withAttributes: appAttributes)
        let appRect = CGRect(
            x: imageSize.width - appStringSize.width - 20,
            y: imageSize.height - appStringSize.height - 20,
            width: appStringSize.width,
            height: appStringSize.height
        )
        
        dateString.draw(in: dateRect, withAttributes: dateAttributes)
        appString.draw(in: appRect, withAttributes: appAttributes)
        
        return UIGraphicsGetImageFromCurrentImageContext()
    }
    
    private static func createBottomGradient(in rect: CGRect) -> UIBezierPath? {
        let gradientPath = UIBezierPath(rect: rect)
        
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = rect
        gradientLayer.colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0.6).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        
        UIGraphicsBeginImageContext(rect.size)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        
        gradientLayer.render(in: context)
        
        guard let gradientImage = UIGraphicsGetImageFromCurrentImageContext() else {
            return nil
        }
        
        UIGraphicsGetCurrentContext()?.saveGState()
        gradientImage.draw(in: rect)
        UIGraphicsGetCurrentContext()?.restoreGState()
        
        return gradientPath
    }
    
    private static func shareVideo(asset: PHAsset, from view: UIView, completion: @escaping () -> Void) {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current

        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
            DispatchQueue.main.async {
                guard let urlAsset = avAsset as? AVURLAsset else {
                    print("Could not get video URL")
                    completion()
                    return
                }

                let shareText = "✨Shared from Simply Swipe✨ https://apps.apple.com/us/app/profit-flip/id6451086664"
                let items: [Any] = [urlAsset.url, shareText]
                
                presentShareSheet(items: items, from: view, completion: completion)
            }
        }
    }
    
    private static func presentShareSheet(items: [Any], from view: UIView, completion: @escaping () -> Void) {
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            completion()
        }
        
        // Get the root view controller more reliably
        if let rootVC = findTopMostViewController() {
            // Check if a view controller is currently being presented
            if rootVC.presentedViewController != nil {
                // Dismiss any presented view controllers first
                rootVC.dismiss(animated: true) {
                    // Then present our share sheet
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let popover = activityVC.popoverPresentationController {
                            popover.sourceView = view
                            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
                        }
                        rootVC.present(activityVC, animated: true, completion: nil)
                    }
                }
            } else {
                // No view is being presented, directly show share sheet
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = view
                    popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
                }
                rootVC.present(activityVC, animated: true, completion: nil)
            }
        } else {
            completion()
        }
    }
    
    private static func findTopMostViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        let window = windowScene?.windows.first(where: { $0.isKeyWindow })
        
        var topController = window?.rootViewController
        while let presentedController = topController?.presentedViewController {
            topController = presentedController
        }
        
        return topController
    }
}

struct ShareButton: UIViewRepresentable {
    var asset: PHAsset
    
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        let boldConfig = UIImage.SymbolConfiguration(weight: .bold)
        let boldImage = UIImage(systemName: "square.and.arrow.up")?
            .withConfiguration(boldConfig)
        button.setImage(boldImage, for: .normal)
        button.tintColor = .yellow
        button.addTarget(context.coordinator, action: #selector(Coordinator.share), for: .touchUpInside)
        return button
    }
    
    func updateUIView(_ uiView: UIButton, context: Context) {
        context.coordinator.asset = asset
        context.coordinator.button = uiView
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(asset: asset)
    }
    
    class Coordinator: NSObject {
        var asset: PHAsset
        var button: UIButton?
        
        init(asset: PHAsset) {
            self.asset = asset
        }
        
        @objc func share() {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            if let button = button {
                button.isEnabled = false
                
                ShareController.shareMedia(asset: asset, from: button) {
                    DispatchQueue.main.async {
                        button.isEnabled = true
                    }
                }
            }
        }
    }
}
