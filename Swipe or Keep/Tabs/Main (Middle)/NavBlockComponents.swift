//
//  NavBlockComponents.swift
//  Reusable UI components for NavStackedBlocksView
//

import SwiftUI

// MARK: - Circular Progress View

struct CircularProgressView: View {
    var progress: Double
    var gradient: [Color]
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(lineWidth: 3)
                .opacity(0.2)
                .foregroundColor(Color.white)
            
            // Progress circle
            Circle()
                .trim(from: 0.0, to: min(CGFloat(progress), 1.0))
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: gradient),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(Angle(degrees: 270.0))
                .animation(.linear, value: progress)
            
            // Progress text
            if progress > 0 {
                Text("\(Int(ceil(progress * 100)))%")
                    .font(.custom(AppFont.regular, size: 10))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 40, height: 40)
    }
}

// MARK: - Button Styles

struct SearchSuggestionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct QuickActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var message: String
    var onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            VStack(spacing: 60) {
                Spacer()
                BouncingLogo(size: 120, amplitude: 15, period: 1.0)
                Spacer()
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.custom(AppFont.regular, size: 16))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        )
                }
                .padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Bouncing Logo

struct BouncingLogo: View {
    var size: CGFloat = 100
    var amplitude: CGFloat = 10
    var period: Double = 0.9

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let y = sin((2 * .pi / period) * t) * amplitude

            Image("orca8")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .offset(y: y)
        }
    }
}
