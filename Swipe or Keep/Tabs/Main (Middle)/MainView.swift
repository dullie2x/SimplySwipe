import SwiftUI

struct MainView: View {
    @State private var showInstructions: Bool
    
    init() {
        // Check if this is the first launch
        let hasSeenInstructions = UserDefaults.standard.bool(forKey: "hasSeenInstructions")
        _showInstructions = State(initialValue: !hasSeenInstructions)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack {
                    // App Name Header
                    Text("Simply Swipe")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.top, 20)
                        .padding(.bottom, 10)
                    
                    // Navigation Blocks
                    NavStackedBlocksView(
                        blockTitles: ["Recents", "Screenshots", "Favorites", "Years", "Albums"]
                    )
                    
                    Spacer()
                }
                .background(Color.black.ignoresSafeArea())
                
                // Instructions overlay
                if showInstructions {
                    Color.black.opacity(0.8)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) {
                                dismissInstructions()
                            }
                        }
                    
                    VStack(alignment: .leading, spacing: 15) {
                        // Header with close button
                        HStack {
                            Text("Quick Guide")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            Button(action: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    dismissInstructions()
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Basic gestures
                        VStack(alignment: .leading, spacing: 14) {
                            keepDeleteRow(icon: "hand.thumbsup.fill", prefix: "Right Swipe = ", keyword: "Keep", color: .green)
                            keepDeleteRow(icon: "hand.thumbsdown.fill", prefix: "Left Swipe = ", keyword: "Delete", color: .red)
                        }
                        
                        Divider()
                            .background(Color.white.opacity(0.3))
                            .padding(.vertical, 5)
                        
                        // App sections
                        VStack(alignment: .leading, spacing: 14) {
                            instructionRow(icon: "shuffle", text: "Random")
                            instructionRow(icon: "rectangle.stack", text: "Categories")
                            instructionRow(icon: "trash.fill", text: "Deletion Queue")
                            instructionRow(icon: "person.fill", text: "User Stats")
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color(hex: "#1A1A1A"), Color(hex: "#0D0D0D")]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.green.opacity(0.7), Color.blue.opacity(0.7)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: Color.green.opacity(0.3), radius: 10, x: 0, y: 5)
                    .padding(.horizontal, 28)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .center)))
                }
            }
            .navigationBarHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EmptyView() // Removes the back button
                }
            }
        }
    }
    
    private func dismissInstructions() {
        showInstructions = false
        // Save that user has seen instructions
        UserDefaults.standard.set(true, forKey: "hasSeenInstructions")
    }
    
    private func instructionRow(icon: String, text: String) -> some View {
        HStack(alignment: .center, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.green.opacity(0.9), Color.blue.opacity(0.9)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 26, height: 26)
            
            Text(text)
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .lineSpacing(4)
        }
    }
    
    private func keepDeleteRow(icon: String, prefix: String, keyword: String, color: Color) -> some View {
        HStack(alignment: .center, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.green.opacity(0.9), Color.blue.opacity(0.9)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 26, height: 26)
            
            HStack(spacing: 0) {
                Text(prefix)
                    .foregroundColor(.white)
                
                Text(keyword)
                    .foregroundColor(color)
            }
            .font(.system(size: 18, weight: .medium, design: .rounded))
            .lineSpacing(4)
        }
    }
}

// Add extension for hex colors
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
