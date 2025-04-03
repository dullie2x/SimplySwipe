import SwiftUI
import Photos
import AVKit

struct CircularProgressView: View {
    var progress: Double
    var gradient: [Color]
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(lineWidth: 5)
                .opacity(0.3)
                .foregroundColor(Color.white)
            
            // Progress circle
            Circle()
                .trim(from: 0.0, to: min(CGFloat(progress), 1.0))
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: gradient),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.linear, value: progress)
            
            // Progress text
            if progress > 0 {
                Text("\(Int(ceil(progress * 100)))%")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 40, height: 40)
    }
}

struct NavStackedBlocksView: View {
    var blockTitles: [String] = ["Recents", "Screenshots", "Favorites", "Years", "Albums"]

    @State private var expandedSections: Set<Int> = [] // Tracks expanded sections
    @State private var selectedIndex: IdentifiableInt? = nil // Wrap Int in Identifiable struct
    @State private var folders: [PHAssetCollection] = []
    @State private var yearsList: [String] = [] // Stores fetched years with photos
    @State private var selectedFolderAssets: [PHAsset] = [] // Store fetched assets
    @State private var selectedYearAssets: [PHAsset] = [] // Store fetched assets for selected year
    @State private var isFolderSelected = false // Track when a folder is clicked
    @State private var isYearSelected = false // Track when a year is clicked
    
    // Add loading states
    @State private var isFoldersLoading = false
    @State private var isYearsLoading = false
    
    // Add state to track whether assets are ready
    @State private var areFolderAssetsReady = false
    @State private var areYearAssetsReady = false
    
    // Add state variables to track progress
    @State private var categoryProgress: [Int: Double] = [:]
    @State private var yearProgress: [String: Double] = [:]
    @State private var albumProgress: [String: Double] = [:]
    
