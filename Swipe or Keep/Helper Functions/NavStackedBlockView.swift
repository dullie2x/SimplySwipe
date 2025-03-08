import SwiftUI
import Photos
import AVKit

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
            .onAppear {
                fetchFolders() // Fetch albums
                fetchYears() // Fetch years dynamically
            }
        }
        .fullScreenCover(item: $selectedIndex) { item in
            destinationView(for: item.value)
        }
        .fullScreenCover(isPresented: $isFolderSelected) {
            FilteredSwipeStack(filterOptions: createFolderFilterOptions())
        }
        .fullScreenCover(isPresented: $isYearSelected) {
            FilteredSwipeStack(filterOptions: createYearFilterOptions())
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
    }

    /// **Expandable Block for "Years" and "Albums"**
    private func expandableBlock(index: Int) -> some View {
        VStack {
            Button(action: { toggleSection(index) }) {
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
                        .font(.largeTitle.weight(.bold))
                        .padding(.leading, 15)
                    Spacer()
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
            if index == 3 { // ✅ Years Section
                if yearsList.isEmpty {
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
            } else if index == 4 { // ✅ Albums Section (Folders)
                if folders.isEmpty {
                    Text("No Albums Found")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    ForEach(folders, id: \.localIdentifier) { folder in
                        Button(action: {
                            fetchAssets(for: folder) // ✅ Fetch assets for selected folder
                        }) {
                            albumBlock(title: folder.localizedTitle ?? "Unknown Album")
                        }
                    }
                }
            }
        }
    }
}
extension NavStackedBlocksView {
    /// **Fetch photos for the selected folder**
    private func fetchAssets(for collection: PHAssetCollection) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)] // Sort by newest first

        let assets = PHAsset.fetchAssets(in: collection, options: fetchOptions) // ✅ Fetch only folder-specific assets

        var tempAssets: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            tempAssets.append(asset)
        }

        DispatchQueue.main.async {
            self.selectedFolderAssets = tempAssets // ✅ Store assets for the selected folder
            self.isFolderSelected = true // ✅ Open `FilteredSwipeStack`
        }
    }

    /// **Fetch photos for the selected year**
    private func fetchAssets(forYear year: String) {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var tempAssets: [PHAsset] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM ''yy"

        assets.enumerateObjects { asset, _, _ in
            if let creationDate = asset.creationDate {
                let formattedDate = dateFormatter.string(from: creationDate)
                if formattedDate == year {
                    tempAssets.append(asset)
                }
            }
        }

        DispatchQueue.main.async {
            self.selectedYearAssets = tempAssets
            self.isYearSelected = true // ✅ Open `FilteredSwipeStack` for years
        }
    }

    /// **Generate filter options for selected folder**
    private func createFolderFilterOptions() -> PHFetchOptions {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        // ✅ Only fetch assets from the selected folder
        fetchOptions.predicate = NSPredicate(format: "SELF IN %@", selectedFolderAssets)
        return fetchOptions
    }

    /// **Generate filter options for selected year**
    private func createYearFilterOptions() -> PHFetchOptions {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        // ✅ Only fetch assets from the selected year
        fetchOptions.predicate = NSPredicate(format: "SELF IN %@", selectedYearAssets)
        return fetchOptions
    }

    /// **🌟 Year Block (Same UI as Main Blocks)**
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
                        .font(.largeTitle.weight(.bold))
                        .padding(.leading, 15)
                    Spacer()
                }
            )
            .padding(.top, 2)
    }

    /// **🌟 Album Block (Same UI as Main Blocks)**
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
                        .font(.largeTitle.weight(.bold))
                        .padding(.leading, 15)
                    Spacer()
                }
            )
            .padding(.top, 2)
    }

    /// **✅ Gradient Colors Function**
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

    /// **✅ Destination View**
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
    private func fetchFolders() {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                print("Photo access denied")
                return
            }

            let allFolders = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            var tempFolders: [PHAssetCollection] = [] // ✅ Store the full `PHAssetCollection`

            allFolders.enumerateObjects { collection, _, _ in
                if PHAsset.fetchAssets(in: collection, options: nil).count > 0 {
                    tempFolders.append(collection) // ✅ Store the collection
                }
            }

            DispatchQueue.main.async {
                self.folders = tempFolders // ✅ Now stores PHAssetCollection instead of name/ID tuples
            }
        }
    }

    /// **Fetch Available Years from Photos (Sorted & Unique)**
    private func fetchYears() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM ''yy" // ✅ Formats like "Jan '25"

        var uniqueDates: Set<String> = [] // ✅ Prevents duplicate months
        var sortedDates: [(year: Int, month: Int, formatted: String)] = []

        assets.enumerateObjects { asset, _, _ in
            if let creationDate = asset.creationDate {
                let formattedDate = dateFormatter.string(from: creationDate)

                let calendar = Calendar.current
                let components = calendar.dateComponents([.year, .month], from: creationDate)

                if let year = components.year, let month = components.month {
                    if !uniqueDates.contains(formattedDate) { // ✅ Avoid duplicate months
                        uniqueDates.insert(formattedDate)
                        sortedDates.append((year, month, formattedDate))
                    }
                }
            }
        }

        // ✅ Sort by Year (Descending), then by Month (Descending)
        sortedDates.sort {
            if $0.year == $1.year {
                return $0.month > $1.month
            }
            return $0.year > $1.year
        }

        DispatchQueue.main.async {
            self.yearsList = sortedDates.map { $0.formatted }
        }
    }
}

/// **Wrapper for Int to Conform to Identifiable**
struct IdentifiableInt: Identifiable {
    let id = UUID()
    let value: Int
}

#Preview {
    NavStackedBlocksView()
}
