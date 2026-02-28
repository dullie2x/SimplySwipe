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
        // Request authorization FIRST — on first launch fetchYears() and
        // loadSectionPreviewImages() would otherwise race ahead with no permission
        // and return empty results before the user taps Allow.
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            isDataLoaded = true
            return
        }

        // Now all three tasks can safely access the photo library in parallel
        await withTaskGroup(of: Void.self) { group in
            // Essential: Category preview images (just 3 categories × 4 images = 12 images)
            group.addTask {
                await self.loadSectionPreviewImages()
            }

            // Essential: List of years and folders (fast metadata only, no images)
            group.addTask {
                await self.fetchYears()
            }
            group.addTask {
                await self.fetchFolders()
            }
        }

        isDataLoaded = true
        
        // BACKGROUND: Load remaining data after app is shown
        Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                // Load year and album preview images in background
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
        }
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
        
    }
    
    private func fetchFolders() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized else {
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
    }
    
    private func loadYearPreviewImages() async {
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.isSynchronous = false
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.resizeMode = .fast

        let calendar = Calendar.current

        for year in yearsList {
            guard let yearInt = Int(year) else { continue }

            // Build a date-ranged predicate instead of scanning the full library
            var startComponents = DateComponents()
            startComponents.year = yearInt
            startComponents.month = 1
            startComponents.day = 1
            startComponents.hour = 0
            startComponents.minute = 0
            startComponents.second = 0

            var endComponents = DateComponents()
            endComponents.year = yearInt + 1
            endComponents.month = 1
            endComponents.day = 1
            endComponents.hour = 0
            endComponents.minute = 0
            endComponents.second = 0

            guard let startDate = calendar.date(from: startComponents),
                  let endDate   = calendar.date(from: endComponents) else { continue }

            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 4
            fetchOptions.predicate = NSPredicate(
                format: "creationDate >= %@ AND creationDate < %@",
                startDate as NSDate,
                endDate   as NSDate
            )

            let assets = PHAsset.fetchAssets(with: fetchOptions)
            var images: [UIImage] = []

            // Load images for the matching assets
            for asset in assets.objects(at: IndexSet(integersIn: 0..<min(4, assets.count))) {
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
    }
}