    // Add a progress calculation task to track and cancel background work
    @State private var progressCalculationTask: Task<Void, Never>? = nil
    @State private var isCalculatingProgress = false

    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 5) {
                    Spacer().frame(height: 5) // Adjust top spacing
                    blockListView()
                }
                .padding(.horizontal, 3)
            }
            .background(Color.black)
            // Calculate progress values when view appears
            .onAppear {
                startProgressCalculation()
            }
            .refreshable {
                startProgressCalculation(forceRefresh: true)
            }
        }
        .fullScreenCover(item: $selectedIndex) { item in
            destinationView(for: item.value)
        }
        .fullScreenCover(isPresented: $isFolderSelected, onDismiss: {
            areFolderAssetsReady = false
            selectedFolderAssets = [] // ⬅️ ADD THIS LINE
            startProgressCalculation()
        }) {
            if areFolderAssetsReady {
                FilteredSwipeStack(filterOptions: createFolderFilterOptions())
            } else {
                LoadingView(message: "Loading folder media...") {
                    isFolderSelected = false
                }
            }
        }

        .fullScreenCover(isPresented: $isYearSelected, onDismiss: {
            areYearAssetsReady = false
            selectedYearAssets = [] // ⬅️ ADD THIS LINE
            startProgressCalculation()
        }) {
            if areYearAssetsReady {
                FilteredSwipeStack(filterOptions: createYearFilterOptions())
            } else {
                LoadingView(message: "Loading year media...") {
                    isYearSelected = false
                }
            }
        }
    }

    /// **Extracted Function**: Builds the list of blocks
    private func blockListView() -> some View {
        ForEach(0..<blockTitles.count, id: \.self) { index in
            VStack {
                if index == 3 || index == 4 { // "Years" and "Albums" are expandable
                    expandableBlock(index: index)
                } else {
                    fullScreenNavigationBlock(index: index)
                }
            }
        }
        .overlay(
            Group {
                if isCalculatingProgress {
                    // Small, unobtrusive loading indicator in the corner
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 20, height: 20)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding()
                }
            }
        )
    }

    /// **Expandable Block for "Years" and "Albums"**
    private func expandableBlock(index: Int) -> some View {
        VStack {
            Button(action: {
                toggleSection(index)
                // Only load data when section is expanded and data is empty
                if expandedSections.contains(index) {
                    if index == 3 && yearsList.isEmpty && !isYearsLoading {
                        loadYearsInBackground()
                    } else if index == 4 && folders.isEmpty && !isFoldersLoading {
                        loadFoldersInBackground()
                    }
                }
            }) {
                blockView(index: index, showChevron: true)
            }
            .buttonStyle(PlainButtonStyle())

            if expandedSections.contains(index) {
                expandedContent(for: index)
                    .padding(.horizontal, 10)
                    .transition(.opacity)
            }
        }
    }
    
    // Load years asynchronously
    private func loadYearsInBackground() {
        isYearsLoading = true
        Task {
            await fetchYears()
        }
    }
    
    // Load folders asynchronously
    private func loadFoldersInBackground() {
        isFoldersLoading = true
        Task {
            await fetchFolders()
        }
    }

    /// **Full-Screen Navigation Block**
    private func fullScreenNavigationBlock(index: Int) -> some View {
        Button(action: { selectedIndex = IdentifiableInt(value: index) }) {
            blockView(index: index, showChevron: false)
        }
    }

    /// **Block UI View (Extracted for Reuse)**
    private func blockView(index: Int, showChevron: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(LinearGradient(
                gradient: Gradient(colors: gradientColors(for: index)),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(height: 75)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            .overlay(
                HStack {
                    Text(blockTitles[index])
                        .foregroundColor(.white)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .padding(.leading, 15)
                    Spacer()
                    
                    // Show progress indicator if progress > 0
                    if let progress = categoryProgress[index], progress > 0 {
                        CircularProgressView(progress: progress, gradient: gradientColors(for: index))
                            .padding(.trailing, showChevron ? 10 : 15)
                    }
                    
                    if showChevron {
                        Image(systemName: expandedSections.contains(index) ? "chevron.down" : "chevron.right")
                            .foregroundColor(.white)
                            .padding(.trailing, 15)
                    }
                }
            )
    }

    /// **Function to Toggle Expandable Sections**
    private func toggleSection(_ index: Int) {
        if expandedSections.contains(index) {
            expandedSections.remove(index)
        } else {
            expandedSections.insert(index)
        }
    }

    /// **Expanded Content for Years & Albums**
    private func expandedContent(for index: Int) -> some View {
        VStack {
            if index == 3 { // Years Section
                if isYearsLoading {
                    ProgressView("Loading years...")
                        .foregroundColor(.gray)
                        .padding()
                } else if yearsList.isEmpty {
                    Text("No Years Found")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    ForEach(yearsList, id: \.self) { year in
                        Button(action: {
                            fetchAssets(forYear: year)
                        }) {
                            yearBlock(title: year)
                        }
                    }
                }
            } else if index == 4 { // Albums Section (Folders)
                if isFoldersLoading {
                    ProgressView("Loading albums...")
                        .foregroundColor(.gray)
                        .padding()
                } else if folders.isEmpty {
                    Text("No Albums Found")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    ForEach(folders, id: \.localIdentifier) { folder in
                        Button(action: {
                            fetchAssets(for: folder) // Fetch assets for selected folder
                        }) {
                            albumBlock(title: folder.localizedTitle ?? "Unknown Album")
                        }
                    }
                }
            }
        }
    }
    
    // Optimized progress calculation method - runs in background
    private func startProgressCalculation(forceRefresh: Bool = false) {
        // Cancel any existing calculation
        progressCalculationTask?.cancel()
        
        // If SwipedMediaManager has no swiped media and we're not forcing a refresh, skip the calculation
        if SwipedMediaManager.shared.swipeCount == 0 && !forceRefresh {
            // Clear all progress values if no swiped media
            categoryProgress = [:]
            yearProgress = [:]
            albumProgress = [:]
            return
        }
        
        // Show the loading indicator if there's swiped media
        if SwipedMediaManager.shared.swipeCount > 0 {
            isCalculatingProgress = true
        }
        
        // Create a new background task
        progressCalculationTask = Task {
            // Check for cancellation
            if Task.isCancelled { return }
            
            // Use ProgressManager to get cached or calculate new progress values
            let categoryResults = await ProgressManager.shared.getCategoryProgress()
            let yearResults = await ProgressManager.shared.getYearProgress(for: yearsList)
            let albumResults = await ProgressManager.shared.getAlbumProgress(for: folders)
            
            // Only update the UI if the task hasn't been cancelled
            if !Task.isCancelled {
                // Update the UI on the main thread
                await MainActor.run {
                    self.categoryProgress = categoryResults
                    self.yearProgress = yearResults
                    self.albumProgress = albumResults
                    self.isCalculatingProgress = false
                }
            }
        }
    }
}

// Add a simple loading view
struct LoadingView: View {
    var message: String
    var onCancel: () -> Void
    
    var body: some View {
        ZStack {
            // Black background
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 25) {
                // Green glowing circle with spinner
                ZStack {
                    // Outer glow effect
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .blur(radius: 10)
                    
                    // Inner circle
                    Circle()
                        .fill(Color.black)
                        .frame(width: 100, height: 100)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.green.opacity(0.8), Color.green.opacity(0.4)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                        )
                    
                    // Progress spinner
                    ProgressView()
                        .scaleEffect(1.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.green))
                }
                
                // Loading message
                Text(message)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                // Cancel button
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 30)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.green.opacity(0.7), Color.blue.opacity(0.7)]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: Color.green.opacity(0.5), radius: 5, x: 0, y: 2)
                }
                .padding(.top, 10)
            }
            .padding(30)
            // Add a subtle animation
            .scaleEffect(1.0)
            .animation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: UUID())
        }
    }
}

