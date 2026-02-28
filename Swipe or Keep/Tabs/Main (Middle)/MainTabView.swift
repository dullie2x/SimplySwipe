import SwiftUI

// MARK: - Constants
private enum Spacing {
    static let tabBarBottom: CGFloat = 20
    static let tabBarHorizontal: CGFloat = 20
    static let tabBarInternalHorizontal: CGFloat = 20
    static let tabBarInternalVertical: CGFloat = 16
    static let tabBarCornerRadius: CGFloat = 28
    static let tabIconSpacing: CGFloat = 6
    static let tabIconSize: CGFloat = 24
    static let underlineWidth: CGFloat = 24
    static let underlineHeight: CGFloat = 3
}

private enum ZIndex {
    static let welcomeOverlay: Double = 1000
    static let content: Double = 0
    static let tabBar: Double = 100
}

private enum AnimationConfig {
    static let tabSwitch = Animation.spring(response: 0.3, dampingFraction: 0.7)
    static let debounceDelay: Duration = .milliseconds(300)
}

// MARK: - Main Tab View
@MainActor
struct MainTabView: View {
    // Fixed: Use @ObservedObject instead of @StateObject for singleton
    @ObservedObject private var onboardingManager = OnboardingManager.shared
    
    // First launch → category tab so new users get oriented.
    // Every launch after → random/swipe view to get straight to the action.
    private static func initialTab() -> String {
        let hasOnboarded = UserDefaults.standard.bool(forKey: "completedWelcomeOnboarding")
        return hasOnboarded ? Tab.random.rawValue : Tab.main.rawValue
    }

    @State private var selectedTabRawValue: String = MainTabView.initialTab()

    private var selectedTab: Tab {
        get { Tab(rawValue: selectedTabRawValue) ?? .main }
        set { selectedTabRawValue = newValue.rawValue }
    }
    
    // Added: Debouncing for rapid tab switches
    @State private var isTransitioning = false

    // Hide tab bar while the search overlay is active in MainView
    @State private var isSearchActive = false
    
    var body: some View {
        ZStack {
            contentView
            tabBarOverlay
            welcomeOverlay
        }
        // Fixed: Only ignore container safe area on bottom edge, not all
        .ignoresSafeArea(.container, edges: .bottom)
        .onReceive(navigationPublisher) { _ in
            navigateToMainTab()
        }
        .onReceive(NotificationCenter.default.publisher(for: .searchStateChanged)) { notification in
            if let isSearching = notification.userInfo?["isSearching"] as? Bool {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isSearchActive = isSearching
                }
            }
        }
        // PERFORMANCE: Trigger cleanup when switching tabs
        .onChange(of: selectedTab) { oldValue, newValue in
            // Give the old view a moment to animate out, then request cleanup
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                // Trigger memory cleanup if app has caching
                NotificationCenter.default.post(name: .cleanupOldTabResources, object: nil)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var contentView: some View {
        // PERFORMANCE: Use id() to force view recreation when switching tabs
        // This ensures old views are properly deallocated
        Group {
            switch selectedTab {
            case .random:
                RandomView()
                    .id("tab-random")
            case .main:
                MainView()
                    .id("tab-main")
            case .trash:
                TrashView()
                    .id("tab-trash")
            case .settings:
                UserView()
                    .id("tab-settings")
            }
        }
        .transition(.opacity)
        .zIndex(ZIndex.content)
        // CRITICAL: Force deallocation of previous tab's resources
        .id(selectedTab)
    }
    
    private var tabBarOverlay: some View {
        VStack {
            Spacer()
            CustomTabBar(
                selectedTab: Binding(
                    get: { selectedTab },
                    set: { newValue in
                        selectedTabRawValue = newValue.rawValue
                    }
                ),
                isTransitioning: $isTransitioning
            )
            .padding(.bottom, Spacing.tabBarBottom)
            .padding(.horizontal, Spacing.tabBarHorizontal)
            // Hide tab bar (and disable its hit-testing) while search is active
            .opacity(isSearchActive ? 0 : 1)
            .allowsHitTesting(!isSearchActive)
        }
        .zIndex(ZIndex.tabBar)
    }
    
    @ViewBuilder
    private var welcomeOverlay: some View {
        if onboardingManager.showWelcomeScreen {
            WelcomeScreen()
                .transition(.opacity)
                .zIndex(ZIndex.welcomeOverlay)
        }
    }
    
    // MARK: - Helpers
    
    private var navigationPublisher: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: .navigateToMainTab)
    }
    
    private func navigateToMainTab() {
        guard selectedTab != .main, !isTransitioning else { return }
        
        isTransitioning = true
        withAnimation(AnimationConfig.tabSwitch) {
            selectedTabRawValue = Tab.main.rawValue
        }
        
        // Reset debounce flag
        Task {
            try? await Task.sleep(for: AnimationConfig.debounceDelay)
            isTransitioning = false
        }
    }
}

