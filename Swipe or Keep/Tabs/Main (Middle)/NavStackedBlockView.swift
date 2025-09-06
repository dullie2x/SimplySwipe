import SwiftUI
import Photos
import AVKit

// MARK: - Search Result Model
struct SearchResult {
    let id: String
    let title: String
    let subtitle: String
    let type: SearchResultType
    let data: Any
}

enum SearchResultType {
    case year
    case album
}

struct CircularProgressView: View {
    var progress: Double
    var gradient: [Color]
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(lineWidth: 3)
                .opacity(0.2)
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
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.linear, value: progress)
            
            // Progress text
            if progress > 0 {
                Text("\(Int(ceil(progress * 100)))%")
                    .font(.custom(AppFont.regular, size: 10))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 40, height: 40)
    }
}

struct NavStackedBlocksView: View {
    var blockTitles: [String] = ["Recents", "Screenshots", "Favorites", "Years", "Albums"]

    @State private var selectedIndex: IdentifiableInt? = nil
    @State private var selectedFolderAssets: [PHAsset] = []
    @State private var selectedYearAssets: [PHAsset] = []
    @State private var isFolderSelected = false
    @State private var isYearSelected = false
    
    // Add state to track whether assets are ready
    @State private var areFolderAssetsReady = false
    @State private var areYearAssetsReady = false
    
    // NEW: Search state tracking
    @State private var isYearsSectionExpanded = false
    @State private var isAlbumsSectionExpanded = false
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var showingSearchResults = false
    
