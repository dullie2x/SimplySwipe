//
//  NavStackedBlocksView.swift - Updated with FilterType Integration
//  Media App - Main navigation blocks view
//

import SwiftUI
import Photos
import AVKit

struct NavStackedBlocksView: View {
    var blockTitles: [String] = ["Recents", "Screenshots", "Favorites", "Years", "Albums"]
    
    @State private var selectedIndex: IdentifiableInt? = nil
    @State private var selectedFilterType: FilterType? = nil
    
    // Search state tracking
    @State fileprivate var isYearsSectionExpanded = false
    @State fileprivate var isAlbumsSectionExpanded = false
    @State var isSearching = false
    @State var searchText = ""
    @State var searchResults: [SearchResult] = []
    @State var showingSearchResults = false
    
    // Use shared data manager
    @StateObject private var dataManager = MediaDataManager.shared
    
    // MARK: - Main Body
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 20) {
                // Search bar (shows when pulling to refresh)
                if isSearching {
                    searchBarView()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Show search results, quick actions, or normal content
                if showingSearchResults {
                    searchResultsView()
                } else if isSearching && searchText.isEmpty {
                    quickActionsView()
                } else if !isSearching {
                    normalContentView()
                }
                
                Spacer().frame(height: 20)
            }
            .padding(.top, 0)
            .padding(.horizontal, 16)
        }
        .background(Color.black)
        .refreshable {
            // Trigger search mode
            withAnimation(.easeInOut(duration: 0.3)) {
                isSearching = true
            }
        }
        // Notify MainTabView to hide/show the tab bar when search mode changes
        .onChange(of: isSearching) { _, newValue in
            NotificationCenter.default.post(
                name: .searchStateChanged,
                object: nil,
                userInfo: ["isSearching": newValue]
            )
        }
        // UPDATED: Single fullScreenCover for categories
        .fullScreenCover(item: $selectedIndex, onDismiss: {
            Task { await refreshProgress() }
        }) { item in
            destinationView(for: item.value)
        }
        
        // UPDATED: Single fullScreenCover for filtered views with FilterType
        .fullScreenCover(item: $selectedFilterType, onDismiss: {
            Task { await refreshProgress() }
        }) { filterType in
            FilteredVertScroll(
                filterOptions: createFilterOptions(for: filterType),
                filterType: filterType
            )
        }
    }
    
    // MARK: - Normal Content View
    private func normalContentView() -> some View {
        VStack(spacing: 20) {
            // Main categories
            mainCategoriesView()
            
            // Years section
            if !dataManager.yearsList.isEmpty {
                if isYearsSectionExpanded {
                    expandedYearsView()
                } else {
                    largeYearsBlock()
                }
            }
            
            // Albums section
            if !dataManager.folders.isEmpty {
                if isAlbumsSectionExpanded {
                    expandedAlbumsView()
                } else {
                    largeAlbumsBlock()
                }
            }
        }
        .padding(.top, 0)
    }
    
    // MARK: - Main Categories View
    private func mainCategoriesView() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(0..<3, id: \.self) { index in
                Button(action: {
                    selectedIndex = IdentifiableInt(value: index)
                }) {
                    appleCategoryBlock(index: index)
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Rectangle())
            }
        }
    }
    
    // Part 6: Filter Type Creation and Navigation
    
    // MARK: - Expanded Years View
    private func expandedYearsView() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Years")
                    .foregroundColor(.white)
                    .font(.custom(AppFont.regular, size: 24))
                Spacer()
                Button(action: {
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
                                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Circle())
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 20) {
                ForEach(dataManager.yearsList, id: \.self) { year in
                    Button(action: {
                        navigateToYear(year)
                    }) {
                        appleYearBlock(title: year)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contentShape(Rectangle())
                }
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Expanded Albums View
    private func expandedAlbumsView() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Albums")
                    .foregroundColor(.white)
                    .font(.custom(AppFont.regular, size: 24))
                Spacer()
                Button(action: {
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
                                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .contentShape(Circle())
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 20) {
                ForEach(dataManager.folders, id: \.localIdentifier) { folder in
                    Button(action: {
                        navigateToAlbum(folder)
                    }) {
                        appleAlbumBlock(title: folder.localizedTitle ?? "Unknown Album")
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contentShape(Rectangle())
                }
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Navigation Functions (UPDATED)
    private func navigateToYear(_ year: String) {
        selectedFilterType = .year(year)          // removed: isFilteredViewPresented = true
    }

    private func navigateToAlbum(_ collection: PHAssetCollection) {
        selectedFilterType = .album(collection)   // removed: isFilteredViewPresented = true
    }

    
    // MARK: - Filter Options Creation (UPDATED)
    private func createFilterOptions(for filterType: FilterType) -> PHFetchOptions {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        let swipedIds = Array(SwipedMediaManager.shared.getSwipedMediaIdentifiers())
        
        switch filterType {
        case .album(let collection):
            // Get all assets in this album
            let albumAssets = PHAsset.fetchAssets(in: collection, options: nil)
            var albumAssetIds: [String] = []
            albumAssets.enumerateObjects { asset, _, _ in
                albumAssetIds.append(asset.localIdentifier)
            }
            
            if swipedIds.isEmpty {
                fetchOptions.predicate = NSPredicate(format: "localIdentifier IN %@", albumAssetIds)
            } else {
                fetchOptions.predicate = NSPredicate(
                    format: "localIdentifier IN %@ AND NOT (localIdentifier IN %@)",
                    albumAssetIds, swipedIds
                )
            }
            
        case .year(let year):
            // Handle both full years and month-year formats
            let isFullYear = year.count == 4 && Int(year) != nil
            
            if isFullYear {
                // Full year: use date range predicate
                guard let yearInt = Int(year) else { return fetchOptions }
                let calendar = Calendar.current
                let startOfYear = calendar.date(from: DateComponents(year: yearInt, month: 1, day: 1))!
                let endOfYear = calendar.date(from: DateComponents(year: yearInt + 1, month: 1, day: 1))!
                
                if swipedIds.isEmpty {
                    fetchOptions.predicate = NSPredicate(
                        format: "creationDate >= %@ AND creationDate < %@",
                        startOfYear as NSDate, endOfYear as NSDate
                    )
                } else {
                    fetchOptions.predicate = NSPredicate(
                        format: "creationDate >= %@ AND creationDate < %@ AND NOT (localIdentifier IN %@)",
                        startOfYear as NSDate, endOfYear as NSDate, swipedIds
                    )
                }
            } else {
                // Month-year format: need to fetch all and filter
                if !swipedIds.isEmpty {
                    fetchOptions.predicate = NSPredicate(format: "NOT (localIdentifier IN %@)", swipedIds)
                }
            }
            
        case .category(let index):
            // Category filtering
            switch index {
            case 0: // Recents
                let calendar = Calendar.current
                let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date())!
                if swipedIds.isEmpty {
                    fetchOptions.predicate = NSPredicate(format: "creationDate > %@", thirtyDaysAgo as NSDate)
                } else {
                    fetchOptions.predicate = NSPredicate(
                        format: "creationDate > %@ AND NOT (localIdentifier IN %@)",
                        thirtyDaysAgo as NSDate, swipedIds
                    )
                }
                
            case 1: // Screenshots
                if swipedIds.isEmpty {
                    fetchOptions.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
                } else {
                    fetchOptions.predicate = NSPredicate(
                        format: "(mediaSubtype & %d) != 0 AND NOT (localIdentifier IN %@)",
                        PHAssetMediaSubtype.photoScreenshot.rawValue, swipedIds
                    )
                }
                
            case 2: // Favorites
                if swipedIds.isEmpty {
                    fetchOptions.predicate = NSPredicate(format: "favorite == YES")
                } else {
                    fetchOptions.predicate = NSPredicate(
                        format: "favorite == YES AND NOT (localIdentifier IN %@)",
                        swipedIds
                    )
                }
                
            default:
                break
            }
        }
        
        return fetchOptions
    }
    
    // Part 7: Search Logic and Helper Functions
    
    // MARK: - Search Result Selection (UPDATED)
    func selectSearchResult(_ result: SearchResult) {
        // Hide search
        withAnimation(.easeInOut(duration: 0.3)) {
            isSearching = false
            showingSearchResults = false
            searchText = ""
            searchResults = []
        }
        
        // Handle the selection based on type using FilterType
        switch result.type {
        case .year:
            if let year = result.data as? String {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isYearsSectionExpanded = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    selectedFilterType = .year(year)
                }
            }

        case .album:
            if let folder = result.data as? PHAssetCollection {
                withAnimation(.easeInOut(duration: 0.5)) {
                    isAlbumsSectionExpanded = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    selectedFilterType = .album(folder)
                }
            }

        case .category(let index):
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                selectedFilterType = .category(index)
            }
        }
    }
    
    // MARK: - Search Logic
    func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            withAnimation(.easeInOut(duration: 0.3)) {
                showingSearchResults = false
            }
            return
        }
        
        var results: [SearchResult] = []
        let lowercaseQuery = query.lowercased()

        // Search categories (Recents, Screenshots, Favorites)
        let categoryDefs: [(Int, String, String)] = [
            (0, "Recents",     "Last 30 days"),
            (1, "Screenshots", "Screen captures"),
            (2, "Favorites",   "Liked photos & videos")
        ]
        for (index, name, subtitle) in categoryDefs {
            if name.lowercased().contains(lowercaseQuery) {
                results.append(SearchResult(
                    id: "category_\(index)",
                    title: name,
                    subtitle: subtitle,
                    type: .category(index),
                    data: index
                ))
            }
        }

        // Search using month-year data for granular results
        for monthYear in dataManager.monthYearsList {
            if matchesDateQuery(monthYear: monthYear, query: lowercaseQuery) {
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
                // Only show the full-year result if there are no individual month results for this year
                let yearSuffix = String(year.suffix(2))
                let hasMonthResults = results.contains { result in
                    if let resultData = result.data as? String {
                        return resultData.hasSuffix(yearSuffix) && resultData.count <= 6
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
    
    // MARK: - Date Query Matching
    // `monthYear` is a string like "Jan 25" from monthYearsList
    private func matchesDateQuery(monthYear: String, query: String) -> Bool {
        // Direct match first (e.g. "jan 25")
        if monthYear.lowercased().contains(query) {
            return true
        }

        let calendar = Calendar.current
        let now = Date()

        // Helper: extract the 2-digit year suffix from a 4-digit year string ("2025" → "25")
        func twoDigit(_ fullYear: Int) -> String { String(fullYear).suffix(2).description }

        // Helper: extract 4-digit year from the query string if present
        let yearRegex = try? NSRegularExpression(pattern: "20\\d{2}")
        func extractQueryYear() -> String? {
            guard let match = yearRegex?.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)) else { return nil }
            return String(query[Range(match.range, in: query)!])
        }

        // Handle season searches
        let seasonMonths: [String: [String]] = [
            "summer": ["Jun", "Jul", "Aug"],
            "winter": ["Dec", "Jan", "Feb"],
            "spring": ["Mar", "Apr", "May"],
            "fall":   ["Sep", "Oct", "Nov"],
            "autumn": ["Sep", "Oct", "Nov"]
        ]
        for (season, months) in seasonMonths {
            if query.contains(season) {
                let isSeasonMonth = months.contains { monthYear.hasPrefix($0) }
                if let qYear = extractQueryYear() {
                    return isSeasonMonth && monthYear.hasSuffix(twoDigit(Int(qYear)!))
                }
                return isSeasonMonth
            }
        }

        // Handle month name searches (e.g. "january", "jan", "august 2025")
        let monthMappings: [String: String] = [
            "january": "Jan", "jan": "Jan", "february": "Feb", "feb": "Feb",
            "march": "Mar", "mar": "Mar", "april": "Apr", "apr": "Apr",
            "may": "May", "june": "Jun", "jun": "Jun", "july": "Jul", "jul": "Jul",
            "august": "Aug", "aug": "Aug", "september": "Sep", "sep": "Sep", "sept": "Sep",
            "october": "Oct", "oct": "Oct", "november": "Nov", "nov": "Nov",
            "december": "Dec", "dec": "Dec"
        ]
        for (monthInput, monthAbbr) in monthMappings {
            if query.contains(monthInput) && monthYear.hasPrefix(monthAbbr) {
                if let qYear = extractQueryYear() {
                    return monthYear.hasSuffix(twoDigit(Int(qYear)!))
                }
                return true  // month matches, no year constraint
            }
        }

        // Handle bare 4-digit year (e.g. "2025")
        if let qYear = extractQueryYear() {
            return monthYear.hasSuffix(twoDigit(Int(qYear)!))
        }

        // Handle relative date keywords
        if query.contains("last month") {
            let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: now)!
            let m = calendar.component(.month, from: lastMonthDate)
            let y = calendar.component(.year, from: lastMonthDate)
            let abbrs = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
            return monthYear == "\(abbrs[m - 1]) \(twoDigit(y))"
        }

        if query.contains("last year") {
            return monthYear.hasSuffix(twoDigit(calendar.component(.year, from: now) - 1))
        }

        if query.contains("this year") {
            return monthYear.hasSuffix(twoDigit(calendar.component(.year, from: now)))
        }

        return false
    }
    
    // Part 8: UI Components, Styling, and Helper Functions

        // MARK: - UI Component Functions
        private func largeYearsBlock() -> some View {
            Button(action: {
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
            .contentShape(Rectangle())
        }
        
        private func largeAlbumsBlock() -> some View {
            Button(action: {
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
            .contentShape(Rectangle())
        }
        
    private func appleLargeSectionBlock(title: String, subtitle: String, gradientColors: [Color], previewImages: [UIImage]) -> some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color.gray.opacity(0.15))
            .frame(height: 200)
            .clipped()
            .overlay(
                ZStack {
                    if !previewImages.isEmpty {
                        photoPreviewGrid(images: previewImages)
                    } else {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: gradientColors),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .opacity(0.7)
                    }
                    
                    RoundedRectangle(cornerRadius: 20)
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
                    
                    VStack {
                        Spacer()
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title)
                                    .foregroundColor(.white)
                                    .font(.custom(AppFont.regular, size: 28))
                            }
                            Spacer()
                            Image(systemName: "chevron.down")
                                .foregroundColor(.white.opacity(0.8))
                                .font(.system(size: 28, weight: .medium))
                                .frame(width: 60, height: 60)
                        }
                        .padding(20)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.25),
                                Color.white.opacity(0.08)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: Color.black.opacity(0.6), radius: 15, x: 0, y: 8)
            .shadow(color: Color.white.opacity(0.1), radius: 2, x: 0, y: -2)
    }

    private func appleCategoryBlock(index: Int) -> some View {
        let progress = dataManager.categoryProgress[index] ?? 0
        let done = progress >= 0.999

        return RoundedRectangle(cornerRadius: 20)
            .fill(Color.gray.opacity(0.15))
            .frame(height: 200)
            .overlay(
                ZStack {
                    if let previewImages = dataManager.sectionPreviewImages[index], !previewImages.isEmpty {
                        photoPreviewGrid(images: previewImages)
                    } else {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: gradientColors(for: index)),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .opacity(0.7)
                    }

                    RoundedRectangle(cornerRadius: 20)
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

                    ZStack {
                        if done {
                            RoundedRectangle(cornerRadius: 20)
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
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.25),
                                Color.white.opacity(0.08)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: Color.black.opacity(0.6), radius: 15, x: 0, y: 8)
            .shadow(color: Color.white.opacity(0.1), radius: 2, x: 0, y: -2)
    }

    private func appleYearBlock(title: String) -> some View {
        let progress = dataManager.yearProgress[title] ?? 0
        let done = progress >= 0.999

        return RoundedRectangle(cornerRadius: 18)
            .fill(Color.gray.opacity(0.15))
            .aspectRatio(1.3, contentMode: .fit)
            .overlay(
                ZStack {
                    if let previewImages = dataManager.yearPreviewImages[title], !previewImages.isEmpty {
                        photoPreviewGrid(images: previewImages)
                    } else {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [Color.red.opacity(0.6), Color.pink.opacity(0.6)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    }

                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.black.opacity(0.5), Color.clear]),
                                startPoint: .bottom,
                                endPoint: .center
                            )
                        )

                    ZStack {
                        if done {
                            RoundedRectangle(cornerRadius: 18)
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
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.25),
                                Color.white.opacity(0.08)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: Color.black.opacity(0.5), radius: 12, x: 0, y: 6)
            .shadow(color: Color.white.opacity(0.1), radius: 2, x: 0, y: -2)
    }

    private func appleAlbumBlock(title: String) -> some View {
        let progress = dataManager.albumProgress[title] ?? 0
        let done = progress >= 0.999

        return RoundedRectangle(cornerRadius: 18)
            .fill(Color.gray.opacity(0.15))
            .aspectRatio(1.3, contentMode: .fit)
            .overlay(
                ZStack {
                    if let previewImages = dataManager.albumPreviewImages[title], !previewImages.isEmpty {
                        photoPreviewGrid(images: previewImages)
                    } else {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [Color.orange.opacity(0.6), Color.yellow.opacity(0.6)]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    }

                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.black.opacity(0.5), Color.clear]),
                                startPoint: .bottom,
                                endPoint: .center
                            )
                        )

                    ZStack {
                        if done {
                            RoundedRectangle(cornerRadius: 18)
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
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.25),
                                Color.white.opacity(0.08)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: Color.black.opacity(0.5), radius: 12, x: 0, y: 6)
            .shadow(color: Color.white.opacity(0.1), radius: 2, x: 0, y: -2)
    }
        
    private func photoPreviewGrid(images: [UIImage]) -> some View {
        GeometryReader { geometry in
            let size = geometry.size
            
            if let firstImage = images.first {
                Image(uiImage: firstImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .cornerRadius(20) // Updated to match the larger blocks
            }
        }
    }
        
        // MARK: - Helper Functions
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
            // Skip the most recent year — it would show the same photos as Recents.
            // Use photos from the previous year (and older) so the block looks distinct.
            let yearsForThumbnail = dataManager.yearsList.count > 1
                ? Array(dataManager.yearsList.dropFirst().prefix(4))
                : Array(dataManager.yearsList.prefix(4))

            var allImages: [UIImage] = []

            for year in yearsForThumbnail {
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
        
        func getSearchExamples() -> [String] {
            return ["May 2019", "Summer 2024", "Winter 2023", "2022", "Last year"]
        }
        
        func getQuickActions() -> [QuickAction] {
            let calendar = Calendar.current
            let now = Date()
            let currentYear = calendar.component(.year, from: now)
            let lastYear = currentYear - 1

            let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: now)!
            let lastMonthNum = calendar.component(.month, from: lastMonthDate)
            let lastMonthYear = calendar.component(.year, from: lastMonthDate)
            let monthNames = ["January","February","March","April","May","June",
                              "July","August","September","October","November","December"]
            let lastMonthName = monthNames[lastMonthNum - 1]
            let lastMonthQuery = "\(lastMonthName) \(lastMonthYear)"
            let lastMonthLabel = "\(["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][lastMonthNum - 1]) \(lastMonthYear)"

            let threeMonthsDate = calendar.date(byAdding: .month, value: -3, to: now)!
            let threeMonthNum = calendar.component(.month, from: threeMonthsDate)
            let threeMonthYear = calendar.component(.year, from: threeMonthsDate)
            let threeMonthName = monthNames[threeMonthNum - 1]
            let threeMonthQuery = "\(threeMonthName) \(threeMonthYear)"

            return [
                QuickAction(
                    title: "Last Month", subtitle: lastMonthLabel, icon: "calendar",
                    query: lastMonthQuery, gradientColors: [Color.blue, Color.purple]
                ),
                QuickAction(
                    title: "3 Months Ago", subtitle: threeMonthQuery, icon: "calendar.badge.clock",
                    query: threeMonthQuery, gradientColors: [Color.purple, Color.pink]
                ),
                QuickAction(
                    title: "This Year", subtitle: "\(currentYear)", icon: "calendar.circle",
                    query: "\(currentYear)", gradientColors: [Color.green, Color.blue]
                ),
                QuickAction(
                    title: "Last Year", subtitle: "\(lastYear)", icon: "clock.arrow.circlepath",
                    query: "\(lastYear)", gradientColors: [Color.orange, Color.red]
                )
            ]
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
            case 0: return AnyView(FilteredVertScroll(filterOptions: createFilterOptions(for: .category(0)), filterType: .category(0)))
            case 1: return AnyView(FilteredVertScroll(filterOptions: createFilterOptions(for: .category(1)), filterType: .category(1)))
            case 2: return AnyView(FilteredVertScroll(filterOptions: createFilterOptions(for: .category(2)), filterType: .category(2)))
            default: return AnyView(Text("Unknown View"))
            }
        }
    }
