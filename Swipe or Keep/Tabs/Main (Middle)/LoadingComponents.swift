//
//  LoadingComponents.swift
//  Swipe or Keep
//
//  Modern, minimal loading indicators
//

import SwiftUI

// MARK: - Shimmer Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -200
    let isActive: Bool
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isActive {
                        GeometryReader { geometry in
                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.12),
                                    .white.opacity(0.18),
                                    .white.opacity(0.12),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: 200)
                            .offset(x: phase)
                            .onAppear {
                                withAnimation(
                                    .linear(duration: 1.8)
                                        .repeatForever(autoreverses: false)
                                ) {
                                    phase = geometry.size.width + 200
                                }
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
            )
    }
}

extension View {
    func shimmer(isActive: Bool = true) -> some View {
        modifier(ShimmerModifier(isActive: isActive))
    }
}

// MARK: - Pulsing Dot Indicator

struct LoadingDot: View {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.6
    
    var body: some View {
        Circle()
            .fill(.white.opacity(opacity))
            .frame(width: 6, height: 6)
            .scaleEffect(scale)
            .shadow(color: .white.opacity(0.3), radius: 4)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.2)
                        .repeatForever(autoreverses: true)
                ) {
                    scale = 1.4
                    opacity = 0.9
                }
            }
    }
}

// MARK: - Minimal Loading Overlay

struct MinimalLoadingOverlay: View {
    let isLoading: Bool
    let isSlow: Bool
    let message: String?
    
    init(isLoading: Bool, isSlow: Bool = false, message: String? = nil) {
        self.isLoading = isLoading
        self.isSlow = isSlow
        self.message = message
    }
    
    var body: some View {
        if isLoading {
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        LoadingDot()
                        
                        if isSlow, let msg = message {
                            Text(msg)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, isSlow ? 12 : 8)
                    .padding(.vertical, isSlow ? 8 : 6)
                    .background(
                        Capsule()
                            .fill(.black.opacity(isSlow ? 0.7 : 0.5))
                            .shadow(color: .black.opacity(0.3), radius: 8)
                    )
                    .padding()
                }
                Spacer()
            }
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
            .animation(.spring(response: 0.3), value: isLoading)
        }
    }
}

// MARK: - Error Overlay

struct ErrorOverlay: View {
    let error: Error?
    let onRetry: () -> Void
    
    var body: some View {
        if error != nil {
            ZStack {
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 56, weight: .light))
                        .foregroundColor(.yellow.opacity(0.9))
                        .shadow(color: .yellow.opacity(0.3), radius: 10)
                    
                    Text("Unable to Load")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if let error = error {
                        Text(error.localizedDescription)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .lineLimit(3)
                    }
                    
                    Button(action: onRetry) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(Color.blue)
                                .shadow(color: .blue.opacity(0.4), radius: 10)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(.spring(response: 0.4), value: error != nil)
        }
    }
}

// MARK: - Network Error Specific

struct NetworkErrorOverlay: View {
    let onRetry: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(.orange.opacity(0.9))
                    .shadow(color: .orange.opacity(0.3), radius: 10)
                
                Text("No Connection")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Check your internet connection and try again")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Button(action: onRetry) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(Color.orange)
                            .shadow(color: .orange.opacity(0.4), radius: 10)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}

// MARK: - Thumbnail Placeholder

struct ThumbnailPlaceholder: View {
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        ZStack {
            // Very minimal dark background
            Color.black.opacity(0.95)
            
            // Simple spinning grey ring
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    Color.gray,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 50, height: 50)
                .rotationEffect(.degrees(rotationAngle))
                .onAppear {
                    withAnimation(
                        .linear(duration: 1.0)
                        .repeatForever(autoreverses: false)
                    ) {
                        rotationAngle = 360
                    }
                }
        }
    }
}
