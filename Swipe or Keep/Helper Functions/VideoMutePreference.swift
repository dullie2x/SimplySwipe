//
//  VideoMutePreference.swift
//  Global video mute state manager
//

import Foundation

/// Manages the global mute preference for all videos
/// Default is muted, but once user toggles it, all subsequent videos follow that preference
class VideoMutePreference {
    static let shared = VideoMutePreference()
    
    private let userDefaultsKey = "globalVideoMuteState"
    
    /// Current mute state (default: true/muted)
    var isMuted: Bool {
        get {
            // Default to true (muted) if not set
            if UserDefaults.standard.object(forKey: userDefaultsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: userDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
        }
    }
    
    /// Toggle the global mute state
    func toggle() -> Bool {
        isMuted.toggle()
        return isMuted
    }
    
    /// Reset to default (muted)
    func reset() {
        isMuted = true
    }
    
    private init() {}
}
