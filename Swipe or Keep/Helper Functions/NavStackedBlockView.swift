import SwiftUI

struct NavStackedBlocksView: View {
    var blockTitles: [String]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 5) {
                Spacer()
                    .frame(height: 60) // Adjust the height for top spacing

                ForEach(0..<blockTitles.count, id: \.self) { index in
                    NavigationLink(
                        destination: destinationView(for: index),
                        label: {
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
                                    }
                                )
                        }
                    )
                }
            }
            .padding(.horizontal, 5)
        }
        .background(Color(.black))
    }

    // Provide the destination view based on the selected index
    func destinationView(for index: Int) -> some View {
        switch index {
        case 0:
            return AnyView(RecentsView()) // Replace with your actual view
        case 1:
            return AnyView(YearsView())
        case 2:
            return AnyView(ScreenshotsView())
        case 3:
            return AnyView(FoldersView())
        case 4:
            return AnyView(FavoritesView())
        default:
            return AnyView(Text("Unknown View"))
        }
    }

    // Function to provide gradient colors for each block
    func gradientColors(for index: Int) -> [Color] {
        let baseColors: [Color] = [
            Color.green.opacity(0.7),
            Color.blue.opacity(0.7)
        ]
        let firstColor = baseColors[index % baseColors.count]
        let secondColor = baseColors[(index + 1) % baseColors.count]
        return [firstColor, secondColor]
    }
}

#Preview {
    NavStackedBlocksView(blockTitles: ["Recents", "Year", "Screenshots", "Folders", "Favorites"])
}
