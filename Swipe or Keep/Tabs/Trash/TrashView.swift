import SwiftUI
import Photos
import StoreKit

struct TrashView: View {
    @ObservedObject var swipedMediaManager = SwipedMediaManager.shared
    @State private var selectedItems: Set<String> = []
    @State private var isSelectionMode: Bool = false
    @State private var selectedAssetForFullScreen: PHAsset?
    @State private var isDeleting = false
    @State private var isRecovering = false
    @State private var showConfirmationDialog = false
    @State private var showFeedback = false
    @State private var feedbackMessage = ""
    @State private var feedbackIsSuccess = true
    @State private var showRatingPrompt = false

    private let gradientStart = Color(red: 0.2, green: 0.6, blue: 0.3)
    private let gradientEnd = Color(red: 0.2, green: 0.4, blue: 0.8)
    private let deleteColor = Color(red: 0.8, green: 0.2, blue: 0.2)
    private let accentColor = Color(red: 0.8, green: 0.6, blue: 0.2)

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [Color.black, Color.black.opacity(0.9)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                

                if swipedMediaManager.trashedMediaAssets.isEmpty {
                    emptyStateView
                } else {
                    contentView
                }

                if showFeedback {
                    feedbackToast
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(100)
                }
            }
            .navigationTitle("Trash")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if !swipedMediaManager.trashedMediaAssets.isEmpty {
                        Button(action: toggleSelectionMode) {
                            Text(isSelectionMode ? "Cancel" : "Select")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        .disabled(isDeleting || isRecovering)
                    }
                }
            }
            .foregroundColor(.white)
            .sheet(item: $selectedAssetForFullScreen) { asset in
                FullScreenMediaView(
                    initialAsset: asset,
                    allAssets: swipedMediaManager.trashedMediaAssets,
                    onClose: { selectedAssetForFullScreen = nil }
                )
            }
            .actionSheet(isPresented: $showConfirmationDialog) {
                ActionSheet(
                    title: Text("Are you sure you want to delete these items?"),
                    message: Text("These items will be added to your 'Recently Deleted Album'"),
                    buttons: [
                        .destructive(Text("Delete"), action: {
                            performDelete()
                        }),
                        .cancel()
                    ]
                )
            }
            .alert("Enjoying Simply Swipe?", isPresented: $showRatingPrompt) {
                Button("Yes") {
                    if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                        SKStoreReviewController.requestReview(in: scene)
                        AppRatingManager.shared.didPromptForRating()
                        AppRatingManager.shared.markAsRated()
                    }
                }
                Button("Not really") {
                    if let url = URL(string: "https://forms.gle/f7EyjVj4S5x2yGi27") {
                        UIApplication.shared.open(url)
                        AppRatingManager.shared.didPromptForRating()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Would you mind leaving us a quick review?")
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .preferredColorScheme(.dark)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "trash.slash.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [gradientStart, gradientEnd]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .scaleEffect(1.0)
                .animation(
                    Animation.easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true),
                    value: UUID()
                )

            Text("No items in Trash")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text("Items you delete will appear here")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            if isSelectionMode {
                selectionToolbar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView {
                LazyVGrid(columns: adaptiveColumns, spacing: 8) {
                    ForEach(swipedMediaManager.trashedMediaAssets, id: \.localIdentifier) { asset in
                        MediaThumbnailView(
                            asset: asset,
                            isSelected: selectedItems.contains(asset.localIdentifier),
                            isSelectionMode: isSelectionMode,
                            onTap: {
                                handleTapOnAsset(asset)
                            },
                            size: gridItemSize
                        )
                    }
                }
            }
            .refreshable {
                await refreshTrashContents()
            }
        }
    }

    private var gridItemSize: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let spacing: CGFloat = 8
        let minItemWidth: CGFloat = 110
        let numColumns = max(1, Int(screenWidth / (minItemWidth + spacing)))
        let totalSpacing = CGFloat(numColumns - 1) * spacing
        return (screenWidth - totalSpacing - 32) / CGFloat(numColumns)
    }

    private var selectionToolbar: some View {
        HStack(spacing: 20) {
            Button(action: toggleSelectAll) {
                HStack(spacing: 6) {
                    Image(systemName: selectedItems.count == swipedMediaManager.trashedMediaAssets.count ? "checkmark.circle.fill" : "circle")
                    Text(selectedItems.count == swipedMediaManager.trashedMediaAssets.count ? "Deselect All" : "Select All")
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
            }

            Spacer()

            HStack(spacing: 20) {
                Button(action: recoverSelected) {
                    HStack(spacing: 6) {
                        if isRecovering {
                            ProgressView()
                                .frame(width: 16, height: 16)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        Text("Recover")
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [gradientStart, gradientEnd]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
                .disabled(selectedItems.isEmpty || isDeleting || isRecovering)

                Button(action: confirmDelete) {
                    HStack(spacing: 6) {
                        if isDeleting {
                            ProgressView()
                                .frame(width: 16, height: 16)
                                .tint(.white)
                        } else {
                            Image(systemName: "trash.fill")
                        }
                        Text("Delete")
                            .fontWeight(.medium)
                    }
                    .foregroundColor(deleteColor)
                }
                .disabled(selectedItems.isEmpty || isDeleting || isRecovering)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.8))
    }

    private var feedbackToast: some View {
        HStack {
            Image(systemName: feedbackIsSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(feedbackIsSuccess ? gradientStart : deleteColor)

            Text(feedbackMessage)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.8))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .foregroundColor(.white)
    }

    private var adaptiveColumns: [GridItem] {
        let minItemWidth: CGFloat = 110
        return [GridItem(.adaptive(minimum: minItemWidth), spacing: 8)]
    }

    private func handleTapOnAsset(_ asset: PHAsset) {
        if isSelectionMode {
            toggleSelection(for: asset.localIdentifier)
        } else {
            openFullScreen(for: asset)
        }
    }

    private func toggleSelectionMode() {
        withAnimation(.spring(response: 0.3)) {
            isSelectionMode.toggle()
            selectedItems.removeAll()
        }
    }

    private func toggleSelection(for id: String) {
        withAnimation(.spring(response: 0.2)) {
            if selectedItems.contains(id) {
                selectedItems.remove(id)
            } else {
                selectedItems.insert(id)
            }
        }
        hapticFeedback(style: .light)
    }

    private func toggleSelectAll() {
        withAnimation(.spring(response: 0.3)) {
            if selectedItems.count == swipedMediaManager.trashedMediaAssets.count {
                selectedItems.removeAll()
            } else {
                selectedItems = Set(swipedMediaManager.trashedMediaAssets.map { $0.localIdentifier })
            }
        }
        hapticFeedback(style: .medium)
    }

    private func confirmDelete() {
        showConfirmationDialog = true
    }

    private func performDelete() {
        guard !selectedItems.isEmpty else { return }

        isDeleting = true

        let assetsToDelete = swipedMediaManager.trashedMediaAssets.filter { selectedItems.contains($0.localIdentifier) }

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
        }) { success, error in
            DispatchQueue.main.async {
                withAnimation {
                    if success {
                        let deletedIdentifiers = Set(assetsToDelete.map { $0.localIdentifier })
                        swipedMediaManager.deleteItems(with: deletedIdentifiers)
                        selectedItems.removeAll()
                        isSelectionMode = false

                        showFeedback(message: "Items Added to Recently Deleted Folder!", isSuccess: true)

                        promptForAppRatingIfNeeded()
                    } else if let error = error {
                        print("Failed to delete assets: \(error)")
                        showFeedback(message: "Failed to delete items", isSuccess: false)
                    }
                    isDeleting = false
                }
            }
        }
    }

    private func recoverSelected() {
        guard !selectedItems.isEmpty else { return }

        isRecovering = true
        let itemsToRecover = selectedItems

        Task {
            await MainActor.run {
                swipedMediaManager.recoverItems(with: itemsToRecover)
            }

            await MainActor.run {
                withAnimation {
                    let count = itemsToRecover.count
                    selectedItems.removeAll()
                    isRecovering = false
                    isSelectionMode = false

                    showFeedback(message: "\(count) \(count == 1 ? "item" : "items") recovered", isSuccess: true)
                    promptForAppRatingIfNeeded()
                }
            }
        }
    }

    private func promptForAppRatingIfNeeded() {
        AppRatingManager.shared.registerUserAction()

        if AppRatingManager.shared.shouldPromptForRating() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showRatingPrompt = true
                // The following line ensures the AppRatingManager knows we showed the prompt
                AppRatingManager.shared.didPromptForRating()
            }
        }
    }

    private func openFullScreen(for asset: PHAsset) {
        selectedAssetForFullScreen = asset
    }

    private func showFeedback(message: String, isSuccess: Bool) {
        feedbackMessage = message
        feedbackIsSuccess = isSuccess

        withAnimation(.spring(response: 0.3)) {
            showFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.spring(response: 0.3)) {
                showFeedback = false
            }
        }
    }

    private func hapticFeedback(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func refreshTrashContents() async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }
}

extension PHAsset: @retroactive Identifiable {
    public var id: String {
        self.localIdentifier
    }
}
