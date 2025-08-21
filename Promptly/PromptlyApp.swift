//
//  PromptlyApp.swift
//  Promptly
//
//  Created by Bhavish Nader on 20/08/2025.
//

import SwiftUI
import AppKit
import UserNotifications

@main
struct PromptlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, StatusBarDelegate, UNUserNotificationCenterDelegate, AppSettingsDelegate {
    private var detector: AccessibilityTextDetector?
    private var statusItem: NSStatusItem?
    private var defaultIcon: NSImage?
    private var activeIcon: NSImage?
    private var loadingIcon: NSImage?
    private var loadingTimer: Timer?
    private var loadingRotation: CGFloat = 0
    
    // Display mode setting
    private var useNotifications = true // Default to notifications
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon and make app background-only
        NSApp.setActivationPolicy(.accessory)
        
        // Setup notifications
        setupNotifications()
        
        // Create status bar item
        setupStatusBar()
        
        // Set self as status bar and app settings delegate
        statusBarDelegate = self
        appSettingsDelegate = self
        
        // Initialize the detector which will handle global hotkeys
        detector = AccessibilityTextDetector()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep app running even when no windows are open
    }
    
    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        
        // Request notification permissions
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error)")
            }
        }
        
        // Define notification actions
        let copyEnhancedAction = UNNotificationAction(
            identifier: "COPY_ENHANCED_PROMPT",
            title: "Copy Enhanced Prompt",
            options: []
        )
        
        let copyOriginalAction = UNNotificationAction(
            identifier: "COPY_ORIGINAL_TEXT",
            title: "Copy Original Text", 
            options: []
        )
        
        let viewDetailsAction = UNNotificationAction(
            identifier: "VIEW_DETAILS",
            title: "View Details",
            options: []
        )
        
        // Define notification category
        let promptAnalysisCategory = UNNotificationCategory(
            identifier: "PROMPT_ANALYSIS",
            actions: [copyEnhancedAction, copyOriginalAction, viewDetailsAction],
            intentIdentifiers: [],
            options: []
        )
        
        center.setNotificationCategories([promptAnalysisCategory])
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let statusButton = statusItem?.button {
            // Create icons
            defaultIcon = createIcon(active: false)
            activeIcon = createIcon(active: true)
            loadingIcon = createLoadingIcon()
            
            statusButton.image = defaultIcon
            statusButton.toolTip = "Promptly - AI Prompt Analyzer\nCmd+/ to analyze text • Cmd+. to replace with enhanced prompt"
        }
        
        // Create menu
        let menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "Promptly", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let hotKeyItem = NSMenuItem(title: "Cmd+/ to analyze • Cmd+. to replace", action: nil, keyEquivalent: "")
        hotKeyItem.isEnabled = false
        menu.addItem(hotKeyItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let displayModeItem = NSMenuItem(title: useNotifications ? "Switch to Alert Mode" : "Switch to Notification Mode", action: #selector(toggleDisplayMode), keyEquivalent: "")
        displayModeItem.target = self
        menu.addItem(displayModeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let aboutItem = NSMenuItem(title: "About Promptly", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        
        let quitItem = NSMenuItem(title: "Quit Promptly", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
    }
    
    private func createIcon(active: Bool) -> NSImage {
        let icon = NSImage(size: NSSize(width: 18, height: 18))
        icon.lockFocus()
        
        // Draw a stylized "P" icon with a small sparkle
        let path = NSBezierPath()
        
        // Draw "P" shape
        path.move(to: NSPoint(x: 3, y: 4))
        path.line(to: NSPoint(x: 3, y: 15))
        path.line(to: NSPoint(x: 10, y: 15))
        path.curve(to: NSPoint(x: 13, y: 12), 
                  controlPoint1: NSPoint(x: 11.5, y: 15), 
                  controlPoint2: NSPoint(x: 13, y: 13.5))
        path.curve(to: NSPoint(x: 10, y: 9), 
                  controlPoint1: NSPoint(x: 13, y: 10.5), 
                  controlPoint2: NSPoint(x: 11.5, y: 9))
        path.line(to: NSPoint(x: 6, y: 9))
        path.line(to: NSPoint(x: 6, y: 12))
        path.line(to: NSPoint(x: 9, y: 12))
        
        if active {
            NSColor.systemBlue.setStroke()
        } else {
            NSColor.labelColor.setStroke()
        }
        path.lineWidth = 1.5
        path.stroke()
        
        // Add a small sparkle/star at top-right to indicate AI/enhancement
        let sparkle = NSBezierPath()
        sparkle.move(to: NSPoint(x: 14, y: 14))
        sparkle.line(to: NSPoint(x: 16, y: 14))
        sparkle.move(to: NSPoint(x: 15, y: 13))
        sparkle.line(to: NSPoint(x: 15, y: 15))
        sparkle.move(to: NSPoint(x: 14.5, y: 13.5))
        sparkle.line(to: NSPoint(x: 15.5, y: 14.5))
        sparkle.move(to: NSPoint(x: 15.5, y: 13.5))
        sparkle.line(to: NSPoint(x: 14.5, y: 14.5))
        
        if active {
            NSColor.systemYellow.setStroke()
        } else {
            NSColor.systemBlue.setStroke()
        }
        sparkle.lineWidth = 1.0
        sparkle.stroke()
        
        icon.unlockFocus()
        icon.isTemplate = !active
        
        return icon
    }
    
    private func createLoadingIcon() -> NSImage {
        let icon = NSImage(size: NSSize(width: 18, height: 18))
        icon.lockFocus()
        
        // Draw spinning circle
        let center = NSPoint(x: 9, y: 9)
        let radius: CGFloat = 6
        
        // Draw multiple arc segments to create spinner effect
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4 + loadingRotation
            let startAngle = angle
            let endAngle = angle + .pi / 6
            
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius, startAngle: startAngle * 180 / .pi, endAngle: endAngle * 180 / .pi)
            
            // Vary opacity to create spinning effect
            let alpha = 1.0 - (CGFloat(i) / 8.0) * 0.8
            NSColor.systemBlue.withAlphaComponent(alpha).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
        
        icon.unlockFocus()
        return icon
    }
    
    // MARK: - StatusBarDelegate
    func setStatusBarActive(_ active: Bool) {
        if let statusButton = statusItem?.button {
            statusButton.image = active ? activeIcon : defaultIcon
        }
    }
    
    func setStatusBarLoading(_ loading: Bool) {
        if loading {
            // Start loading animation
            startLoadingAnimation()
        } else {
            // Stop loading animation
            stopLoadingAnimation()
            
            // Return to default state
            if let statusButton = statusItem?.button {
                statusButton.image = defaultIcon
            }
        }
    }
    
    private func startLoadingAnimation() {
        // Stop any existing timer
        loadingTimer?.invalidate()
        
        // Start animation timer (60fps = ~16ms intervals)
        loadingTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Update rotation
            self.loadingRotation += 0.1
            if self.loadingRotation > 2 * .pi {
                self.loadingRotation = 0
            }
            
            // Recreate and update loading icon
            self.loadingIcon = self.createLoadingIcon()
            
            // Update status bar
            if let statusButton = self.statusItem?.button {
                statusButton.image = self.loadingIcon
            }
        }
    }
    
    private func stopLoadingAnimation() {
        loadingTimer?.invalidate()
        loadingTimer = nil
        loadingRotation = 0
    }
    
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "✨ Promptly"
        alert.informativeText = "AI-powered prompt analysis tool\n\nUse Cmd+/ from any app to analyze and improve your prompts with detailed scoring and enhanced suggestions."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc func toggleDisplayMode() {
        useNotifications.toggle()
        
        // Update menu item text
        if let menu = statusItem?.menu {
            for item in menu.items {
                if item.action == #selector(toggleDisplayMode) {
                    item.title = useNotifications ? "Switch to Alert Mode" : "Switch to Notification Mode"
                    break
                }
            }
        }
        
        // Show confirmation
        let mode = useNotifications ? "Notification" : "Alert"
        let alert = NSAlert()
        alert.messageText = "Display Mode Changed"
        alert.informativeText = "Prompt analysis will now be shown using \(mode) mode."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    // Method to get the current display mode setting
    func getUseNotifications() -> Bool {
        return useNotifications
    }
    
    @objc func quitApp() {
        NSApp.terminate(self)
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        let originalText = userInfo["originalText"] as? String ?? ""
        let enhancedPrompt = userInfo["enhancedPrompt"] as? String ?? ""
        
        switch response.actionIdentifier {
        case "COPY_ENHANCED_PROMPT":
            await MainActor.run {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(enhancedPrompt, forType: .string)
            }
            
        case "COPY_ORIGINAL_TEXT":
            await MainActor.run {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(originalText, forType: .string)
            }
            
        case "VIEW_DETAILS":
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "✨ Enhanced Prompt"
                alert.informativeText = enhancedPrompt
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Copy Enhanced Prompt")
                alert.addButton(withTitle: "Copy Original Text")
                alert.addButton(withTitle: "Close")
                
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(enhancedPrompt, forType: .string)
                } else if response == .alertSecondButtonReturn {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(originalText, forType: .string)
                }
            }
            
        default:
            break
        }
    }
}
