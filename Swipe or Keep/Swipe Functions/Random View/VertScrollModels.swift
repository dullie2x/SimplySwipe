//
//  VertScrollModels.swift
//  Media App
//
//  Created on [Date]
//

import Foundation
import Photos

struct MediaItemTracker {
    let identifier: String
    var swipeDirection: SwipeDirection?
    var hasBeenSeen: Bool
    var lastViewedAt: Date?
    var isInTrash: Bool
    
    init(identifier: String) {
        self.identifier = identifier
        self.swipeDirection = nil
        self.hasBeenSeen = false
        self.lastViewedAt = nil
        self.isInTrash = false
    }
}

enum GestureDirection {
    case horizontal, vertical, undecided
}

struct VideoControlState {
    var isMuted: Bool = true
    var isPaused: Bool = false
    var showControls: Bool = true
    var controlsTimer: Timer?
    
    mutating func showControlsTemporarily(duration: TimeInterval = 3.0, hideAction: @escaping () -> Void) {
        showControls = true
        resetControlsTimer(duration: duration, hideAction: hideAction)
    }
    
    mutating func resetControlsTimer(duration: TimeInterval = 3.0, hideAction: @escaping () -> Void) {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            hideAction()
        }
    }
    
    mutating func toggleMute() {
        isMuted.toggle()
    }
    
    mutating func togglePlayPause() {
        isPaused.toggle()
    }
    
    mutating func cleanup() {
        controlsTimer?.invalidate()
        controlsTimer = nil
    }
}
