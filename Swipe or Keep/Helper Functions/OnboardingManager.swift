import SwiftUI
import UIKit

// MARK: - Onboarding Manager (Keep existing logic)
class OnboardingManager: ObservableObject {
    @Published var showWelcomeScreen = false
    @Published var showRandomTooltip = false
    @Published var showMainTooltip = false
    @Published var showTrashTooltip = false
    @Published var showUserTooltip = false

    static let shared = OnboardingManager()

    private init() {
        checkOnboardingStatus()
    }

    private func checkOnboardingStatus() {
        let hasCompletedWelcome = UserDefaults.standard.bool(forKey: "completedWelcomeOnboarding")

        if !hasCompletedWelcome {
            showWelcomeScreen = true
        } else {
            // Check individual tooltips
            showRandomTooltip = !UserDefaults.standard.bool(forKey: "seenRandomTooltip")
            showMainTooltip  = !UserDefaults.standard.bool(forKey: "seenMainTooltip")
            showTrashTooltip = !UserDefaults.standard.bool(forKey: "seenTrashTooltip")
            showUserTooltip  = !UserDefaults.standard.bool(forKey: "seenUserTooltip")
        }
    }

    func completeWelcome() {
        UserDefaults.standard.set(true, forKey: "completedWelcomeOnboarding")
        showWelcomeScreen = false

        // Show tooltips for each view
        showRandomTooltip = true
        showMainTooltip = true
        showTrashTooltip = true
        showUserTooltip = true
    }

    func dismissTooltip(for view: String) {
        UserDefaults.standard.set(true, forKey: "seen\(view)Tooltip")

        switch view {
        case "Random":
            showRandomTooltip = false
        case "Main":
            showMainTooltip = false
        case "Trash":
            showTrashTooltip = false
        case "User":
            showUserTooltip = false
        default:
            break
        }
    }

    func skipAllTooltips() {
        UserDefaults.standard.set(true, forKey: "seenRandomTooltip")
        UserDefaults.standard.set(true, forKey: "seenMainTooltip")
        UserDefaults.standard.set(true, forKey: "seenTrashTooltip")
        UserDefaults.standard.set(true, forKey: "seenUserTooltip")

        showRandomTooltip = false
        showMainTooltip = false
        showTrashTooltip = false
        showUserTooltip = false
    }

    func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: "completedWelcomeOnboarding")
        UserDefaults.standard.removeObject(forKey: "seenRandomTooltip")
        UserDefaults.standard.removeObject(forKey: "seenMainTooltip")
        UserDefaults.standard.removeObject(forKey: "seenTrashTooltip")
        UserDefaults.standard.removeObject(forKey: "seenUserTooltip")
        checkOnboardingStatus()
    }
}

// MARK: - Enhanced Welcome Screen
struct WelcomeScreen: View {
    @ObservedObject var onboardingManager = OnboardingManager.shared
    @State private var currentPage = 0
    @State private var showContent = false
    @State private var animateSwipeDemo = false

    private let pages = [
        OnboardingPage(
            icon: "orca8",
            title: "Simply Swipe",
            subtitle: "Organize your media effortlessly",
            description: "The fastest way to clean up your photo library with intuitive swipe gestures",
            color: .blue
        ),
        OnboardingPage(
            icon: "hand.point.right.fill",
            title: "Swipe to Organize",
            subtitle: "Right to keep, left to delete",
            description: "Make quick decisions about thousands of photos and videos in minutes",
            color: .white
        ),
        OnboardingPage(
            icon: "shield.lefthalf.filled",
            title: "Privacy First",
            subtitle: "Everything stays on your device",
            description: "No uploads, no cloud storage, no tracking. Your memories remain completely private",
            color: .purple
        ),
        OnboardingPage(
            icon: "trash.slash.fill",
            title: "Safe Deletion",
            subtitle: "Review before you remove",
            description: "Items go to trash first, giving you time to recover anything you want to keep",
            color: .red
        )
    ]

