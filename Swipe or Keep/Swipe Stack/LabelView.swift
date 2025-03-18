import SwiftUI

struct LabelView: View {
    let text: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(color.opacity(0.9)) // Slightly increased opacity for better contrast
                .shadow(color: color.opacity(0.6), radius: 8, x: 0, y: 4) // Softer shadow for depth

            VStack(spacing: 5) {
                Image(systemName: text == "Keep" ? "hand.thumbsup.fill" : "trash.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)

                Text(text)
                    .font(.system(.title, design: .rounded))
                    .bold()
                    .foregroundColor(.white)
            }
        }
        .frame(minWidth: 140, maxWidth: 160, minHeight: 90, maxHeight: 110) // Flexible frame for adaptability
    }
}

#Preview {
    VStack(spacing: 20) {
        LabelView(text: "Keep", color: Color.green)
        LabelView(text: "Delete", color: Color.red)
    }
}
