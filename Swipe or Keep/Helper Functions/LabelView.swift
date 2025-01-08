// LabelView.swift
// Swipe or Keep
//
// Created by Gbolade Ariyo on 12/24/24.

import SwiftUI

struct LabelView: View {
    let text: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(color.opacity(0.85))
                .shadow(radius: 10)

            VStack(spacing: 5) {
                Image(systemName: text == "Keep" ? "hand.thumbsup.fill" : "trash.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)

                Text(text)
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)
            }
        }
        .frame(width: 150, height: 100)
        .animation(.spring(), value: text) // Smooth transitions for label appearance
    }
}

#Preview {
    VStack(spacing: 20) {
        LabelView(text: "Keep", color: Color.green)
        LabelView(text: "Delete", color: Color.red)
    }
}