    private var swipePageIndex: Int {
        pages.firstIndex { $0.title == "Swipe to Organize" } ?? 1
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button("Skip") { completeOnboarding() }
                        .font(.custom(AppFont.regular, size: 16))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.trailing, 24)
                        .padding(.top, 16)
                }

                // Page content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        OnboardingPageView(
                            page: pages[index],
                            showContent: $showContent,
                            animateSwipeDemo: $animateSwipeDemo
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.6), value: currentPage)

                // Page indicator + CTA
                VStack(spacing: 24) {
                    // Dots
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentPage ? .white : .white.opacity(0.3))
                                .frame(width: 8, height: 8)
                                .scaleEffect(index == currentPage ? 1.2 : 1.0)
                                .animation(.spring(response: 0.3), value: currentPage)
                        }
                    }

                    // Action button
                    Button(action: {
                        if currentPage < pages.count - 1 {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                currentPage += 1
                            }
                        } else {
                            completeOnboarding()
                        }
                    }) {
                        HStack(spacing: 12) {
                            Text(currentPage < pages.count - 1 ? "Continue" : "Get Started")
                                .font(.custom(AppFont.regular, size: 18))
                                .foregroundColor(.black)

                            Image(systemName: currentPage < pages.count - 1 ? "arrow.right" : "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white)
                                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 4)
                        )
                    }
                    .padding(.horizontal, 32)
                    .scaleEffect(showContent ? 1.0 : 0.8)
                    .opacity(showContent ? 1.0 : 0.0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)
                }
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                showContent = true
            }
            // Ensure demo anim is correct when we first appear
            animateSwipeDemo = (currentPage == swipePageIndex)
        }
        // iOS 17+ onChange that also fires once initially
        .onChange(of: currentPage, initial: true) { _, newValue in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            animateSwipeDemo = (newValue == swipePageIndex)
        }
    }

    private func completeOnboarding() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            onboardingManager.completeWelcome()
        }
    }
}

// MARK: - Onboarding Page Model
struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let description: String
    let color: Color
}

// MARK: - Individual Page View
struct OnboardingPageView: View {
    let page: OnboardingPage
    @Binding var showContent: Bool
    @Binding var animateSwipeDemo: Bool
    @State private var iconScale: CGFloat = 0.5
    @State private var iconRotation: Double = 0

    // Demo images (edit as you like)
    private let demoImages = ["ade", "honey", "ade", "honey"]

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            if page.title == "Swipe to Organize" {
                VerticalSwipeDemo(animate: $animateSwipeDemo, images: demoImages)
                    .frame(height: 260)
            } else {
                Group {
                    if page.icon == "orca8" {
                        Image("orca8")
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: page.icon)
                            .font(.system(size: 80, weight: .light))
                    }
                }
                .frame(width: 120, height: 120)
                .foregroundColor(.white)
                .background(
                    Circle()
                        .fill(page.color.opacity(0.2))
                        .background(
                            Circle()
                                .fill(page.color.opacity(0.1))
                                .scaleEffect(1.3)
                        )
                )
                .scaleEffect(iconScale)
                .rotationEffect(.degrees(iconRotation))
                .onAppear {
                    withAnimation(.spring(response: 0.8, dampingFraction: 0.6).delay(0.2)) {
                        iconScale = 1.0
                    }
                    withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true).delay(1.0)) {
                        iconRotation = page.icon == "orca8" ? 5 : 0
                    }
                }
            }

            // Text content
            VStack(spacing: 16) {
                Text(page.title)
                    .font(.custom(AppFont.regular, size: 36))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .opacity(showContent ? 1.0 : 0.0)
                    .offset(y: showContent ? 0 : 20)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3), value: showContent)

                Text(page.subtitle)
                    .font(.custom(AppFont.regular, size: 20))
                    .foregroundColor(page.color)
                    .multilineTextAlignment(.center)
                    .opacity(showContent ? 1.0 : 0.0)
                    .offset(y: showContent ? 0 : 20)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4), value: showContent)

                Text(page.description)
                    .font(.custom(AppFont.regular, size: 16))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 32)
                    .opacity(showContent ? 1.0 : 0.0)
                    .offset(y: showContent ? 0 : 20)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.5), value: showContent)
            }

            Spacer()
        }
    }
}

// MARK: - Simple Swipe Demo (One image at a time, alternating swipes)
struct VerticalSwipeDemo: View {
    @Binding var animate: Bool
    let images: [String]
    
    @State private var currentImageIndex = 0
    @State private var animationTimer: Timer?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SwipeCardDemo(
                    imageName: images[currentImageIndex],
                    swipeDirection: currentImageIndex % 2 == 0 ? .left : .right,
                    animate: animate
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if animate {
                startAnimation()
            }
        }
        .onChange(of: animate) { _, newValue in
            if newValue {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
    }
    
    private func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                currentImageIndex = (currentImageIndex + 1) % images.count
            }
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}

// MARK: - Simple Swipe Card with smooth one-direction animation
struct SwipeCardDemo: View {
    let imageName: String
    let swipeDirection: SwipeDirection
    let animate: Bool
    
    @State private var offset: CGFloat = 0
    @State private var showHands = false
    
    enum SwipeDirection {
        case left, right
    }
    
    private var cardWidth: CGFloat { 180 }
    private var cardHeight: CGFloat { cardWidth * 1.6 }
    
