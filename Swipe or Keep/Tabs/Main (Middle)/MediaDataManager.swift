import SwiftUI
import Photos

// MARK: - Shared Data Manager
@MainActor
class MediaDataManager: ObservableObject {
    static let shared = MediaDataManager()
    
    // Published properties that views can observe
    @Published var isDataLoaded = false
    @Published var folders: [PHAssetCollection] = []
    @Published var yearsList: [String] = []
    @Published var monthYearsList: [String] = []
    @Published var sectionPreviewImages: [Int: [UIImage]] = [:]
    @Published var yearPreviewImages: [String: [UIImage]] = [:]
    @Published var albumPreviewImages: [String: [UIImage]] = [:]
    
    // Progress tracking
    @Published var categoryProgress: [Int: Double] = [:]
    @Published var yearProgress: [String: Double] = [:]
    @Published var albumProgress: [String: Double] = [:]
    
    private init() {}
    
    // MARK: - Main Loading Function (called from splash screen)
    func loadAllData() async {
        print("📱 Starting to load all media data...")
        
        // Load data in parallel for better performance
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.fetchYears()
            }
            group.addTask {
                await self.fetchFolders()
            }
            group.addTask {
                await self.loadSectionPreviewImages()
            }
        }
        
        // Now load preview images (these depend on years/folders being loaded)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.loadYearPreviewImages()
            }
            group.addTask {
                await self.loadAlbumPreviewImages()
            }
            group.addTask {
                await self.startProgressCalculation()
            }
        }
        
        isDataLoaded = true
        print("✅ All media data loaded successfully!")
    }
    
    // MARK: - Data Loading Functions (moved from NavStackedBlocksView)
    private func fetchYears() async {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let assets = PHAsset.fetchAssets(with: fetchOptions)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM ''yy" // Keep this for search functionality
        
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy" // For display

        var uniqueMonthYears: Set<String> = [] // Keep month-year data for search
        var uniqueYears: Set<String> = [] // Track unique years for display
        var sortedMonthYears: [(year: Int, month: Int, formatted: String)] = [] // Keep for search
        var sortedYears: [(year: Int, yearString: String)] = [] // For year display

        let totalAssets = assets.count
        
        if totalAssets == 0 {
            self.yearsList = []
            self.monthYearsList = []
            return
        }
        
        let batchSize = max(1, min(500, totalAssets))
        
        for batchStart in stride(from: 0, to: totalAssets, by: batchSize) {
            autoreleasepool {
                let batchEnd = min(batchStart + batchSize, totalAssets)
                for i in batchStart..<batchEnd {
                    let asset = assets.object(at: i)
                    if let creationDate = asset.creationDate {
                        let monthYearFormatted = dateFormatter.string(from: creationDate)
                        let yearFormatted = yearFormatter.string(from: creationDate)

                        let calendar = Calendar.current
                        let components = calendar.dateComponents([.year, .month], from: creationDate)

                        if let year = components.year, let month = components.month {
                            // Keep month-year data for search functionality
                            if !uniqueMonthYears.contains(monthYearFormatted) {
                                uniqueMonthYears.insert(monthYearFormatted)
                                sortedMonthYears.append((year, month, monthYearFormatted))
                            }
                            
                            // Track unique years for display
                            if !uniqueYears.contains(yearFormatted) {
                                uniqueYears.insert(yearFormatted)
                                sortedYears.append((year, yearFormatted))
                            }
                        }
                    }
                }
            }
        }

        // Sort month-years for search functionality
        sortedMonthYears.sort {
            if $0.year == $1.year {
                return $0.month > $1.month
            }
            return $0.year > $1.year
        }
        
        // Sort years for display (most recent first)
        sortedYears.sort { $0.year > $1.year }

        // Store month-year data for search
        self.monthYearsList = sortedMonthYears.map { $0.formatted }
        
        // Store year data for display
        self.yearsList = sortedYears.map { $0.yearString }
        
        print("📅 Loaded \(yearsList.count) years and \(monthYearsList.count) month-years")
    }
    
    private func fetchFolders() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized else {
            print("Photo access denied")
            return
        }

        let allFolders = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var tempFolders: [PHAssetCollection] = []
        tempFolders.reserveCapacity(allFolders.count)

        for i in 0..<allFolders.count {
            autoreleasepool {
                let collection = allFolders.object(at: i)
                if PHAsset.fetchAssets(in: collection, options: nil).count > 0 {
                    tempFolders.append(collection)
                }
            }
        }

        self.folders = tempFolders
        print("📁 Loaded \(folders.count) albums")
    }
    
    private func loadSectionPreviewImages() async {
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.resizeMode = .fast
        
        for index in 0..<3 {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 4
            
            switch index {
            case 0:
                break
            case 1:
                fetchOptions.predicate = NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            case 2:
                fetchOptions.predicate = NSPredicate(format: "isFavorite == YES")
            default:
                continue
            }
            
            let assets = PHAsset.fetchAssets(with: fetchOptions)
            var images: [UIImage] = []
            
            for i in 0..<min(4, assets.count) {
                let asset = assets.object(at: i)
                
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    var hasResumed = false
                    imageManager.requestImage(
                        for: asset,
                        targetSize: CGSize(width: 200, height: 200), // Smaller for better performance
                        contentMode: .aspectFill,
                        options: requestOptions
                    ) { image, info in
                        guard !hasResumed else { return }
                        
                        if let info = info,
                           let isDegraded = info[PHImageResultIsDegradedKey] as? Bool,
                           isDegraded {
                            return
                        }
                        
                        hasResumed = true
                        if let image = image {
                            images.append(image)
                        }
                        continuation.resume()
                    }
                }
            }
            
            self.sectionPreviewImages[index] = images
        }
        
        print("🖼️ Loaded section preview images")
    }
    
    private func loadYearPreviewImages() async {
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.resizeMode = .fast
        
        for year in yearsList {
            // Get ALL assets, then filter by year
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            let allAssets = PHAsset.fetchAssets(with: fetchOptions)
            var images: [UIImage] = []
            let calendar = Calendar.current
            
            // Find assets that match this specific year
            var matchingAssets: [PHAsset] = []
            
            for i in 0..<allAssets.count {
                let asset = allAssets.object(at: i)
                if let creationDate = asset.creationDate {
                    let assetYear = calendar.component(.year, from: creationDate)
                    if String(assetYear) == year {
                        matchingAssets.append(asset)
                        if matchingAssets.count >= 4 { // Only need 4 for preview
                            break
                        }
                    }
                }
            }
            
            // Load images for the matching assets
            for asset in matchingAssets.prefix(4) {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    var hasResumed = false
                    imageManager.requestImage(
                        for: asset,
                        targetSize: CGSize(width: 200, height: 200), // Smaller for better performance
                        contentMode: .aspectFill,
                        options: requestOptions
                    ) { image, info in
                        guard !hasResumed else { return }
                        
                        if let info = info,
                           let isDegraded = info[PHImageResultIsDegradedKey] as? Bool,
                           isDegraded {
                            return
                        }
                        
                        hasResumed = true
                        if let image = image {
                            images.append(image)
                        }
                        continuation.resume()
                    }
                }
            }
            
            self.yearPreviewImages[year] = images
        }
        
        print("📸 Loaded year preview images for \(yearsList.count) years")
    }
    
    private func loadAlbumPreviewImages() async {
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.resizeMode = .fast
        
        for folder in folders {
            let albumTitle = folder.localizedTitle ?? "Unknown Album"
            
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 4
            
            let assets = PHAsset.fetchAssets(in: folder, options: fetchOptions)
            var images: [UIImage] = []
            
            for i in 0..<min(4, assets.count) {
                let asset = assets.object(at: i)
                
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    var hasResumed = false
                    imageManager.requestImage(
                        for: asset,
                        targetSize: CGSize(width: 200, height: 200), // Smaller for better performance
                        contentMode: .aspectFill,
                        options: requestOptions
                    ) { image, info in
                        guard !hasResumed else { return }
                        
                        if let info = info,
                           let isDegraded = info[PHImageResultIsDegradedKey] as? Bool,
                           isDegraded {
                            return
                        }
                        
                        hasResumed = true
                        if let image = image {
                            images.append(image)
                        }
                        continuation.resume()
                    }
                }
            }
            
            self.albumPreviewImages[albumTitle] = images
        }
        
        print("🎨 Loaded album preview images for \(folders.count) albums")
    }
    
    private func startProgressCalculation() async {
        if SwipedMediaManager.shared.swipeCount == 0 {
            categoryProgress = [:]
            yearProgress = [:]
            albumProgress = [:]
            return
        }
        
        let categoryResults = await ProgressManager.shared.getCategoryProgress()
        let yearResults = await ProgressManager.shared.getYearProgress(for: yearsList)
        let albumResults = await ProgressManager.shared.getAlbumProgress(for: folders)
        
        self.categoryProgress = categoryResults
        self.yearProgress = yearResults
        self.albumProgress = albumResults
        
        print("📊 Loaded progress data")
    }
}
