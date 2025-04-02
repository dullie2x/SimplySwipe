import SwiftUI
import Photos

struct UserView: View {
    @State private var photoCount = UserDefaults.standard.integer(forKey: "photoCount")
    @State private var videoCount = UserDefaults.standard.integer(forKey: "videoCount")
    @State private var swipeCount = UserDefaults.standard.integer(forKey: "swipeCount")
    @State private var isFetching = false
    @State private var showPaywall = false

    @ObservedObject private var swipedMediaManager = SwipedMediaManager.shared

    private var isSubscribed: Bool {
        UserDefaults.standard.bool(forKey: "isSubscribed")
    }

    private var swipesLeft: String {
        isSubscribed ? "Unlimited" : "\(max(75 - swipeCount, 0))"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    Text("User Stats")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 15)

                    // Stats Section
                    VStack(spacing: 15) {
                        statCard(icon: "photo", title: "Photos", value: "\(photoCount)")
                        statCard(icon: "video", title: "Videos", value: "\(videoCount)")
                        statCard(icon: "hand.tap", title: "Total Swipes", value: "\(swipeCount)")
                        statCard(icon: "arrow.left.arrow.right", title: "Swipes Remaining", value: swipesLeft, highlight: !isSubscribed)

                        Button(action: {
                            // Rate app
                        }) {
                            statActionCard(icon: "star.fill", title: "Rate This App")
                        }
                    }
                    .padding(.vertical, 25)

                    // Upgrade Section
                    if !isSubscribed {
                        VStack(spacing: 15) {
                            Text("Want unlimited swipes?")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Button(action: { showPaywall.toggle() }) {
                                HStack {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.black)
                                    Text("Upgrade Now")
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundColor(.black)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(12)
                                .shadow(color: Color.green.opacity(0.5), radius: 5, x: 0, y: 2)
                            }
                            .padding(.horizontal, 30)
                        }
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 15)
                                .fill(Color.black.opacity(0.6))
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    } else {
                        Spacer().frame(height: 80)
                    }

                    if isFetching {
                        HStack {
                            ProgressView().scaleEffect(1.2)
                            Text("Refreshing stats...")
                                .foregroundColor(.gray)
                                .padding(.leading, 10)
                        }
                        .padding()
                    }

                    Spacer().frame(height: 20)
                }
                .frame(maxWidth: .infinity)
            }
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    refreshMediaStats()
                }
                swipeCount = swipedMediaManager.swipeCount
            }
            .fullScreenCover(isPresented: $showPaywall) {
                PaywallView()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.white)
                            .imageScale(.large)
                    }
                }
            }
        }
    }

    private func statActionCard(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.green)
                .frame(width: 40)

            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.15))
        )
        .padding(.horizontal, 16)
    }

    private func statCard(icon: String, title: String, value: String, highlight: Bool = false) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.green)
                .frame(width: 40)

            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(highlight ? .green : .gray)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.15))
        )
        .padding(.horizontal, 16)
    }

    func refreshMediaStats() {
        guard !isFetching else { return }
        isFetching = true

        DispatchQueue.global(qos: .userInitiated).async {
            PHPhotoLibrary.requestAuthorization { status in
                guard status == .authorized else {
                    DispatchQueue.main.async {
                        isFetching = false
                    }
                    return
                }

                let photoOptions = PHFetchOptions()
                photoOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
                let photos = PHAsset.fetchAssets(with: photoOptions)

                let videoOptions = PHFetchOptions()
                videoOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.video.rawValue)
                let videos = PHAsset.fetchAssets(with: videoOptions)

                DispatchQueue.main.async {
                    photoCount = photos.count
                    videoCount = videos.count
                    UserDefaults.standard.set(photoCount, forKey: "photoCount")
                    UserDefaults.standard.set(videoCount, forKey: "videoCount")
                    isFetching = false
                }
            }
        }
    }
}

#Preview {
    UserView()
}