    var body: some View {
        ZStack {
            // The card with image completely locked together
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black)
                .frame(width: cardWidth, height: cardHeight)
                .overlay(
                    Image(imageName)
                        .resizable()
                        .frame(width: cardWidth, height: cardHeight)
                        .clipped()
                        .overlay(Color.black.opacity(0.15))
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
                .offset(x: offset)
                .rotationEffect(.degrees(offset * 0.08))
            
            // Hand indicators
            if showHands {
                HStack(spacing: cardWidth + 40) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.red.opacity(swipeDirection == .left ? 1.0 : 0.3))
                    
                    Image(systemName: "hand.thumbsup.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green.opacity(swipeDirection == .right ? 1.0 : 0.3))
                }
            }
        }
        .onAppear {
            if animate {
                startSwipeAnimation()
            }
        }
        .onChange(of: animate) { _, newValue in
            if newValue {
                startSwipeAnimation()
            } else {
                stopSwipeAnimation()
            }
        }
        .onChange(of: imageName) { _, _ in
            if animate {
                // Reset and restart animation for new image
                offset = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    startSwipeAnimation()
                }
            }
        }
    }
    
    private func startSwipeAnimation() {
        showHands = true
        
        let targetOffset: CGFloat = swipeDirection == .left ? -80 : 80
        
        // Smooth one-direction animation with slight pause at the end
        withAnimation(.easeInOut(duration: 1.2)) {
            offset = targetOffset
        }
        
        // Hold position briefly, then reset for next cycle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.4)) {
                offset = 0
            }
        }
    }
    
    private func stopSwipeAnimation() {
        showHands = false
        withAnimation(.easeInOut(duration: 0.3)) {
            offset = 0
        }
    }
}

// MARK: - Previews
#Preview {
    WelcomeScreen()
        .preferredColorScheme(.dark)
}

#Preview("Simple Swipe Demo") {
    ZStack {
        Color.black.ignoresSafeArea()
        
        VerticalSwipeDemo(
            animate: .constant(true),
            images: ["ade", "honey"]
        )
        .frame(height: 400)
        .padding()
    }
}
// MARK: - Enhanced Tooltip View
struct TooltipView: View {
    let title: String
    let message: String
    let position: TooltipPosition
    let onDismiss: () -> Void
    let onSkipAll: () -> Void

    enum TooltipPosition {
        case top, bottom, center
    }

    var body: some View {
        VStack {
            if position == .bottom { Spacer() }

            VStack(spacing: 16) {
                // Icon + Title Row
                HStack(spacing: 12) {
                    Image("orca8")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)

                    Text(title)
                        .font(.custom(AppFont.regular, size: 16))
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }

                // Message
                Text(message)
                    .font(.custom(AppFont.regular, size: 14))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                // Action Buttons
                HStack(spacing: 12) {
                    Button("Skip All", action: onSkipAll)
                        .font(.custom(AppFont.regular, size: 13))
                        .foregroundColor(.gray)

                    Spacer()

                    Button(action: onDismiss) {
                        Text("Got it")
                            .font(.custom(AppFont.regular, size: 13))
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                    )
            )
            .shadow(color: Color.blue.opacity(0.2), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 24)

            if position == .top { Spacer() }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

// MARK: - Tooltip Overlay Modifier
struct TooltipOverlay: ViewModifier {
    @ObservedObject var onboardingManager = OnboardingManager.shared
    let viewName: String
    let title: String
    let message: String
    let position: TooltipView.TooltipPosition

    private var shouldShow: Bool {
        switch viewName {
        case "Random": return onboardingManager.showRandomTooltip
        case "Main":   return onboardingManager.showMainTooltip
        case "Trash":  return onboardingManager.showTrashTooltip
        case "User":   return onboardingManager.showUserTooltip
        default:       return false
        }
    }

    func body(content: Content) -> some View {
        ZStack {
            content

            if shouldShow {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onboardingManager.dismissTooltip(for: viewName)
                    }

                TooltipView(
                    title: title,
                    message: message,
                    position: position,
                    onDismiss: {
                        withAnimation(.spring()) {
                            onboardingManager.dismissTooltip(for: viewName)
                        }
                    },
                    onSkipAll: {
                        withAnimation(.spring()) {
                            onboardingManager.skipAllTooltips()
                        }
                    }
                )
            }
        }
    }
}

// MARK: - View Extension
extension View {
    func tooltip(
        viewName: String,
        title: String,
        message: String,
        position: TooltipView.TooltipPosition = .center
    ) -> some View {
        self.modifier(
            TooltipOverlay(
                viewName: viewName,
                title: title,
                message: message,
                position: position
            )
        )
    }
}
