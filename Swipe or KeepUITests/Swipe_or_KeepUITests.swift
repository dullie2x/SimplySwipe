//
//  Swipe_or_KeepUITests.swift
//  Swipe or KeepUITests
//
//  Created by Gbolade Ariyo on 12/22/24.
//

import XCTest

final class Swipe_or_KeepUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {}

    // MARK: - Overnight Stress Test
    //
    // Runs 10,000 swipes (roughly 5-8 hours) to verify the app doesn't crash
    // or leak memory during extended use.
    //
    // HOW TO RUN:
    //   1. Plug in your iPhone (do NOT use the simulator — real memory pressure needed)
    //   2. Settings → Display & Brightness → Auto-Lock → Never
    //   3. Keep Wi-Fi on so iCloud downloads happen throughout
    //   4. In Xcode: Product → Scheme → Edit Scheme → Test → Swipe or KeepUITests
    //      → Options → Execution Time Allowance → set to 36000 seconds (10 hours)
    //   5. Right-click testOvernightSwipeStress in the gutter → Run
    //   6. Leave overnight. Green ✅ in the morning = passed. Red ✗ = crash log to inspect.
    //
    // WHAT TO CHECK AFTER:
    //   - Green checkmark in the test navigator (no crash)
    //   - Memory graph in Xcode Debug Navigator stayed flat (no upward creep)
    //   - Console: search "CRITICAL" or "Memory budget" to see how often cleanup fired
    //   - Open the app and tap the debug/telemetry button for the final report

    @MainActor
    func testOvernightSwipeStress() throws {
        let app = XCUIApplication()
        app.launch()

        // Wait for the app to load the first item
        sleep(4)

        let totalSwipes = 10_000
        let logInterval = 100    // Print progress every 100 swipes
        let pauseInterval = 50   // Briefly pause every 50 swipes (mimics dwell detection)
        let pauseDuration: UInt32 = 2  // seconds

        for i in 1...totalSwipes {
            // Swipe mix that mimics real user behaviour:
            //   75% swipe up   (forward — most common)
            //   15% swipe right (keep)
            //   8%  swipe down  (back)
            //   2%  swipe left  (trash)
            let roll = i % 100
            let swipeRight = roll < 15               // i % 100 in 0..<15
            let swipeLeft  = roll >= 15 && roll < 17 // i % 100 in 15..<17
            let goBack     = roll >= 17 && roll < 25 // i % 100 in 17..<25
            // else: swipe up (forward)

            let startCoord: XCUICoordinate
            let endCoord: XCUICoordinate

            if swipeRight {
                // Horizontal right swipe (keep) — drag from left-centre to right-centre
                startCoord = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
                endCoord   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.5))
            } else if swipeLeft {
                // Horizontal left swipe (trash) — drag from right-centre to left-centre
                startCoord = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
                endCoord   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.5))
            } else if goBack {
                // Vertical down swipe (go back)
                startCoord = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                endCoord   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
            } else {
                // Vertical up swipe (forward)
                startCoord = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
                endCoord   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            }

            startCoord.press(forDuration: 0.05, thenDragTo: endCoord)

            // Brief pause every `pauseInterval` swipes so dwell detection fires
            // and the app gets a chance to do full-quality upgrades and memory checks
            if i % pauseInterval == 0 {
                sleep(pauseDuration)
            }

            // Log progress so you can monitor the console while it runs
            if i % logInterval == 0 {
                print("🔄 Overnight test: \(i) / \(totalSwipes) swipes complete")
            }
        }

        print("✅ Overnight stress test complete: \(totalSwipes) swipes with no crash")
    }

    // MARK: - Quick Smoke Test (30 seconds, use this for a fast sanity check)
    //
    // Run this after every significant code change to catch obvious regressions.
    // Takes about 30-45 seconds on device.

    @MainActor
    func testQuickSmoke() throws {
        let app = XCUIApplication()
        app.launch()

        sleep(3)

        let swipeCount = 500

        for i in 1...swipeCount {
            let roll = i % 100
            let swipeRight = roll < 15
            let swipeLeft  = roll >= 15 && roll < 17
            let goBack     = roll >= 17 && roll < 25

            let start: XCUICoordinate
            let end: XCUICoordinate

            if swipeRight {
                start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
                end   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.5))
            } else if swipeLeft {
                start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
                end   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.5))
            } else if goBack {
                start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                end   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
            } else {
                start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
                end   = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            }

            start.press(forDuration: 0.05, thenDragTo: end)

            if i % 50 == 0 {
                sleep(1)
                print("💨 Smoke test: \(i) / \(swipeCount)")
            }
        }

        print("✅ Smoke test passed: \(swipeCount) swipes, no crash")
    }

    // MARK: - Original template tests (kept for reference)

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
