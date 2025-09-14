//
//  ContentView.swift
//  Swipe or Keep
//
//  Created by Gbolade Ariyo on 12/22/24.
//

import SwiftUI

struct RandomView: View {
    var body: some View {
        VertScroll()
            .tooltip(
                viewName: "Random",
                title: "Random Swipe Mode",
                message: "Swipe through all your media randomly.\n\nRight swipe = Keep\nLeft swipe = Delete\n\n",
                position: .center
            )
    }
}

#Preview {
    RandomView()
}