extension NavStackedBlocksView {
    /// **Fetch photos for the selected folder with pagination**
    private func fetchAssets(for collection: PHAssetCollection) {
        // First show the loading screen
        areFolderAssetsReady = false
        isFolderSelected = true
        
        Task {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            // Remove fetch limit to allow all assets
            
            let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
            
            var tempAssets: [PHAsset] = []
            tempAssets.reserveCapacity(assets.count) // Pre-allocate memory
            
            // Use batched fetching for better performance
            let totalAssets = assets.count
            
            // Skip if no assets to process
            if totalAssets == 0 {
                await MainActor.run {
                    self.selectedFolderAssets = []
                    self.areFolderAssetsReady = true
                }
                return
            }
            
            let batchSize = max(1, min(500, totalAssets)) // Process in batches of 500, ensure at least 1
            
            // Use our utility class for batch processing with cancellation check
            var isCancelled = false
            for batchStart in stride(from: 0, to: totalAssets, by: batchSize) {
                if !isFolderSelected {
                    isCancelled = true
                    break
                }
                
                autoreleasepool {
                    let batchEnd = min(batchStart + batchSize, totalAssets)
                    for i in batchStart..<batchEnd {
                        let asset = assets.object(at: i)
                        tempAssets.append(asset)
                    }
                }
            }
            
            // If canceled, return early
            if isCancelled {
                return
            }
            
            await MainActor.run {
                self.selectedFolderAssets = [] // Force UI update
                self.selectedFolderAssets = tempAssets
                self.areFolderAssetsReady = true
            }
        }
    }

