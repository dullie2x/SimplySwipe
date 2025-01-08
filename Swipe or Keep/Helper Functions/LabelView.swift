//
//  LabelView.swift
//  Swipe or Keep
//
//  Created by Gbolade Ariyo on 12/24/24.
//

import SwiftUI

struct LabelView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.largeTitle)
            .bold()
            .foregroundColor(.white)
            .padding()
            .background(color.opacity(0.7))
            .cornerRadius(10)
    }
}
#Preview {
    LabelView()
}
