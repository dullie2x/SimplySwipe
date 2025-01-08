//import SwiftUI
//import Photos
//import AVKit
//
//struct CardView: View {
//    struct Model: Identifiable {
//        let id = UUID()
//        let asset: PHAsset
//    }
//
//    var model: Model
//    var size: CGSize
//    var dragOffset: CGSize
//    var isTopCard: Bool
//    var isSecondCard: Bool
//
//    var body: some View {
//        ZStack {
//            if model.asset.mediaType == .image {
//                AsyncImageLoader(asset: model.asset)
//                    .frame(width: size.width * 0.8, height: size.height * 0.8)
//                    .cornerRadius(15)
//                    .clipped()
//            } else if model.asset.mediaType == .video {
//                VideoPlayerView(asset: model.asset)
//                    .frame(width: size.width * 0.8, height: size.height * 0.8)
//                    .cornerRadius(15)
//            }
//
//            if isTopCard {
//                shadowView
//            }
//        }
//    }
//
//    private var shadowView: some View {
//        Rectangle()
//            .fill(Color.clear)
//            .shadow(color: shadowColor, radius: 10, x: 0, y: 3)
//    }
//
//    private var shadowColor: Color {
//        if dragOffset.width > 0 {
//            return Color.green.opacity(0.5)
//        } else if dragOffset.width < 0 {
//            return Color.red.opacity(0.5)
//        } else {
//            return Color.gray.opacity(0.2)
//        }
//    }
//}
//
//struct AsyncImageLoader: View {
//    let asset: PHAsset
//    @State private var image: UIImage? = nil
//
//    var body: some View {
//        Group {
//            if let image = image {
//                Image(uiImage: image)
//                    .resizable()
//                    .scaledToFill()
//            } else {
//                ProgressView()
//                    .onAppear {
//                        loadImage()
//                    }
//            }
//        }
//    }
//
//    private func loadImage() {
//        let manager = PHImageManager.default()
//        let options = PHImageRequestOptions()
//        options.deliveryMode = .highQualityFormat
//        options.isSynchronous = false
//
//        manager.requestImage(for: asset, targetSize: CGSize(width: 1080, height: 1920), contentMode: .aspectFill, options: options) { result, _ in
//            if let result = result {
//                DispatchQueue.main.async {
//                    self.image = result
//                }
//            }
//        }
//    }
//}
//
//struct VideoPlayerView: View {
//    let asset: PHAsset
//
//    var body: some View {
//        if let player = getPlayer(for: asset) {
//            VideoPlayer(player: player)
//                .onAppear {
//                    player.play()
//                }
//                .onDisappear {
//                    player.pause()
//                }
//        } else {
//            Text("Unable to load video")
//                .foregroundColor(.gray)
//        }
//    }
//
//    private func getPlayer(for asset: PHAsset) -> AVPlayer? {
//        let manager = PHImageManager.default()
//        let options = PHVideoRequestOptions()
//        options.deliveryMode = .highQualityFormat
//        options.isNetworkAccessAllowed = true
//
//        let playerPromise = DispatchSemaphore(value: 0)
//        var player: AVPlayer? = nil
//
//        manager.requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
//            if let playerItem = playerItem {
//                player = AVPlayer(playerItem: playerItem)
//            }
//            playerPromise.signal()
//        }
//
//        _ = playerPromise.wait(timeout: .now() + 5)
//        return player
//    }
//}
//
//struct CardView_Previews: PreviewProvider {
//    static var previews: some View {
//        GeometryReader { geometry in
//            CardView(
//                model: CardView.Model(asset: PHAsset()),
//                size: geometry.size,
//                dragOffset: .zero,
//                isTopCard: true,
//                isSecondCard: false
//            )
//        }
//    }
//}