    // Use shared data manager instead of local state
    @StateObject private var dataManager = MediaDataManager.shared


    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 20) {
                    // Search bar (shows when pulling to refresh)
                    if isSearching {
                        searchBarView()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    Spacer().frame(height: 10)
                    
                    // Show search results or normal content
                    if showingSearchResults {
                        searchResultsView()
                    } else {
                        normalContentView()
                    }
                    
                    Spacer().frame(height: 20)
                }
                .padding(.horizontal, 16)
            }
            .background(Color.black)
            .refreshable {
                // Trigger search mode
                withAnimation(.easeInOut(duration: 0.3)) {
                    isSearching = true
                }
            }
            // Removed .onAppear - data is already loaded!
        }
        .fullScreenCover(item: $selectedIndex, onDismiss: {
            Task { await refreshProgress() }
        }) { item in
            destinationView(for: item.value)
        }

        .fullScreenCover(isPresented: $isFolderSelected, onDismiss: {
            areFolderAssetsReady = false
            selectedFolderAssets = []
            Task { await refreshProgress() }
        }) {
            if areFolderAssetsReady {
                FilteredVertScroll(filterOptions: createFolderFilterOptions())
            } else {
                LoadingView(message: "Loading folder media...") {
                    isFolderSelected = false
                }
            }
        }

        .fullScreenCover(isPresented: $isYearSelected, onDismiss: {
            areYearAssetsReady = false
            selectedYearAssets = []
            Task { await refreshProgress() }
        }) {
            if areYearAssetsReady {
                FilteredVertScroll(filterOptions: createYearFilterOptions())
            } else {
                LoadingView(message: "Loading year media...") {
                    isYearSelected = false
                }
            }
        }
    }
    // MARK: - Search Bar View
    private func searchBarView() -> some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.system(size: 16))
                
                if #available(iOS 17.0, *) {
                    TextField("Search time periods...", text: $searchText)
                        .foregroundColor(.white)
                        .font(.custom(AppFont.regular, size: 16))
                        .textFieldStyle(PlainTextFieldStyle())
                        .onChange(of: searchText) { _, newValue in
                            performSearch(query: newValue)
                        }
                } else {
                    TextField("Search time periods...", text: $searchText)
                        .foregroundColor(.white)
                        .font(.custom(AppFont.regular, size: 16))
                        .textFieldStyle(PlainTextFieldStyle())
                        .onChange(of: searchText) { newValue in
                            performSearch(query: newValue)
                        }
                }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searchResults = []
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showingSearchResults = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.6))
                            .font(.system(size: 16))
                    }
                }
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isSearching = false
                        showingSearchResults = false
                        searchText = ""
                        searchResults = []
                    }
                }) {
                    Text("Cancel")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.custom(AppFont.regular, size: 16))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.2))
            )
            
            // Search suggestions
            if searchText.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Search Suggestions")
                            .foregroundColor(.white)
                            .font(.custom(AppFont.regular, size: 20))

                        Spacer()
                        
                        Image(systemName: "lightbulb")
                            .foregroundColor(.white.opacity(0.6))
                            .font(.system(size: 16))
                    }
                    .padding(.horizontal, 4)
                    
                    // Examples section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.white.opacity(0.6))
                                .font(.system(size: 14))
                            
                            Text("Try searching for:")
                                .foregroundColor(.white.opacity(0.8))
                                .font(.custom(AppFont.regular, size: 16))
                        }
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(getSearchExamples(), id: \.self) { example in
                                    Button(action: {
                                        searchText = example
                                        performSearch(query: example)
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "quote.bubble")
                                                .foregroundColor(.white.opacity(0.6))
                                                .font(.system(size: 12))
                                            
                                            Text(example)
                                                .foregroundColor(.white)
                                                .font(.custom(AppFont.regular, size: 14))
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 20)
                                                .fill(Color.white.opacity(0.1))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 20)
                                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(SearchSuggestionButtonStyle())
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                    
                    // Quick actions section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "bolt")
                                .foregroundColor(.white.opacity(0.6))
                                .font(.system(size: 14))
                            
                            Text("Quick Actions")
                                .foregroundColor(.white.opacity(0.8))
                                .font(.custom(AppFont.regular, size: 16))
                        }
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                            ForEach(getQuickActions(), id: \.title) { action in
                                Button(action: {
                                    searchText = action.query
                                    performSearch(query: action.query)
                                }) {
                                    VStack(spacing: 8) {
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        gradient: Gradient(colors: action.gradientColors),
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 44, height: 44)
                                                .shadow(color: action.gradientColors.first?.opacity(0.3) ?? Color.clear, radius: 4, x: 0, y: 2)
                                            
                                            Image(systemName: action.icon)
                                                .foregroundColor(.white)
                                                .font(.system(size: 18, weight: .semibold))
                                        }
                                        
                                        VStack(spacing: 2) {
                                            Text(action.title)
                                                .foregroundColor(.white)
                                                .font(.custom(AppFont.regular, size: 14))
                                                .lineLimit(1)
                                            
//                                            Text(action.subtitle)
//                                                .foregroundColor(.white.opacity(0.6))
//                                                .font(.custom(AppFont.regular, size: 12))
//                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .padding(.horizontal, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.white.opacity(0.05))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .stroke(
                                                        LinearGradient(
                                                            gradient: Gradient(colors: [
                                                                Color.white.opacity(0.1),
                                                                Color.white.opacity(0.05)
                                                            ]),
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        ),
                                                        lineWidth: 1
                                                    )
                                            )
                                    )
                                }
                                .buttonStyle(QuickActionButtonStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 8)
            }
        }
    }
    
    // MARK: - Search Results View
    private func searchResultsView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Simple results header
            HStack {
                Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.custom(AppFont.regular, size: 14))

                Spacer()
            }
            .padding(.horizontal, 4)
            
            if searchResults.isEmpty && !searchText.isEmpty {
                // Simple empty state
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.4))
                        .font(.system(size: 28))
                    
                    Text("No results found")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.custom(AppFont.regular, size: 16))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            } else {
                // Simple results list
                VStack(spacing: 8) {
                    ForEach(searchResults, id: \.id) { result in
                        Button(action: {
                            selectSearchResult(result)
                        }) {
                            simpleSearchResultRow(result: result)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }
    
    // MARK: - Simple Search Result Row
    private func simpleSearchResultRow(result: SearchResult) -> some View {
        HStack(spacing: 12) {
            // Simple icon
            Image(systemName: result.type == .year ? "calendar" : "rectangle.stack")
                .foregroundColor(.white.opacity(0.7))
                .font(.system(size: 18))
                .frame(width: 24)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .foregroundColor(.white)
                    .font(.custom(AppFont.regular, size: 16))

                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .foregroundColor(.white.opacity(0.6))
                        .font(.custom(AppFont.regular, size: 14))
                }
            }
            
            Spacer()
            
            // Simple arrow
            Image(systemName: "chevron.right")
                .foregroundColor(.white.opacity(0.4))
                .font(.system(size: 12))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
        )
    }
    
    // MARK: - Normal Content View (updated to use dataManager)
    private func normalContentView() -> some View {
        VStack(spacing: 20) {
            // Main categories (always visible as large blocks)
            mainCategoriesView()
                // REMOVED: .zIndex(10)
            
            // Years section - large block or expanded grid
            if !dataManager.yearsList.isEmpty {
                if isYearsSectionExpanded {
                    expandedYearsView()
                        // REMOVED: .zIndex(8)
                        .clipped()
                } else {
                    largeYearsBlock()
                        // REMOVED: .zIndex(8)
                        .clipped()
                }
            }
            
            // Albums section - large block or expanded grid
            if !dataManager.folders.isEmpty {
                if isAlbumsSectionExpanded {
                    expandedAlbumsView()
                        // REMOVED: .zIndex(6)
                } else {
                    largeAlbumsBlock()
                        // REMOVED: .zIndex(6)
                }
            }
        }
    }
    
    // MARK: - Main Categories View (updated to use dataManager)
    private func mainCategoriesView() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(0..<3, id: \.self) { index in
                Button(action: {
                    print("DEBUG: Category \(index) tapped") // Add debug logging
                    selectedIndex = IdentifiableInt(value: index)
                }) {
                    appleCategoryBlock(index: index)
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle()) // Move contentShape here
                // REMOVED: .allowsHitTesting(true) - redundant
            }
        }
    }
    
    // MARK: - Large Years Block (updated - no loading state)
    private func largeYearsBlock() -> some View {
        Button(action: {
            print("DEBUG: Years block tapped") // Add debug logging
            withAnimation(.easeInOut(duration: 0.3)) {
                isYearsSectionExpanded = true
            }
        }) {
            appleLargeSectionBlock(
                title: "Years",
                subtitle: "Browse by time period",
                gradientColors: [Color.red.opacity(0.7), Color.pink.opacity(0.7)],
                previewImages: getYearsPreviewImages()
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle()) // Ensure proper touch area
    }
    
    // MARK: - Large Albums Block (updated - no loading state)
    private func largeAlbumsBlock() -> some View {
        Button(action: {
            print("DEBUG: Albums block tapped") // Add debug logging
            withAnimation(.easeInOut(duration: 0.3)) {
                isAlbumsSectionExpanded = true
            }
        }) {
            appleLargeSectionBlock(
                title: "Albums",
                subtitle: "Browse collections",
                gradientColors: [Color.orange.opacity(0.7), Color.yellow.opacity(0.7)],
                previewImages: getAlbumsPreviewImages()
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle()) // Ensure proper touch area
    }
    
    // MARK: - Expanded Years View (updated to use dataManager)
    private func expandedYearsView() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with collapse button
            HStack {
                Text("Years")
                    .foregroundColor(.white)
                    .font(.custom(AppFont.regular, size: 24))

                Spacer()
                
                Button(action: {
                    print("DEBUG: Years collapse tapped") // Add debug logging
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isYearsSectionExpanded = false
                    }
                }) {
                    Image(systemName: "chevron.up")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 24, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Circle()) // Ensure proper touch area for circle
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
            
            // 2x2 Grid of years
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 20) {
                ForEach(dataManager.yearsList, id: \.self) { year in
                    Button(action: {
                        print("DEBUG: Year \(year) tapped") // Add debug logging
                        fetchAssets(forYear: year)
                    }) {
                        appleYearBlock(title: year)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contentShape(Rectangle()) // Ensure proper touch area
                }
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Expanded Albums View (updated to use dataManager)
    private func expandedAlbumsView() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with collapse button
            HStack {
                Text("Albums")
                    .foregroundColor(.white)
                    .font(.custom(AppFont.regular, size: 24))

                Spacer()
                
                Button(action: {
                    print("DEBUG: Albums collapse tapped") // Add debug logging
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isAlbumsSectionExpanded = false
                    }
                }) {
                    Image(systemName: "chevron.up")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 24, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.1))
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Circle()) // Ensure proper touch area for circle
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
            
            // 2x2 Grid of albums
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 20) {
                ForEach(dataManager.folders, id: \.localIdentifier) { folder in
                    Button(action: {
                        print("DEBUG: Album \(folder.localizedTitle ?? "Unknown") tapped") // Add debug logging
                        fetchAssets(for: folder)
                    }) {
                        appleAlbumBlock(title: folder.localizedTitle ?? "Unknown Album")
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contentShape(Rectangle()) // Ensure proper touch area
                }
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Large Section Block (updated - no loading states!)
    private func appleLargeSectionBlock(title: String, subtitle: String, gradientColors: [Color], previewImages: [UIImage]) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.15))
            .frame(height: 200)
            .clipped()
            .overlay(
                ZStack {
                    // Background preview images
                    if !previewImages.isEmpty {
                        photoPreviewGrid(images: previewImages)
                    } else {
                        // Fallback gradient background
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: gradientColors),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .opacity(0.7)
                    }
                    
                    // Dark overlay for text readability
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.black.opacity(0.6),
                                    Color.black.opacity(0.3),
                                    Color.clear
                                ]),
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                    
                    // Content overlay
                    VStack {
                        Spacer()
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title)
                                    .foregroundColor(.white)
                                    .font(.custom(AppFont.regular, size: 28))

