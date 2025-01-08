//
//  StackedBlocksView.swift
//  Swipe or Keep
//
//  Created by Gbolade Ariyo on 12/22/24.
//

import SwiftUI

struct StackedBlocksView: View {
    var blockCount: Int = 40 // Default number of blocks
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) { // Removed scroll indicators
            VStack(spacing: 5) { // Increased spacing for a modern look
                Spacer() // Adds space at the top
                    .frame(height: 60) // Adjust the height for more or less spacing
                
                ForEach(0..<blockCount, id: \.self) { index in
                    Button(action: {
                        print("Category \(index + 1) clicked")
                    }) {
                        RoundedRectangle(cornerRadius: 5) // Rounded corners for modern look
                            .fill(LinearGradient(
                                gradient: Gradient(colors: gradientColors(for: index)),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(height: 75)
                            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2) // Subtle shadow for depth
                            .overlay(
                                Text("Category \(index + 1)")
                                    .foregroundColor(.white)
                                    .font(Font.title2.weight(.heavy))
                                    .padding()
                            )
                    }
                }
            }
            .padding(.horizontal, 5) // Added horizontal padding for alignment
        }
        .background(Color(.systemGray6)) // Light gray background for contrast
    }
    
    // Function to provide gradient colors for each block
    func gradientColors(for index: Int) -> [Color] {
        let baseColors: [Color] = [
            Color.green.opacity(0.7),
            Color.white.opacity(0.7),
            Color.black.opacity(0.7),
            Color.gray.opacity(0.7)
        ]
        let firstColor = baseColors[index % baseColors.count]
        let secondColor = baseColors[(index + 1) % baseColors.count]
        return [firstColor, secondColor]
    }
}

#Preview {
    StackedBlocksView()
}
