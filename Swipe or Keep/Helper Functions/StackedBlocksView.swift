import SwiftUI

struct StackedBlocksView: View {
    var blockTitles: [String] // Titles for blocks
    var actionHandler: ((Int) -> Void)? // Optional action handler

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 5) {
                Spacer()
                    .frame(height: 60) // Adjust the height for top spacing

                ForEach(0..<blockTitles.count, id: \.self) { index in
                    Button(action: {
                        actionHandler?(index) // Trigger the provided action
                    }) {
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
                                        .font(.largeTitle.weight(.bold)) // LargeTitle with bold weight
                                        .padding(.leading, 15) // Align text to the left
                                    Spacer() // Push text to the left
                                }
                            )
                    }
                }
            }
            .padding(.horizontal, 5)
        }
        .background(Color(.black))
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
    StackedBlocksView(blockTitles: ["Recents", "Favorites", "Screenshots"], actionHandler: { index in
        print("Block \(index) clicked")
    })
}