//                                Text(subtitle)
//                                    .foregroundColor(.white.opacity(0.8))
//                                    .font(.custom(AppFont.regular, size: 16))
                            }
                            
                            Spacer()
                            
                            // Simple expand indicator (no loading spinner needed)
                            Image(systemName: "chevron.down")
                                .foregroundColor(.white.opacity(0.8))
                                .font(.system(size: 28, weight: .medium))
                                .frame(width: 60, height: 60)
                        }
                        .padding(20)
                    }
                }
            )
    }
    
    // MARK: - Apple-style Category Block (updated to use dataManager)
    private func appleCategoryBlock(index: Int) -> some View {
        let progress = dataManager.categoryProgress[index] ?? 0
        let done = progress >= 0.999

        return RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.15))
            .frame(height: 200)
            .overlay(
                ZStack {
                    // Background (unchanged)
                    if let previewImages = dataManager.sectionPreviewImages[index], !previewImages.isEmpty {
                        photoPreviewGrid(images: previewImages)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: gradientColors(for: index)),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .opacity(0.7)
                    }

                    // Dark overlay (unchanged)
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.black.opacity(0.6),
                                    Color.black.opacity(0.3),
                                    Color.clear
                                ]),
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )

                    // CONSOLIDATED OVERLAY - All content in one place
                    ZStack {
                        // Done overlay (if needed)
                        if done {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    LinearGradient(
                                        colors: [Color.black.opacity(0.15), Color.clear],
                                        startPoint: .bottom, endPoint: .top
                                    )
                                )
                                .allowsHitTesting(false)
                        }
                        
                        // Content overlay
                        VStack {
                            Spacer()
                            HStack(alignment: .bottom) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(blockTitles[index])
                                        .foregroundColor(.white)
                                        .font(.custom(AppFont.regular, size: done ? 20 : 28))
                                }
                                Spacer()
                                if progress > 0 {
                                    CircularProgressView(
                                        progress: progress,
                                        gradient: done ?
                                            [Color.blue.opacity(0.9), Color.blue.opacity(0.7)] :
                                            [Color.white.opacity(0.8), Color.white.opacity(0.6)]
                                    )
                                }
                            }
                            .padding(20)
                        }
                    }
                }
            )
            // REMOVED: Multiple separate overlays
            // REMOVED: .contentShape(Rectangle()) - moved to button level
    }
    
    // MARK: - Apple-style Year Block (updated to use dataManager)
    private func appleYearBlock(title: String) -> some View {
        let progress = dataManager.yearProgress[title] ?? 0
        let done = progress >= 0.999

        return RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.15))
            .aspectRatio(1.3, contentMode: .fit)
            .overlay(
                ZStack {
                    // Background
                    if let previewImages = dataManager.yearPreviewImages[title], !previewImages.isEmpty {
                        photoPreviewGrid(images: previewImages)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [Color.red.opacity(0.6), Color.pink.opacity(0.6)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    }

                    // Dark overlay
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.black.opacity(0.5), Color.clear]),
                                startPoint: .bottom,
                                endPoint: .center
                            )
                        )

                    // CONSOLIDATED content overlay
                    ZStack {
                        if done {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    LinearGradient(
                                        colors: [Color.black.opacity(0.15), Color.clear],
                                        startPoint: .bottom, endPoint: .top
                                    )
                                )
                                .allowsHitTesting(false)
                        }
                        
                        VStack {
                            Spacer()
                            HStack(alignment: .bottom) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title)
                                        .foregroundColor(.white)
                                        .font(.custom(AppFont.regular, size: 18))
                                }
                                Spacer()
                                if progress > 0 {
                                    CircularProgressView(
                                        progress: progress,
                                        gradient: done ?
                                            [Color.blue.opacity(0.9), Color.blue.opacity(0.7)] :
                                            [Color.white.opacity(0.8), Color.white.opacity(0.6)]
                                    )
                                }
                            }
                            .padding(12)
                        }
                    }
                }
            )
    }


    
    // MARK: - Apple-style Album Block (updated to use dataManager)
    private func appleAlbumBlock(title: String) -> some View {
        let progress = dataManager.albumProgress[title] ?? 0
        let done = progress >= 0.999

        return RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.15))
            .aspectRatio(1.3, contentMode: .fit)
            .overlay(
                ZStack {
                    // Background
                    if let previewImages = dataManager.albumPreviewImages[title], !previewImages.isEmpty {
                        photoPreviewGrid(images: previewImages)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [Color.orange.opacity(0.6), Color.yellow.opacity(0.6)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    }

                    // Dark overlay
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.black.opacity(0.5), Color.clear]),
                                startPoint: .bottom,
                                endPoint: .center
                            )
                        )

                    // CONSOLIDATED content overlay
                    ZStack {
                        if done {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    LinearGradient(
                                        colors: [Color.black.opacity(0.15), Color.clear],
                                        startPoint: .bottom, endPoint: .top
                                    )
                                )
                                .allowsHitTesting(false)
                        }
                        
                        VStack {
                            Spacer()
                            HStack(alignment: .bottom) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title)
                                        .foregroundColor(.white)
                                        .font(.custom(AppFont.regular, size: 16))
                                        .lineLimit(2)
                                }
                                Spacer()
                                if progress > 0 {
                                    CircularProgressView(
                                        progress: progress,
                                        gradient: done ?
                                            [Color.blue.opacity(0.9), Color.blue.opacity(0.7)] :
                                            [Color.white.opacity(0.8), Color.white.opacity(0.6)]
                                    )
                                }
                            }
                            .padding(12)
                        }
                    }
                }
            )
    }
    
    // MARK: - Photo Preview Grid (simplified to single image)
    private func photoPreviewGrid(images: [UIImage]) -> some View {
        GeometryReader { geometry in
            let size = geometry.size
            
            if let firstImage = images.first {
                // Single image only
                Image(uiImage: firstImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Helper functions to get preview images from dataManager
    
    @MainActor
    private func refreshProgress() async {
        let cats = await ProgressManager.shared.getCategoryProgress()
        dataManager.categoryProgress = cats

        let yrs = await ProgressManager.shared.getYearProgress(for: dataManager.yearsList)
        dataManager.yearProgress = yrs

        let albs = await ProgressManager.shared.getAlbumProgress(for: dataManager.folders)
        var byTitle: [String: Double] = [:]
        for folder in dataManager.folders {
            if let title = folder.localizedTitle, let p = albs[title] {
                byTitle[title] = p
            }
        }
        dataManager.albumProgress = byTitle
    }

    private func getYearsPreviewImages() -> [UIImage] {
        let firstFewYears = Array(dataManager.yearsList.prefix(4))
        var allImages: [UIImage] = []
        
        for year in firstFewYears {
            if let images = dataManager.yearPreviewImages[year] {
                allImages.append(contentsOf: images)
                if allImages.count >= 4 { break }
            }
        }
        
        return Array(allImages.prefix(4))
    }
    
    private func getAlbumsPreviewImages() -> [UIImage] {
        let firstFewAlbums = Array(dataManager.folders.prefix(4))
        var allImages: [UIImage] = []
        
        for folder in firstFewAlbums {
            let albumTitle = folder.localizedTitle ?? "Unknown Album"
            if let images = dataManager.albumPreviewImages[albumTitle] {
                allImages.append(contentsOf: images)
                if allImages.count >= 4 { break }
            }
        }
        
        return Array(allImages.prefix(4))
    }
    
    private func isCategoryDone(_ index: Int) -> Bool { (dataManager.categoryProgress[index] ?? 0) >= 0.999 }
    private func isYearDone(_ title: String) -> Bool { (dataManager.yearProgress[title] ?? 0) >= 0.999 }
    private func isAlbumDone(_ title: String) -> Bool { (dataManager.albumProgress[title] ?? 0) >= 0.999 }

    
    // MARK: - Search Logic (updated to use dataManager)
    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            withAnimation(.easeInOut(duration: 0.3)) {
                showingSearchResults = false
            }
            return
        }
        
        var results: [SearchResult] = []
        let lowercaseQuery = query.lowercased()
        
        // Search using month-year data for granular results
        for monthYear in dataManager.monthYearsList {
            if matchesDateQuery(year: monthYear, query: lowercaseQuery) {
                results.append(SearchResult(
                    id: "monthyear_\(monthYear)",
                    title: monthYear,
                    subtitle: "",
                    type: .year,
                    data: monthYear
                ))
            }
        }
        
        // Also search full years for broader results
        for year in dataManager.yearsList {
            if year.lowercased().contains(lowercaseQuery) {
                let hasMonthResults = results.contains { result in
                    if let resultData = result.data as? String {
                        return resultData.contains(year.suffix(2))
                    }
                    return false
                }
                
                if !hasMonthResults {
                    results.append(SearchResult(
                        id: "year_\(year)",
                        title: year,
                        subtitle: "Entire year",
                        type: .year,
                        data: year
                    ))
                }
            }
        }
        
        // Search albums
        for folder in dataManager.folders {
            let albumTitle = folder.localizedTitle ?? "Unknown Album"
            if albumTitle.lowercased().contains(lowercaseQuery) {
                results.append(SearchResult(
                    id: "album_\(folder.localIdentifier)",
                    title: albumTitle,
                    subtitle: "Album",
                    type: .album,
                    data: folder
                ))
            }
        }
        
        searchResults = results
        withAnimation(.easeInOut(duration: 0.3)) {
            showingSearchResults = !results.isEmpty
        }
    }
    
    private func matchesDateQuery(year: String, query: String) -> Bool {
        // Direct match first
        if year.lowercased().contains(query) {
            return true
        }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Handle season searches FIRST and return immediately
        let seasonMonths: [String: [String]] = [
            "summer": ["Jun", "Jul", "Aug"],
            "winter": ["Dec", "Jan", "Feb"],
            "spring": ["Mar", "Apr", "May"],
            "fall": ["Sep", "Oct", "Nov"],
            "autumn": ["Sep", "Oct", "Nov"]
        ]
        
        for (season, months) in seasonMonths {
            if query.contains(season) {
                // This is a season query - handle it completely here
                let isSeasonMonth = months.contains { monthAbbr in
                    year.hasPrefix(monthAbbr)
                }
                
                // If there's a year in the query, check it matches
                let yearRegex = try? NSRegularExpression(pattern: "20\\d{2}")
                if let match = yearRegex?.firstMatch(in: query, range: NSRange(location: 0, length: query.count)) {
                    let queryYear = String(query[Range(match.range, in: query)!])
                    // Must be BOTH a season month AND the right year
                    return isSeasonMonth && year.contains(String(queryYear.suffix(2)))
                } else {
                    // No year specified, just check if it's a season month
                    return isSeasonMonth
                }
            }
        }
        
        // Handle full month names and abbreviations
        let monthMappings: [String: String] = [
            "january": "Jan", "jan": "Jan",
            "february": "Feb", "feb": "Feb",
            "march": "Mar", "mar": "Mar",
            "april": "Apr", "apr": "Apr",
            "may": "May",
            "june": "Jun", "jun": "Jun",
            "july": "Jul", "jul": "Jul",
            "august": "Aug", "aug": "Aug",
            "september": "Sep", "sep": "Sep", "sept": "Sep",
            "october": "Oct", "oct": "Oct",
            "november": "Nov", "nov": "Nov",
            "december": "Dec", "dec": "Dec"
        ]
        
        // Check for month names in the query
        for (monthInput, monthAbbr) in monthMappings {
            if query.contains(monthInput) {
                if year.hasPrefix(monthAbbr) {
                    // If there's a year in the query, make sure it matches
                    let yearRegex = try? NSRegularExpression(pattern: "20\\d{2}")
                    if let match = yearRegex?.firstMatch(in: query, range: NSRange(location: 0, length: query.count)) {
                        let queryYear = String(query[Range(match.range, in: query)!])
                        return year.contains(String(queryYear.suffix(2)))
                    } else {
                        // No year specified, match any year with this month
                        return true
                    }
                }
            }
        }
        
        // Handle any year from 2000-2099
        let yearRegex = try? NSRegularExpression(pattern: "20\\d{2}")
        if let match = yearRegex?.firstMatch(in: query, range: NSRange(location: 0, length: query.count)) {
            let queryYear = String(query[Range(match.range, in: query)!])
            
            // Check if our formatted year contains this year
            if year.contains(String(queryYear.suffix(2))) {
                return true
            }
        }
        
        // Handle relative dates
        if query.contains("last year") {
            let lastYear = calendar.component(.year, from: now) - 1
            return year.contains(String(lastYear).suffix(2))
        }
        
        if query.contains("this year") {
            let thisYear = calendar.component(.year, from: now)
            return year.contains(String(thisYear).suffix(2))
        }
        
        return false
    }
    
    private func selectSearchResult(_ result: SearchResult) {
        // Hide search
        withAnimation(.easeInOut(duration: 0.3)) {
            isSearching = false
            showingSearchResults = false
            searchText = ""
            searchResults = []
        }
        
        // Handle the selection based on type
        switch result.type {
        case .year:
            if let year = result.data as? String {
                // Expand years section and jump to that year
                withAnimation(.easeInOut(duration: 0.5)) {
                    isYearsSectionExpanded = true
                }
                
                // Small delay to allow expansion, then trigger the year selection
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    fetchAssets(forYear: year)
                }
            }
            
        case .album:
            if let folder = result.data as? PHAssetCollection {
                // Expand albums section and jump to that album
                withAnimation(.easeInOut(duration: 0.5)) {
                    isAlbumsSectionExpanded = true
                }
                
                // Small delay to allow expansion, then trigger the album selection
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    fetchAssets(for: folder)
                }
            }
        }
    }
    
    private func getSearchSuggestions() -> [String] {
        var suggestions: [String] = []
        
        let currentYear = Calendar.current.component(.year, from: Date())
        suggestions.append("\(currentYear)")
        suggestions.append("\(currentYear - 1)")
        
        suggestions.append("Summer 2024")
        suggestions.append("Winter 2023")
        
        if let recentYear = dataManager.yearsList.first {
            suggestions.append(recentYear)
        }
        
        if let firstAlbum = dataManager.folders.first?.localizedTitle {
            suggestions.append(firstAlbum)
        }
        
        return Array(suggestions.prefix(6))
    }
    
    private func getSearchExamples() -> [String] {
        return [
            "May 2019",
            "Summer 2024",
            "Winter 2023",
            "2022",
            "Last year"
        ]
    }
    
    private func getQuickActions() -> [QuickAction] {
        let currentYear = Calendar.current.component(.year, from: Date())
        let lastYear = currentYear - 1
        
        return [
            QuickAction(
                title: "This Year",
                subtitle: "\(currentYear)",
                icon: "calendar.circle",
                query: "\(currentYear)",
                gradientColors: [Color.green, Color.blue]
            ),
            QuickAction(
                title: "Last Year",
                subtitle: "\(lastYear)",
                icon: "clock.arrow.circlepath",
                query: "\(lastYear)",
                gradientColors: [Color.orange, Color.red]
            )
        ]
    }
    
    // MARK: - Helper Functions
    private func getSubtitleText(for index: Int) -> String {
        switch index {
        case 0: return "Latest photos and videos"
        case 1: return "Screen captures"
        case 2: return "Loved memories"
        default: return ""
        }
    }
    
    private func gradientColors(for index: Int) -> [Color] {
        switch index {
        case 0: return [Color.green.opacity(0.7), Color.blue.opacity(0.7)]
        case 1: return [Color.purple.opacity(0.7), Color.blue.opacity(0.7)]
        case 2: return [Color.pink.opacity(0.7), Color.red.opacity(0.7)]
        default: return [Color.gray.opacity(0.7), Color.gray.opacity(0.7)]
        }
    }
    
    private func destinationView(for index: Int) -> some View {
        switch index {
        case 0: return AnyView(RecentsView())
        case 1: return AnyView(ScreenshotsView())
        case 2: return AnyView(FavoritesView())
        default: return AnyView(Text("Unknown View"))
        }
    }
    
    // MARK: - Asset fetching functions (keep these - they're still needed)
    private func fetchAssets(for collection: PHAssetCollection) {
        areFolderAssetsReady = false
        isFolderSelected = true
        
        Task {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions)
            
            var tempAssets: [PHAsset] = []
            tempAssets.reserveCapacity(assets.count)
            
            let totalAssets = assets.count
            
            if totalAssets == 0 {
                await MainActor.run {
                    self.selectedFolderAssets = []
                    self.areFolderAssetsReady = true
                }
                return
            }
            
            let batchSize = max(1, min(500, totalAssets))
            
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
            
            if isCancelled {
                return
            }
            
            await MainActor.run {
                self.selectedFolderAssets = []
                self.selectedFolderAssets = tempAssets
                self.areFolderAssetsReady = true
            }
        }
    }
    
    private func fetchAssets(forYear year: String) {
        areYearAssetsReady = false
        isYearSelected = true
        
        Task {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            let assets = PHAsset.fetchAssets(with: fetchOptions)
            
            var tempAssets: [PHAsset] = []
            let calendar = Calendar.current
            
            // Determine if this is a full year (e.g., "2021") or month-year (e.g., "Jan '21")
            let isFullYear = year.count == 4 && Int(year) != nil
            
            let totalAssets = assets.count
            
            if totalAssets == 0 {
                await MainActor.run {
                    self.selectedYearAssets = []
                    self.areYearAssetsReady = true
                }
                return
            }
            
            let batchSize = max(1, min(500, totalAssets))
            
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
                            
                            if isFullYear {
                                // Full year matching (e.g., "2021")
                                let assetYear = calendar.component(.year, from: creationDate)
                                if String(assetYear) == year {
                                    tempAssets.append(asset)
                                }
                            } else {
                                // Month-year matching (e.g., "Jan '21")
                                let dateFormatter = DateFormatter()
                                dateFormatter.dateFormat = "MMM ''yy"
                                let formattedDate = dateFormatter.string(from: creationDate)
                                if formattedDate == year {
                                    tempAssets.append(asset)
                                }
                            }
                        }
                    }
                }
            }
            
            if isCancelled {
                return
            }
            
            await MainActor.run {
                self.selectedYearAssets = []
                self.selectedYearAssets = tempAssets
                self.areYearAssetsReady = true
            }
        }
    }
    
    private func createFolderFilterOptions() -> PHFetchOptions {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        // Use identifiers, not PHAsset objects, in the predicate
        let selectedIds = selectedFolderAssets.map { $0.localIdentifier }
        let swipedIds = Array(SwipedMediaManager.shared.getSwipedMediaIdentifiers())
        
        if swipedIds.isEmpty {
            fetchOptions.predicate = NSPredicate(format: "localIdentifier IN %@", selectedIds)
        } else {
            fetchOptions.predicate = NSPredicate(
                format: "localIdentifier IN %@ AND NOT (localIdentifier IN %@)",
                selectedIds, swipedIds
            )
        }
        
        return fetchOptions
    }

    
    private func createYearFilterOptions() -> PHFetchOptions {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        // Use identifiers, not PHAsset objects, in the predicate
        let selectedIds = selectedYearAssets.map { $0.localIdentifier }
        let swipedIds = Array(SwipedMediaManager.shared.getSwipedMediaIdentifiers())
        
        if swipedIds.isEmpty {
            fetchOptions.predicate = NSPredicate(format: "localIdentifier IN %@", selectedIds)
        } else {
            fetchOptions.predicate = NSPredicate(
                format: "localIdentifier IN %@ AND NOT (localIdentifier IN %@)",
                selectedIds, swipedIds
            )
        }
        
        return fetchOptions
    }
}