// MARK: - Tab Enum
extension MainTabView {
    enum Tab: String, CaseIterable, Identifiable {
        case random, main, trash, settings
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .random: return "shuffle"
            case .main: return "rectangle.stack"
            case .trash: return "trash"
            case .settings: return "person"
            }
        }
        
        var label: String {
            switch self {
            case .random: return "Random"
            case .main: return "Library"
            case .trash: return "Trash"
            case .settings: return "Settings"
            }
        }
        
        var accessibilityHint: String {
            switch self {
            case .random: return "Swipe through all your media randomly"
            case .main: return "View your media library"
            case .trash: return "View deleted items"
            case .settings: return "Manage your account and preferences"
            }
        }
    }
}

// MARK: - Custom Tab Bar
struct CustomTabBar: View {
    @Binding var selectedTab: MainTabView.Tab
    @Binding var isTransitioning: Bool
    
    @Namespace private var animation
    
    // PERFORMANCE: Share haptic generator across lifecycle
    private static let sharedHaptic = UIImpactFeedbackGenerator(style: .medium)
    
    // Added: Track pressed state for visual feedback
    @State private var pressedTab: MainTabView.Tab?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTabView.Tab.allCases) { tab in
                tabBarItem(tab: tab)
            }
        }
        .padding(.horizontal, Spacing.tabBarInternalHorizontal)
        .padding(.vertical, Spacing.tabBarInternalVertical)
        .background(tabBarBackground)
        // Fixed: Use compositingGroup for better shadow performance
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.3), radius: 15, x: 0, y: 8)
        .onAppear {
            Self.sharedHaptic.prepare()
        }
    }
    
    private var tabBarBackground: some View {
        RoundedRectangle(cornerRadius: Spacing.tabBarCornerRadius)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.tabBarCornerRadius)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.2),
                                Color.white.opacity(0.08)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: Spacing.tabBarCornerRadius)
                    .fill(.ultraThinMaterial)
                    .opacity(0.3)
            )
    }

    private func tabBarItem(tab: MainTabView.Tab) -> some View {
        Button(action: {
            handleTabSelection(tab)
        }) {
            VStack(spacing: Spacing.tabIconSpacing) {
                Image(systemName: tab.icon)
                    .font(.system(
                        size: Spacing.tabIconSize,
                        weight: selectedTab == tab ? .semibold : .regular
                    ))
                    .foregroundColor(selectedTab == tab ? .white : .white.opacity(0.5))
                    .scaleEffect(selectedTab == tab ? 1.1 : 1.0)
                    // Added: Press feedback animation
                    .scaleEffect(pressedTab == tab ? 0.9 : 1.0)
                
                tabUnderline(for: tab)
            }
        }
        .frame(maxWidth: .infinity)
        // Added: Full accessibility support
        .accessibilityLabel(tab.label)
        .accessibilityHint(tab.accessibilityHint)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        // Added: Visual press feedback
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if pressedTab == nil {
                        pressedTab = tab
                    }
                }
                .onEnded { _ in
                    pressedTab = nil
                }
        )
    }
    
    @ViewBuilder
    private func tabUnderline(for tab: MainTabView.Tab) -> some View {
        if selectedTab == tab {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.blue,
                            Color.blue.opacity(0.8)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: Spacing.underlineWidth, height: Spacing.underlineHeight)
                // Fixed: Make ID unique in case of multiple tab bars
                .matchedGeometryEffect(id: "underline", in: animation)
        } else {
            Color.clear
                .frame(width: Spacing.underlineWidth, height: Spacing.underlineHeight)
        }
    }
    
    private func handleTabSelection(_ tab: MainTabView.Tab) {
        // Added: Debouncing to prevent rapid tab switches
        guard selectedTab != tab, !isTransitioning else { return }
        
        // Trigger haptic feedback
        Self.sharedHaptic.impactOccurred()
        Self.sharedHaptic.prepare() // Prepare for next interaction
        
        // Added: Set transitioning flag
        isTransitioning = true
        
        withAnimation(AnimationConfig.tabSwitch) {
            selectedTab = tab
        }
        
        // Reset transitioning flag after animation
        Task {
            try? await Task.sleep(for: AnimationConfig.debounceDelay)
            isTransitioning = false
        }
    }
}

// MARK: - Previews
struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .preferredColorScheme(.dark)
    }
}
