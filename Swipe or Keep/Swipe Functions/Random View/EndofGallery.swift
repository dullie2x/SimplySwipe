//
//  EndofGallery.swift
//  Swipe or Keep
//
//  Created by Gbolade Ariyo on 7/13/25.
//

import SwiftUI

struct EndOfGalleryView: View {
    let totalCount: Int
    let seenCount: Int
    let onRestart: () -> Void
    let onGoHome: () -> Void
    
    var body: some View {
        ZStack {
            // Background
            Color.black.opacity(0.95)
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // Completion Icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.green)
                
                // Main message
                VStack(spacing: 15) {
                    Text("Gallery Complete!")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("You've reviewed all \(totalCount) photos and videos")
                        .font(.system(size: 18))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 16) {
                    // Start Again button
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                        onRestart()
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Start Again")
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.blue)
                        .cornerRadius(16)
                    }
                    
                    // Go to Home button
                    Button(action: {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        onGoHome()
                    }) {
                        HStack {
                            Image(systemName: "house")
                                .font(.system(size: 16, weight: .medium))
                            Text("Go to Home")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 50)
            }
        }
    }
}

// MARK: - Preview
struct EndOfGalleryView_Previews: PreviewProvider {
    static var previews: some View {
        EndOfGalleryView(
            totalCount: 1247,
            seenCount: 1247,
            onRestart: {},
            onGoHome: {}
        )
    }
}