// MARK: - Search UI Models
struct SearchCapability {
    let title: String
    let examples: String
    let icon: String
    let color: Color
}

struct QuickAction {
    let title: String
    let subtitle: String
    let icon: String
    let query: String
    let gradientColors: [Color]
}

struct BrowseCategory {
    let title: String
    let icon: String
    let color: Color
}

// MARK: - Custom Button Styles
struct SearchSuggestionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct QuickActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SearchResultButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Bouncing Logo
private struct BouncingLogo: View {
    var size: CGFloat = 100
    var amplitude: CGFloat = 10       // vertical travel (pts)
    var period: Double = 0.9          // seconds per full cycle

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let y = sin((2 * .pi / period) * t) * amplitude

            Image("orca7")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .offset(y: y)
        }
    }
}

// MARK: - Loading View with Bouncing Logo
struct LoadingView: View {
    var message: String
    var onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 60) {
                Spacer()
                
                // Bouncing logo in the center
                BouncingLogo(size: 120, amplitude: 15, period: 1.0)
                
                Spacer()
                
                // Subtle cancel button at the bottom
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.custom(AppFont.regular, size: 16))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.05))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        )
                }
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Identifiable Int Wrapper
struct IdentifiableInt: Identifiable {
    let id = UUID()
    let value: Int
}
