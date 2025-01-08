//
//  Swipe_or_KeepApp.swift
//  Swipe or Keep
//
//  Created by Gbolade Ariyo on 12/22/24.
//

import SwiftUI

@main
struct Swipe_or_KeepApp: App {
    init() {
        // Force dark mode throughout the app
        UIView.appearance().overrideUserInterfaceStyle = .dark
    }

    var body: some Scene {
        WindowGroup {
            SplashView()
        }
    }
}

