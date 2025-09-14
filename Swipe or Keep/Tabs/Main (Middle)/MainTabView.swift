import SwiftUI

struct MainTabView: View {
    @StateObject private var onboardingManager = OnboardingManager.shared
    @State private var selectedTab: Tab = .main // Set the default tab to .main

    enum Tab {
        case random, main, trash, settings
    }

    var body: some View {
        ZStack {
            VStack {
                Spacer()
                // Content
                switch selectedTab {
                case .random:
                    RandomView()
                case .main:
                    MainView()
                case .trash:
                    TrashView()
                case .settings:
                    UserView()
                }
                Spacer()
                // Custom Tab Bar
                CustomTabBar(selectedTab: $selectedTab)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToMainTab)) { _ in
                withAnimation(.spring()) {
                    selectedTab = .main
                }
            }
            
            // Welcome screen overlay
            if onboardingManager.showWelcomeScreen {
                WelcomeScreen()
                    .transition(.opacity)
                    .zIndex(1000)
            }
        }
    }
}

struct CustomTabBar: View {
    @Binding var selectedTab: MainTabView.Tab
    @Namespace private var animation
    
    // Add a haptic feedback manager
    let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        HStack(spacing: 40) { // Add spacing between tabs for better layout
            tabBarItem(icon: "shuffle", tab: .random)
            tabBarItem(icon: "rectangle.stack", tab: .main)
            tabBarItem(icon: "trash", tab: .trash)
            tabBarItem(icon: "person", tab: .settings)
        }
        .padding(.vertical, 10)
        .background(Color(.clear))
        .padding(.horizontal)
    }

    private func tabBarItem(icon: String, tab: MainTabView.Tab) -> some View {
        Button(action: {
            if selectedTab != tab {
                // Trigger haptic feedback when changing tabs
                haptic.prepare()
                haptic.impactOccurred()
                
                // Animate tab change
                withAnimation(.spring()) {
                    selectedTab = tab
                }
            }
        }) {
            VStack(spacing: 5) { // Add spacing between icon and underline
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(selectedTab == tab ? .white : .blue)
                if selectedTab == tab {
                    Color.red
                        .frame(width: 20, height: 2) // Shortened underline
                        .matchedGeometryEffect(id: "underline", in: animation)
                } else {
                    Color.clear.frame(width: 20, height: 2) // Maintain same width for alignment
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
