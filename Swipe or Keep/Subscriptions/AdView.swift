import SwiftUI

struct AdView: View {
    @Environment(\.dismiss) var dismiss
    @State private var adLoading = true
    @State private var adFinished = false // Controls when "X" appears

    var body: some View {
        ZStack {
            // Background blur
            Color.black.opacity(0.6)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 20) {
                // Loading Indicator
                if adLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                        .padding()
                    
                    // Text under the loading wheel
                    Text("Ad test, wait 3 seconds")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.top, 5)
                }
            }
            .padding()
            .frame(maxWidth: 300)
            .background(Color.black.opacity(0.3))
            .cornerRadius(20)
            .shadow(radius: 10)

            // Close "X" Button (Only shows after ad is finished)
            VStack {
                HStack {
                    Spacer()
                    if adFinished {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .resizable()
                                .frame(width: 30, height: 30)
                                .foregroundColor(.white.opacity(0.6))
                                .shadow(radius: 5)
                        }
                        .padding(.top, 15)
                        .padding(.trailing, 15)
                        .transition(.opacity)
                    }
                }
                Spacer()
            }
        }
        .onAppear {
            simulateAdPlayback()
        }
        .interactiveDismissDisabled(true) // Completely prevents swipe-down dismissal
    }

    // Simulated function for ad playback
    private func simulateAdPlayback() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { // Simulate a 3-second ad
            adLoading = false
            adFinished = true
        }
    }
}

struct AdView_Previews: PreviewProvider {
    static var previews: some View {
        AdView()
    }
}
