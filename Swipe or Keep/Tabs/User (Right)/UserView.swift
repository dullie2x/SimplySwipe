import SwiftUI

struct UserView: View {
    // Example data for your blocks
    private let blockTitles = ["Stats", "Swipes", "Feedback"]

    var body: some View {
        VStack {
            // Header for the UserView
            Text("User Data")
                .font(.largeTitle.weight(.bold))
                .foregroundColor(.white)
                .padding(.top, 20)

            Spacer()
                .frame(height: 10)

            // Embed StackedBlocksView
            StackedBlocksView(blockTitles: blockTitles, actionHandler: { index in
                handleBlockAction(index)
            })
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
    }

    // Handle block actions based on index
    func handleBlockAction(_ index: Int) {
        switch index {
        case 0:
            print("Stats block tapped")
            // Navigate to stats or show stats here
        case 1:
            print("Swipes block tapped")
            // Navigate to swipes or show swipes here
        case 2:
            print("Feedback block tapped")
            // Navigate to feedback or show feedback here
        default:
            print("Unknown block tapped")
        }
    }
}

#Preview {
    UserView()
}
