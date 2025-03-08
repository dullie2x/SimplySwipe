import SwiftUI
import Photos

struct UserView: View {
    @State private var photoCount = UserDefaults.standard.integer(forKey: "photoCount")
    @State private var videoCount = UserDefaults.standard.integer(forKey: "videoCount")
    @State private var swipeCount = UserDefaults.standard.integer(forKey: "swipeCount") // Tracks total swipes
    @State private var isFetching = false // Background fetching indicator
    @State private var showPaywall = false // Controls paywall visibility
    
    // ✅ Check if the user has unlimited swipes
    private var swipesLeft: String {
        let isSubscribed = UserDefaults.standard.bool(forKey: "isSubscribed")
        let remainingSwipes = max(75 - swipeCount, 0) // 75 swipes per day

        return isSubscribed ? "Unlimited" : "\(remainingSwipes)"
    }

    var body: some View {
        VStack {
            // Header
            Text("User Stats")
                .font(.largeTitle.weight(.bold))
                .foregroundColor(.white)
                .padding(.top, 20)

            Spacer().frame(height: 20)

            // Stats Section
            VStack(alignment: .leading, spacing: 25) {
                statRow(title: "Photos", value: "\(photoCount)")
                statRow(title: "Videos", value: "\(videoCount)")
                statRow(title: "Total Swipes", value: "\(swipeCount)")
                statRow(title: "Swipes Left", value: swipesLeft)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.2))
            )
            .padding(.horizontal, 16)

            Spacer()

            if isFetching {
                ProgressView("Refreshing stats...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .padding(.bottom, 20)
            }

            // Upgrade Button (Only if not subscribed)
            if !UserDefaults.standard.bool(forKey: "isSubscribed") {
                Button(action: { showPaywall.toggle() }) {
                    Text("Upgrade to Unlimited Swipes")
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.yellow)
                        .cornerRadius(10)
                        .shadow(radius: 5)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            // Feedback Section
            VStack(spacing: 10) {
                Text("Enjoying the app? Or not?")
                    .foregroundColor(.white)
                    .font(.subheadline)

                Text("We would love to hear some feedback!")
                    .foregroundColor(.gray)
                    .font(.footnote)

                Button(action: {
                    print("Feedback button tapped")
                    // Navigate to feedback page or show feedback form here
                }) {
                    Text("Feedback")
                        .font(.footnote)
                        .foregroundColor(.black)
                        .padding()
                        .frame(maxWidth: 100, maxHeight: 40)
                        .background(Color.green)
                        .cornerRadius(6)
                }
            }
            .padding(.bottom, 20)
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        .onAppear {
            refreshMediaStats()
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    /// **Helper Function for Stats Row**
    private func statRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .font(.title3)
                .foregroundColor(.gray)
        }
    }

    /// **Fetch & Update User Stats**
    func refreshMediaStats() {
        isFetching = true
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                let fetchOptions = PHFetchOptions()
                let allAssets = PHAsset.fetchAssets(with: fetchOptions)

                var newPhotoCount = 0
                var newVideoCount = 0

                allAssets.enumerateObjects { asset, _, _ in
                    if asset.mediaType == .image {
                        newPhotoCount += 1
                    } else if asset.mediaType == .video {
                        newVideoCount += 1
                    }
                }

                // ✅ Update the counts and cache them
                DispatchQueue.main.async {
                    photoCount = newPhotoCount
                    videoCount = newVideoCount
                    UserDefaults.standard.set(newPhotoCount, forKey: "photoCount")
                    UserDefaults.standard.set(newVideoCount, forKey: "videoCount")
                    isFetching = false
                }
            } else {
                print("Access to photos denied")
                isFetching = false
            }
        }
    }
}

#Preview {
    UserView()
}
