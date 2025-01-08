import SwiftUI
import Photos

struct YearsView: View {
    @State private var years: [String] = []
    @State private var currentYearAssets: [PHAsset] = [] // Dynamically fetched assets for the selected year
    @State private var selectedYear: String? = nil // Selected year for navigation
    @State private var selectedMonthFilter: PHFetchOptions? = nil // Filter for the selected month
    @Environment(\.presentationMode) var presentationMode // To handle navigation

    var body: some View {
        VStack(spacing: 10) { // Reduced spacing between back button and content
            // Custom Back Button
            HStack {
                Button(action: {
                    presentationMode.wrappedValue.dismiss() // Navigate back
                }) {
                    Image(systemName: "arrow.left.circle") // Back arrow inside a circle
                        .resizable()
                        .frame(width: 30, height: 30) // Adjust the size of the icon
                        .foregroundColor(.white) // White color for the icon
                }
                .padding(.leading, 15) // Add some padding to the left
                .padding(.top, 10) // Add top padding for alignment
                Spacer()
            }

            if years.isEmpty {
                ProgressView("Please wait...")
                    .onAppear(perform: fetchYears)
            } else {
                ZStack {
                    StackedBlocksView(
                        blockTitles: years,
                        actionHandler: { index in
                            selectedYear = years[index]
                        }
                    )
                    .background(Color.black)

                    NavigationLink(
                        destination: selectedYear.flatMap { year in
                            MonthsView(year: year, assets: currentYearAssets) { monthFilter in
                                selectedMonthFilter = monthFilter
                            }
                        },
                        tag: selectedYear ?? "",
                        selection: $selectedYear
                    ) {
                        EmptyView() // Transparent navigation trigger
                    }
                    .onAppear {
                        if let year = selectedYear {
                            fetchAssetsForYear(year: year) { assets in
                                self.currentYearAssets = assets
                            }
                        }
                    }

                    NavigationLink(
                        destination: selectedMonthFilter.flatMap {
                            FilteredSwipeStack(filterOptions: $0)
                        },
                        isActive: Binding(
                            get: { selectedMonthFilter != nil },
                            set: { if !$0 { selectedMonthFilter = nil } }
                        )
                    ) {
                        EmptyView() // Transparent navigation trigger
                    }
                }
            }
        }
        .background(Color.black.ignoresSafeArea()) // Black background for the entire view
        .navigationBarHidden(true) // Hide the default navigation bar
    }

    func fetchYears() {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                print("Photo access denied")
                return
            }

            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let allAssets = PHAsset.fetchAssets(with: fetchOptions)
            var tempYearsSet: Set<String> = []

            allAssets.enumerateObjects { asset, _, _ in
                if let creationDate = asset.creationDate {
                    let year = Calendar.current.component(.year, from: creationDate)
                    tempYearsSet.insert("\(year)")
                }
            }

            DispatchQueue.main.async {
                self.years = Array(tempYearsSet).sorted(by: >) // Sort years in descending order
            }
        }
    }

    func fetchAssetsForYear(year: String, completion: @escaping ([PHAsset]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

            let calendar = Calendar.current
            let startDate = calendar.date(from: DateComponents(year: Int(year), month: 1, day: 1))!
            let endDate = calendar.date(from: DateComponents(year: Int(year)! + 1, month: 1, day: 1))!

            fetchOptions.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", startDate as NSDate, endDate as NSDate)

            let results = PHAsset.fetchAssets(with: fetchOptions)
            var assets: [PHAsset] = []
            results.enumerateObjects { asset, _, _ in
                assets.append(asset)
            }

            DispatchQueue.main.async {
                completion(assets)
            }
        }
    }
}



struct MonthsView: View {
    let year: String
    let assets: [PHAsset]
    let onMonthSelected: (PHFetchOptions) -> Void
    @State private var months: [String] = []
    @Environment(\.presentationMode) var presentationMode // To handle navigation

    var body: some View {
        VStack(spacing: 10) { // Reduced spacing between back button and content
            // Custom Back Button
            HStack {
                Button(action: {
                    presentationMode.wrappedValue.dismiss() // Navigate back
                }) {
                    Image(systemName: "arrow.left.circle") // Back arrow inside a circle
                        .resizable()
                        .frame(width: 30, height: 30) // Adjust the size of the icon
                        .foregroundColor(.white) // White color for the icon
                }
                .padding(.leading, 15) // Add some padding to the left
                .padding(.top, 10) // Add top padding for alignment
                Spacer()
            }

            if months.isEmpty {
                ProgressView("Please Wait...")
                    .onAppear(perform: fetchMonths)
            } else {
                StackedBlocksView(
                    blockTitles: months,
                    actionHandler: { index in
                        let selectedMonth = months[index]
                        if let monthFilter = createFilter(forMonth: selectedMonth) {
                            onMonthSelected(monthFilter)
                        }
                    }
                )
                .background(Color.black)
            }
        }
        .background(Color.black.ignoresSafeArea()) // Black background for the entire view
        .navigationBarHidden(true) // Hide the default navigation bar
    }

    func fetchMonths() {
        var tempMonthsMap: [Int: String] = [:]

        for asset in assets {
            if let creationDate = asset.creationDate {
                let month = Calendar.current.component(.month, from: creationDate)
                let monthName = DateFormatter().monthSymbols[month - 1]

                if tempMonthsMap[month] == nil {
                    tempMonthsMap[month] = monthName
                }
            }
        }

        DispatchQueue.main.async {
            self.months = tempMonthsMap.keys.sorted(by: <).map { index in
                "\(tempMonthsMap[index]!) \(year)"
            }
        }
    }

    func createFilter(forMonth month: String) -> PHFetchOptions? {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM yyyy"
        if let startDate = dateFormatter.date(from: month) {
            var components = Calendar.current.dateComponents([.year, .month], from: startDate)
            components.month = components.month! + 1
            let endDate = Calendar.current.date(from: components) ?? Date()

            fetchOptions.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", startDate as NSDate, endDate as NSDate)
            return fetchOptions
        }
        return nil
    }
}


#Preview {
    NavigationView {
        YearsView()
    }
}
