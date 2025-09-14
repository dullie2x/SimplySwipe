//
//  NavStackedBlocksView.swift - Updated with FilterType Integration
//  Media App - Part 1: Header and State
//

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
    
    // UPDATED: Replace asset arrays with FilterType tracking
    @State private var selectedFilterType: FilterType? = nil
//    @State private var isFilteredViewPresented = false
    
    // Search state tracking
    @State private var isYearsSectionExpanded = false
    @State private var isAlbumsSectionExpanded = false
    @State private var isSearching = false
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var showingSearchResults = false
    
    // Use shared data manager
    @StateObject private var dataManager = MediaDataManager.shared
    // Part 2: Main Body and Navigation
    
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
    
    // Part 3: Search Bar and Results Views
    
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
            
            // Search suggestions (same as before)
            if searchText.isEmpty {
                searchSuggestionsView()
            }
        }
    }
    
    // MARK: - Search Suggestions View
    private func searchSuggestionsView() -> some View {
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
            
            // Examples and Quick Actions (same implementation as before)
            searchExamplesSection()
            quickActionsSection()
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
    
    // Part 4: Search Implementation and Helper Views
    
    // MARK: - Search Examples Section
    private func searchExamplesSection() -> some View {
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
    }
    
    // MARK: - Quick Actions Section
    private func quickActionsSection() -> some View {
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
                            
                            Text(action.title)
                                .foregroundColor(.white)
                                .font(.custom(AppFont.regular, size: 14))
                                .lineLimit(1)
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
    
    // Part 5: Content Views and Navigation Logic
    
    // MARK: - Search Results View
    private func searchResultsView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")")
                    .foregroundColor(.white.opacity(0.6))
                    .font(.custom(AppFont.regular, size: 14))
                Spacer()
            }
            .padding(.horizontal, 4)
            
            if searchResults.isEmpty && !searchText.isEmpty {
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
            Image(systemName: result.type == .year ? "calendar" : "rectangle.stack")
                .foregroundColor(.white.opacity(0.7))
                .font(.system(size: 18))
                .frame(width: 24)
            
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
    }
    
    // MARK: - Main Categories View
    private func mainCategoriesView() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(0..<3, id: \.self) { index in
                Button(action: {
                    print("DEBUG: Category \(index) tapped")
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
                        print("DEBUG: Year \(year) tapped")
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
                        print("DEBUG: Album \(folder.localizedTitle ?? "Unknown") tapped")
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
    private func selectSearchResult(_ result: SearchResult) {
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
        }
    }
    
    // MARK: - Search Logic
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
    
    // MARK: - Date Query Matching
    private func matchesDateQuery(year: String, query: String) -> Bool {
        // Direct match first
        if year.lowercased().contains(query) {
            return true
        }
        
        let calendar = Calendar.current
        let now = Date()
        
        // Handle season searches
        let seasonMonths: [String: [String]] = [
            "summer": ["Jun", "Jul", "Aug"],
            "winter": ["Dec", "Jan", "Feb"],
            "spring": ["Mar", "Apr", "May"],
            "fall": ["Sep", "Oct", "Nov"],
            "autumn": ["Sep", "Oct", "Nov"]
        ]
        
        for (season, months) in seasonMonths {
            if query.contains(season) {
                let isSeasonMonth = months.contains { monthAbbr in
                    year.hasPrefix(monthAbbr)
                }
                
                let yearRegex = try? NSRegularExpression(pattern: "20\\d{2}")
                if let match = yearRegex?.firstMatch(in: query, range: NSRange(location: 0, length: query.count)) {
                    let queryYear = String(query[Range(match.range, in: query)!])
                    return isSeasonMonth && year.contains(String(queryYear.suffix(2)))
                } else {
                    return isSeasonMonth
                }
            }
        }
        
        // Handle month names
        let monthMappings: [String: String] = [
            "january": "Jan", "jan": "Jan", "february": "Feb", "feb": "Feb",
            "march": "Mar", "mar": "Mar", "april": "Apr", "apr": "Apr",
            "may": "May", "june": "Jun", "jun": "Jun", "july": "Jul", "jul": "Jul",
            "august": "Aug", "aug": "Aug", "september": "Sep", "sep": "Sep", "sept": "Sep",
            "october": "Oct", "oct": "Oct", "november": "Nov", "nov": "Nov",
            "december": "Dec", "dec": "Dec"
        ]
        
        for (monthInput, monthAbbr) in monthMappings {
            if query.contains(monthInput) && year.hasPrefix(monthAbbr) {
                let yearRegex = try? NSRegularExpression(pattern: "20\\d{2}")
                if let match = yearRegex?.firstMatch(in: query, range: NSRange(location: 0, length: query.count)) {
                    let queryYear = String(query[Range(match.range, in: query)!])
                    return year.contains(String(queryYear.suffix(2)))
                } else {
                    return true
                }
            }
        }
        
        // Handle year patterns
        let yearRegex = try? NSRegularExpression(pattern: "20\\d{2}")
        if let match = yearRegex?.firstMatch(in: query, range: NSRange(location: 0, length: query.count)) {
            let queryYear = String(query[Range(match.range, in: query)!])
            return year.contains(String(queryYear.suffix(2)))
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
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.15))
                .frame(height: 200)
                .clipped()
                .overlay(
                    ZStack {
                        if !previewImages.isEmpty {
                            photoPreviewGrid(images: previewImages)
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(LinearGradient(
                                    gradient: Gradient(colors: gradientColors),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .opacity(0.7)
                        }
                        
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
        }
        
        private func appleCategoryBlock(index: Int) -> some View {
            let progress = dataManager.categoryProgress[index] ?? 0
            let done = progress >= 0.999

            return RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.15))
                .frame(height: 200)
                .overlay(
                    ZStack {
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
        }
        
        private func appleYearBlock(title: String) -> some View {
            let progress = dataManager.yearProgress[title] ?? 0
            let done = progress >= 0.999

            return RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.15))
                .aspectRatio(1.3, contentMode: .fit)
                .overlay(
                    ZStack {
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

                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.black.opacity(0.5), Color.clear]),
                                    startPoint: .bottom,
                                    endPoint: .center
                                )
                            )

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
        
        private func appleAlbumBlock(title: String) -> some View {
            let progress = dataManager.albumProgress[title] ?? 0
            let done = progress >= 0.999

            return RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.15))
                .aspectRatio(1.3, contentMode: .fit)
                .overlay(
                    ZStack {
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

                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.black.opacity(0.5), Color.clear]),
                                    startPoint: .bottom,
                                    endPoint: .center
                                )
                            )

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
        
        private func photoPreviewGrid(images: [UIImage]) -> some View {
            GeometryReader { geometry in
                let size = geometry.size
                
                if let firstImage = images.first {
                    Image(uiImage: firstImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .cornerRadius(12)
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
        
        private func getSearchExamples() -> [String] {
            return ["May 2019", "Summer 2024", "Winter 2023", "2022", "Last year"]
        }
        
        private func getQuickActions() -> [QuickAction] {
            let currentYear = Calendar.current.component(.year, from: Date())
            let lastYear = currentYear - 1
            
            return [
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

    // MARK: - Supporting Types and Styles
    struct QuickAction {
        let title: String
        let subtitle: String
        let icon: String
        let query: String
        let gradientColors: [Color]
    }

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

    struct LoadingView: View {
        var message: String
        var onCancel: () -> Void
        
        var body: some View {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                VStack(spacing: 60) {
                    Spacer()
                    BouncingLogo(size: 120, amplitude: 15, period: 1.0)
                    Spacer()
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.custom(AppFont.regular, size: 16))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 20)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.05))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                            )
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private struct BouncingLogo: View {
        var size: CGFloat = 100
        var amplitude: CGFloat = 10
        var period: Double = 0.9

        var body: some View {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let y = sin((2 * .pi / period) * t) * amplitude

                Image("orca8")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .offset(y: y)
            }
        }
    }

    struct IdentifiableInt: Identifiable {
        let id = UUID()
        let value: Int
    }
