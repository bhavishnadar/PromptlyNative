//
//  PromptlyApp.swift
//  Promptly
//
//  Created by Bhavish Nader on 20/08/2025.
//

import SwiftUI
import AppKit

@main
struct PromptlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, StatusBarDelegate {
    private var detector: AccessibilityTextDetector?
    private var statusItem: NSStatusItem?
    private var defaultIcon: NSImage?
    private var activeIcon: NSImage?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon and make app background-only
        NSApp.setActivationPolicy(.accessory)
        
        // Create status bar item
        setupStatusBar()
        
        // Set self as status bar delegate
        statusBarDelegate = self
        
        // Initialize the detector which will handle global hotkeys
        detector = AccessibilityTextDetector()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep app running even when no windows are open
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let statusButton = statusItem?.button {
            // Create default icon
            defaultIcon = createIcon(active: false)
            activeIcon = createIcon(active: true)
            
            statusButton.image = defaultIcon
            statusButton.toolTip = "Promptly - AI Prompt Analyzer (Cmd+/ to analyze text)"
        }
        
        // Create menu
        let menu = NSMenu()
        
        let titleItem = NSMenuItem(title: "Promptly", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let hotKeyItem = NSMenuItem(title: "Press Cmd+/ to analyze text", action: nil, keyEquivalent: "")
        hotKeyItem.isEnabled = false
        menu.addItem(hotKeyItem)
        
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
    
    // MARK: - StatusBarDelegate
    func setStatusBarActive(_ active: Bool) {
        if let statusButton = statusItem?.button {
            statusButton.image = active ? activeIcon : defaultIcon
        }
    }
    
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "✨ Promptly"
        alert.informativeText = "AI-powered prompt analysis tool\n\nUse Cmd+/ from any app to analyze and improve your prompts with detailed scoring and enhanced suggestions."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc func quitApp() {
        NSApp.terminate(self)
    }
}