    /// **Fetch photos and videos for the selected year with pagination**
    private func fetchAssets(forYear year: String) {
        // First show the loading screen
        areYearAssetsReady = false
        isYearSelected = true
        
        Task {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            // Remove fetch limit to allow all assets
            
            // Fetch both images AND videos
            let assets = PHAsset.fetchAssets(with: fetchOptions)
            
            var tempAssets: [PHAsset] = []
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM ''yy"
            
            // Use batched fetching for better performance
            let totalAssets = assets.count
            
            // Skip if no assets to process
            if totalAssets == 0 {
                await MainActor.run {
                    self.selectedYearAssets = []
                    self.areYearAssetsReady = true
                }
                return
            }
            
            let batchSize = max(1, min(500, totalAssets)) // Process in batches of 500, ensure at least 1
            
            // Use our utility class for batch processing with cancellation check
            var isCancelled = false
            for batchStart in stride(from: 0, to: totalAssets, by: batchSize) {
                if !isYearSelected {
                    isCancelled = true
                    break
                }
                
                autoreleasepool {
                    let batchEnd = min(batchStart + batchSize, totalAssets)
                    for i in batchStart..<batchEnd {
                        let asset = assets.object(at: i)
                        if let creationDate = asset.creationDate {
                            let formattedDate = dateFormatter.string(from: creationDate)
                            if formattedDate == year {
                                tempAssets.append(asset)
                            }
                        }
                    }
                }
            }
            
            // If canceled, return early
            if isCancelled {
                return
            }
            
            await MainActor.run {
                self.selectedYearAssets = [] // Force UI update
                self.selectedYearAssets = tempAssets
                self.areYearAssetsReady = true
            }
        }
    }

    /// **Generate filter options for selected folder**
    private func createFolderFilterOptions() -> PHFetchOptions {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        // Get the swiped media identifiers from SwipedMediaManager
        let swipedIdentifiers = Array(SwipedMediaManager.shared.getSwipedMediaIdentifiers())
        
        if swipedIdentifiers.isEmpty {
            // If no swiped media yet, just filter by the selected folder
            fetchOptions.predicate = NSPredicate(format: "SELF IN %@", selectedFolderAssets)
        } else {
            // Filter by the selected folder AND exclude already swiped media
            fetchOptions.predicate = NSPredicate(format: "SELF IN %@ AND NOT (localIdentifier IN %@)",
                                               selectedFolderAssets, swipedIdentifiers)
        }
        
        return fetchOptions
    }

    /// **Generate filter options for selected year**
    private func createYearFilterOptions() -> PHFetchOptions {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        // Get the swiped media identifiers from SwipedMediaManager
        let swipedIdentifiers = Array(SwipedMediaManager.shared.getSwipedMediaIdentifiers())
        
        if swipedIdentifiers.isEmpty {
            // If no swiped media yet, just filter by the selected year
            fetchOptions.predicate = NSPredicate(format: "SELF IN %@", selectedYearAssets)
        } else {
            // Filter by the selected year AND exclude already swiped media
            fetchOptions.predicate = NSPredicate(format: "SELF IN %@ AND NOT (localIdentifier IN %@)",
                                               selectedYearAssets, swipedIdentifiers)
        }
        
        return fetchOptions
    }

