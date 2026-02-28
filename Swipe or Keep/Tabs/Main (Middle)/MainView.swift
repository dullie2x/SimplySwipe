import SwiftUI

struct MainView: View {
    @StateObject private var quotesManager = QuotesManager.shared
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 0) {
                // Inspirational Quote Header - Top Left
                HStack {
                    Text(quotesManager.currentQuote)
                        .font(.custom(AppFont.regular, size: 18))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7) // Allows text to shrink to 70% if needed
                        .padding(.leading, 16)
                        .padding(.trailing, 16) // Add trailing padding too
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    
                    Spacer()
                }
                
                // Navigation Blocks
                NavStackedBlocksView(
                    blockTitles: ["Recents", "Screenshots", "Favorites", "Years", "Albums"]
                )
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.ignoresSafeArea())
            .tooltip(
                viewName: "Main",
                title: "Browse by Categories",
                message: "Choose how to organize your media",
                position: .center
            )
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EmptyView()
                }
            }
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

#Preview {
    MainView()
}
