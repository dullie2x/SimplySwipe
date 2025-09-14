import SwiftUI

struct MainView: View {
    var body: some View {
        NavigationView {
            VStack {
                // App Name Header
                Text("simply swipe")
                    .font(.custom(AppFont.regular, size: 38))
                    .foregroundColor(.white)
                    .padding(.top, 20)
                    .padding(.bottom, 1)
                
                // Navigation Blocks
                NavStackedBlocksView(
                    blockTitles: ["Recents", "Screenshots", "Favorites", "Years", "Albums"]
                )
                
                Spacer()
            }
            .background(Color.black.ignoresSafeArea())
            .tooltip(
                viewName: "Main",
                title: "Browse by Categories",
                message: "Choose how to organize your media\n• Swipe down to search",
                position: .center
            )
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EmptyView() // Removes the back button
                }
            }
        }
    }
}

// Keep the hex color extension if it's used elsewhere in your app
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
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
