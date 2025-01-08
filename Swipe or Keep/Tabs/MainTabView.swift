//
//  MainTabView.swift
//  Swipe or Keep
//
//  Created by Gbolade Ariyo on 12/22/24.
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            // Random Tab
            RandomView()
                .tabItem {
                    Label("Random", systemImage: "shuffle")
                }

            // Main Tab
            MainView()
                .tabItem {
                    Label("Main", systemImage: "rectangle.stack")
                }

            // User Tab (Settings)
            UserView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
