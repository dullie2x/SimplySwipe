import SwiftUI
import Photos
import AVKit

struct SwipeStack: View {
    @State private var offset = CGSize.zero
    @State private var currentIndex = 0
    @State private var mediaItems: [PHAsset] = []
    @State private var paginatedMediaItems: [PHAsset] = []
    @State private var mediaSize: String = "0 MB"
    @State private var isLoading = true
    @State private var preloadedPlayers: [Int: AVQueuePlayer] = [:]

    private let pageSize = 30 // Limit to 30 media items

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading Media...")
                    .scaleEffect(1.5)
            } else {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        HStack {
                            Text("Size: \(mediaSize)")
                                .font(Font.title2.weight(.heavy))
                                .foregroundColor(.green)
                                .padding(8)
                                .onChange(of: currentIndex) {
                                    updateMediaSize() // Ensure real-time update
                                }
                            Spacer()
                            Text("\(currentIndex + 1)/\(mediaItems.count)")
                                .font(Font.title2.weight(.heavy))
                                .foregroundColor(.green)
                                .padding(8)
                        }
                        .padding(.horizontal, 20)
                        .zIndex(1)

                        ZStack {
                            ForEach(currentIndex..<min(currentIndex + 2, paginatedMediaItems.count), id: \ .self) { index in
                                if index < paginatedMediaItems.count {
                                    MediaCardView(
                                        asset: paginatedMediaItems[index],
                                        size: CGSize(width: geometry.size.width - CGFloat((index - currentIndex) * 10), height: geometry.size.height - CGFloat((index - currentIndex) * 10) - 60),
                                        offset: index == currentIndex ? $offset : .constant(.zero),
                                        onSwiped: handleSwipe,
                                        player: preloadedPlayers[index]
                                    )
                                    .zIndex(Double(-index))
                                    .offset(x: CGFloat((index - currentIndex) * 10), y: CGFloat((index - currentIndex) * 10))
                                    .scaleEffect(index == currentIndex ? 1.0 : 0.9, anchor: .center)
                                    .animation(.interpolatingSpring(stiffness: 300, damping: 50), value: currentIndex) // Smoother animation

                                }
                            }
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height - 60)
                        .zIndex(0)
                    }
                }
            }
        }
        .onAppear(perform: fetchMedia)
    }

    // Fetch Media Items
    func fetchMedia() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.includeAssetSourceTypes = [.typeUserLibrary, .typeCloudShared, .typeiTunesSynced]
            fetchOptions.fetchLimit = 30

            let result = PHAsset.fetchAssets(with: fetchOptions)
            var tempMediaItems: [PHAsset] = []
            result.enumerateObjects { asset, _, _ in
                tempMediaItems.append(asset)
            }

            DispatchQueue.main.async {
                self.mediaItems = tempMediaItems
                self.paginatedMediaItems = tempMediaItems
                self.updateMediaSize()
                self.preloadVideos()
                self.isLoading = false
            }
        }
    }

    // Preload Videos
    func preloadVideos() {
        DispatchQueue.global(qos: .background).async {
            for (index, asset) in self.paginatedMediaItems.enumerated() where asset.mediaType == .video {
                let manager = PHImageManager.default()
                let options = PHVideoRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = true

                manager.requestPlayerItem(forVideo: asset, options: options) { playerItem, _ in
                    if let playerItem = playerItem {
                        DispatchQueue.main.async {
                            let player = AVQueuePlayer(playerItem: playerItem)
                            _ = AVPlayerLooper(player: player, templateItem: playerItem)
                            self.preloadedPlayers[index] = player
                        }
                    }
                }
            }
        }
    }

    func handleSwipe(direction: SwipeDirection) {
        if direction == .left || direction == .right {
            withAnimation(.easeInOut(duration: 0.15)) { // Faster disappearance of the top card
                offset.width = direction == .left ? -1000 : 1000
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { // Match the animation duration
                currentIndex += 1 // Update the index immediately after the swipe
                offset = .zero
            }
        }
    }


    func updateMediaSize() {
        guard currentIndex < paginatedMediaItems.count else { return }
        let asset = paginatedMediaItems[currentIndex]
        let resources = PHAssetResource.assetResources(for: asset)
        if let resource = resources.first {
            mediaSize = ByteCountFormatter.string(fromByteCount: Int64(resource.value(forKey: "fileSize") as? Int ?? 0), countStyle: .file)
        }
    }
}

// Updated MediaCardView
struct MediaCardView: View {
    let asset: PHAsset
    let size: CGSize
    @Binding var offset: CGSize
    let onSwiped: (SwipeDirection) -> Void
    let player: AVQueuePlayer?

    var body: some View {
        ZStack {
            if asset.mediaType == .image {
                Image(uiImage: getUIImage(from: asset))
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .background(Color.black)
                    .clipped()
            } else if asset.mediaType == .video, let player = player {
                VideoPlayer(player: player)
                    .frame(width: size.width, height: size.height)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            }

            if offset.width > 0 {
                LabelView(text: "Keep", color: .green)
                    .opacity(Double(offset.width / 150).clamped(to: 0...1))
            } else if offset.width < 0 {
                LabelView(text: "Delete", color: .red)
                    .opacity(Double(-offset.width / 150).clamped(to: 0...1))
            }
        }
        .offset(offset)
        .gesture(
            DragGesture()
                .onChanged { gesture in offset = gesture.translation }
                .onEnded { _ in
                    if offset.width > 150 {
                        onSwiped(.right)
                    } else if offset.width < -150 {
                        onSwiped(.left)
                    } else {
                        withAnimation(.spring()) { offset = .zero }
                    }
                }
        )
    }

    private func getUIImage(from asset: PHAsset) -> UIImage {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = true

        var image = UIImage()
        manager.requestImage(for: asset, targetSize: CGSize(width: 1080, height: 1920), contentMode: .aspectFit, options: options) { result, _ in
            if let result = result {
                image = result
            }
        }
        return image
    }
}

struct LabelView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.largeTitle)
            .bold()
            .foregroundColor(.white)
            .padding()
            .background(color.opacity(0.7))
            .cornerRadius(10)
    }
}

enum SwipeDirection {
    case left, right
}

struct SwipeStack_Previews: PreviewProvider {
    static var previews: some View {
        SwipeStack()
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