    /// **Year Block (Same UI as Main Blocks)**
    private func yearBlock(title: String) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(LinearGradient(
                gradient: Gradient(colors: [Color.red.opacity(0.7), Color.pink.opacity(0.7)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(height: 75)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            .overlay(
                HStack {
                    Text(title)
                        .foregroundColor(.white)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .padding(.leading, 15)
                    Spacer()
                    
                    // Show progress indicator if progress > 0
                    if let progress = yearProgress[title], progress > 0 {
                        CircularProgressView(progress: progress, gradient: [Color.red.opacity(0.7), Color.pink.opacity(0.7)])
                            .padding(.trailing, 15)
                    }
                }
            )
            .padding(.top, 2)
    }

    /// **Album Block (Same UI as Main Blocks)**
    private func albumBlock(title: String) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(LinearGradient(
                gradient: Gradient(colors: [Color.orange.opacity(0.7), Color.yellow.opacity(0.7)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(height: 75)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            .overlay(
                HStack {
                    Text(title)
                        .foregroundColor(.white)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .padding(.leading, 15)
                    Spacer()
                    
                    // Show progress indicator if progress > 0
                    if let progress = albumProgress[title], progress > 0 {
                        CircularProgressView(progress: progress, gradient: [Color.orange.opacity(0.7), Color.yellow.opacity(0.7)])
                            .padding(.trailing, 15)
                    }
                }
            )
            .padding(.top, 2)
    }

    /// **Gradient Colors Function**
    private func gradientColors(for index: Int) -> [Color] {
        switch index {
        case 3: // Years Section
            return [Color.red.opacity(0.7), Color.pink.opacity(0.7)]
        case 4: // Albums Section
            return [Color.orange.opacity(0.7), Color.yellow.opacity(0.7)]
        default:
            return [Color.green.opacity(0.7), Color.blue.opacity(0.7)]
        }
    }

    /// **Destination View**
    private func destinationView(for index: Int) -> some View {
        switch index {
        case 0:
            return AnyView(RecentsView())
        case 1:
            return AnyView(ScreenshotsView())
        case 2:
            return AnyView(FavoritesView())
        default:
            return AnyView(Text("Unknown View"))
        }
    }

    /// **Fetch Available Folders (Sorted by Creation Date)**
    private func fetchFolders() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized else {
            print("Photo access denied")
            await MainActor.run {
                self.isFoldersLoading = false
            }
            return
        }

        let allFolders = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var tempFolders: [PHAssetCollection] = []
        tempFolders.reserveCapacity(allFolders.count) // Pre-allocate capacity

        // Use autoreleasepool to prevent memory pressure during enumeration
        for i in 0..<allFolders.count {
            autoreleasepool {
                let collection = allFolders.object(at: i)
                if PHAsset.fetchAssets(in: collection, options: nil).count > 0 {
                    tempFolders.append(collection)
                }
            }
        }

        await MainActor.run {
            self.folders = tempFolders
            self.isFoldersLoading = false
            
            // After loading folders, update their progress in the background
            startProgressCalculation()
        }
    }

    /// **Fetch Available Years from Photos (Sorted & Unique)**
    private func fetchYears() async {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let assets = PHAsset.fetchAssets(with: fetchOptions)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM ''yy" // Formats like "Jan '25"

        var uniqueDates: Set<String> = [] // Prevents duplicate months
        var sortedDates: [(year: Int, month: Int, formatted: String)] = []

        // Process in batches to improve performance
        let totalAssets = assets.count
        
        // Skip if no assets to process
        if totalAssets == 0 {
            await MainActor.run {
                self.yearsList = []
                self.isYearsLoading = false
            }
            return
        }
        
        let batchSize = max(1, min(500, totalAssets)) // Process in batches of 500, ensure at least 1
        
        PHAssetBatchProcessor.processBatched(fetchResult: assets, batchSize: batchSize) { asset in
            if let creationDate = asset.creationDate {
                let formattedDate = dateFormatter.string(from: creationDate)

                let calendar = Calendar.current
                let components = calendar.dateComponents([.year, .month], from: creationDate)

                if let year = components.year, let month = components.month {
                    if !uniqueDates.contains(formattedDate) { // Avoid duplicate months
                        uniqueDates.insert(formattedDate)
                        sortedDates.append((year, month, formattedDate))
                    }
                }
            }
        }

        // Sort by Year (Descending), then by Month (Descending)
        sortedDates.sort {
            if $0.year == $1.year {
                return $0.month > $1.month
            }
            return $0.year > $1.year
        }

        await MainActor.run {
            self.yearsList = sortedDates.map { $0.formatted }
            self.isYearsLoading = false
            
            // After loading years, update their progress
            startProgressCalculation()
        }
    }
}

/// **Wrapper for Int to Conform to Identifiable**
struct IdentifiableInt: Identifiable {
    let id = UUID()
    let value: Int
}

