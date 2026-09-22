import AppKit
import CoreGraphics

/// Detects whether a full-screen application window is active on a given display.
enum FullScreenDetector {
    typealias Window = (pid: pid_t, layer: Int, bounds: CGRect)
    @MainActor private static let windowCache = WindowCache()

    /// One bounded background request shared by all monitors. A stalled
    /// WindowServer must neither block AppKit nor accumulate queued work.
    @MainActor
    final class WindowCache {
        private let query: @Sendable () -> [Window]?
        private let queue = DispatchQueue(label: "codenotch.full-screen", qos: .utility)
        private var windows: [Window]?
        private var requestedAt: Date?
        private var receivedAt: Date?
        private(set) var isQueryInFlight = false
        static let refreshInterval: TimeInterval = 2
        static let maximumAge: TimeInterval = 5

        init(query: @escaping @Sendable () -> [Window]? = FullScreenDetector.queryWindows) {
            self.query = query
        }

        func reading(now: Date = Date()) -> [Window]? {
            if !isQueryInFlight && now.timeIntervalSince(requestedAt ?? .distantPast) >= Self.refreshInterval {
                isQueryInFlight = true
                requestedAt = now
                let started = Date()
                let query = self.query
                queue.async { [weak self] in
                    let result = query()
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.isQueryInFlight = false
                        let finished = Date()
                        // A delayed reply describes an old desktop. Leave the
                        // bar visible instead of folding it from stale data.
                        self.windows = finished.timeIntervalSince(started) <= Self.maximumAge ? result : nil
                        self.receivedAt = finished
                    }
                }
            }
            guard let receivedAt, now.timeIntervalSince(receivedAt) <= Self.maximumAge else { return nil }
            return windows
        }
    }

    private static func queryWindows() -> [Window]? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return list.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return nil }
            return (pid, layer, bounds)
        }
    }

    /// Pure function checking whether any layer 0 window belonging to `frontmostPID`
    /// matches or spans the `screenBounds`.
    static func isFullScreen(
        screenBounds: CGRect,
        frontmostPID: pid_t,
        windows: [(pid: pid_t, layer: Int, bounds: CGRect)],
        safeAreaTopInset: CGFloat = 0
    ) -> Bool {
        for window in windows {
            guard window.pid == frontmostPID, window.layer == 0 else { continue }
            let b = window.bounds

            // Must match screen width (within small tolerance for window borders/rounding)
            guard abs(b.origin.x - screenBounds.origin.x) <= 4,
                  abs(b.width - screenBounds.width) <= 4 else {
                continue
            }

            // Case 1: Spans full screen height (e.g. video, game, or non-notched screen with hidden menu bar)
            if abs(b.origin.y - screenBounds.origin.y) <= 4 &&
               abs(b.height - screenBounds.height) <= 4 {
                return true
            }

            // Case 2: Full-screen window on a notched MacBook or with menu bar present.
            // Starts right below notch/menu bar, reaches bottom of screen,
            // and occupies the available display area.
            let maxTopInset = max(safeAreaTopInset, 40.0) + 4.0
            let reachesBottom = abs(b.maxY - screenBounds.maxY) <= 4
            let startsNearTop = b.origin.y >= screenBounds.origin.y - 4 &&
                                b.origin.y <= screenBounds.origin.y + maxTopInset
            let occupiesMainArea = b.height >= screenBounds.height - (maxTopInset + 10)

            if reachesBottom && startsNearTop && occupiesMainArea {
                return true
            }
        }
        return false
    }

    /// Uses a shared background WindowServer snapshot and main-thread AppKit
    /// metadata. It never waits for the window list on the UI thread.
    @MainActor
    static func isFullScreenAppFrontmost(on screen: NSScreen? = NSScreen.main) -> Bool {
        guard let screen = screen ?? NSScreen.main else { return false }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }

        // Ignore Codenotch itself (settings panel, etc.)
        guard frontApp.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }

        // Convert NSScreen (AppKit coordinates: origin bottom-left of primary screen)
        // to CoreGraphics coordinates (origin top-left of primary screen).
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let cgScreenBounds = CGRect(
            x: screen.frame.minX,
            y: primaryHeight - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )

        let safeTop: CGFloat
        if #available(macOS 12.0, *) {
            safeTop = screen.safeAreaInsets.top
        } else {
            safeTop = 0
        }

        if let extractedWindows = windowCache.reading() {
            if isFullScreen(
                screenBounds: cgScreenBounds,
                frontmostPID: frontApp.processIdentifier,
                windows: extractedWindows,
                safeAreaTopInset: safeTop
            ) {
                return true
            }
        }

        // Supplementary check: on a full-screen Space without camera notch,
        // macOS autohides the menu bar, causing visibleFrame to match the entire screen frame.
        if abs(screen.visibleFrame.width - screen.frame.width) <= 1 &&
           abs(screen.visibleFrame.height - screen.frame.height) <= 1 &&
           frontApp.bundleIdentifier != "com.apple.finder" {
            return true
        }

        return false
    }
}
