//
//  ContentView.swift
//  Promptly
//
//  Created by Bhavish Nader on 20/08/2025.
//

import SwiftUI
import ApplicationServices
import Carbon

// JSON Response structures
struct ScoreResponse: Codable {
    let score: ScoreData
    let improve: ImproveData
}

struct ScoreData: Codable {
    let specificity: Int
    let context: Int
    let clarity: Int
    let structure: Int
    let key_issues: [String]
    let overall: Int
}

struct ImproveData: Codable {
    let prompt: String
    let original_score: Int
    let improved_score: Int
    let improvement: Int
}

// Global reference for Carbon hotkey callback
var globalDetector: AccessibilityTextDetector?
var statusBarDelegate: StatusBarDelegate?

protocol StatusBarDelegate: AnyObject {
    func setStatusBarActive(_ active: Bool)
}

// Beautiful toast notification system
class SuggestionOverlay {
    static func show(_ text: String, at position: NSPoint) {
        // Send API request and show toast notification
        sendTextToAPI(text) { response in
            DispatchQueue.main.async {
                showToastNotification(originalText: text, apiResponse: response, at: position)
            }
        }
    }
    
    private static func sendTextToAPI(_ text: String, completion: @escaping (String) -> Void) {
        guard let url = URL(string: "http://localhost:4200/score") else {
            completion("Error: Invalid API URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = ["text": text]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                var responseMessage = ""
                
                if error != nil {
                    responseMessage = "Connection failed"
                } else if response is HTTPURLResponse {
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        responseMessage = responseString
                    } else {
                        responseMessage = "No response data"
                    }
                } else {
                    responseMessage = "Unknown response"
                }
                
                completion(responseMessage)
            }
            
            task.resume()
        } catch {
            completion("Failed to send request")
        }
    }
    
    private static func showToastNotification(originalText: String, apiResponse: String, at position: NSPoint) {
        // Parse JSON and show formatted alert
        var scoreData: ScoreResponse?
        if let data = apiResponse.data(using: .utf8) {
            scoreData = try? JSONDecoder().decode(ScoreResponse.self, from: data)
        }
        
        let alert = NSAlert()
        alert.alertStyle = .informational
        
        if let scores = scoreData {
            // Format the score data nicely
            let overallScore = scores.score.overall
            let icon = getScoreIcon(for: overallScore)
            let key_issues = scores.score.key_issues
            
            alert.messageText = "\(icon) Prompt Quality Score: \(overallScore)/100"
            
            var details = "📊 Detailed Scores:\n"
            details += "   • Specificity: \(scores.score.specificity)\n"
            details += "   • Context: \(scores.score.context)\n"
            details += "   • Clarity: \(scores.score.clarity)\n"
            details += "   • Structure: \(scores.score.structure)\n"
            
            if scores.improve.improvement > 0 {
                details += "\n🚀 Improvement: +\(scores.improve.improvement) points (\(scores.improve.original_score) → \(scores.improve.improved_score))"
            }
            
            // Add key issues
            if !key_issues.isEmpty {
                details += "\n\n🔍 Key Issues:"
                for (index, issue) in key_issues.enumerated() {
                    details += "\n   \(index + 1). \(issue)"
                }
            }
            
            // Mention enhanced prompt availability
            details += "\n\n✨ Enhanced prompt available"
            
            alert.informativeText = details
        } else {
            alert.messageText = "⚡ Promptly Analysis"
            alert.informativeText = apiResponse.prefix(300) + (apiResponse.count > 300 ? "..." : "")
        }
        
        if let scores = scoreData {
            alert.addButton(withTitle: "Copy Enhanced Prompt")
            alert.addButton(withTitle: "Copy Original Text")
            alert.addButton(withTitle: "Show Enhanced Prompt")
            alert.addButton(withTitle: "Close")
            
            let response = alert.runModal()
            
            if response == .alertFirstButtonReturn {
                // Copy Enhanced Prompt
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(scores.improve.prompt, forType: .string)
                
            } else if response == .alertSecondButtonReturn {
                // Copy Original Text
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(originalText, forType: .string)
                
            } else if response == .alertThirdButtonReturn {
                // Show Enhanced Prompt in detail
                showEnhancedPromptDetail(enhanced_prompt: scores.improve.prompt, originalText: originalText)
            }
        } else {
            alert.addButton(withTitle: "Copy Original Text")
            alert.addButton(withTitle: "Close")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(originalText, forType: .string)
            }
        }
    }
    
    private static func showEnhancedPromptDetail(enhanced_prompt: String, originalText: String) {
        let detailAlert = NSAlert()
        detailAlert.messageText = "✨ Enhanced Prompt"
        detailAlert.informativeText = enhanced_prompt
        detailAlert.alertStyle = .informational
        
        detailAlert.addButton(withTitle: "Copy Enhanced Prompt")
        detailAlert.addButton(withTitle: "Copy Original Text") 
        detailAlert.addButton(withTitle: "Close")
        
        let response = detailAlert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Copy Enhanced Prompt
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(enhanced_prompt, forType: .string)
            
        } else if response == .alertSecondButtonReturn {
            // Copy Original Text
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(originalText, forType: .string)
        }
    }
    
    private static func getScoreIcon(for score: Int) -> String {
        if score >= 50 {
            return "✅"
        } else if score >= 10 {
            return "⚠️"
        } else {
            return "❌"
        }
    }
}

class AccessibilityTextDetector {
    private var hotKeyRef: EventHotKeyRef?
    
    init() {
        globalDetector = self
        checkAccessibilityPermissions()
        setupGlobalKeyboardShortcut()
    }
    
    private func checkAccessibilityPermissions() {
        let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options = [checkOptPrompt: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !accessEnabled {
            print("Accessibility access not granted. Please enable in System Settings.")
        } else {
            print("Accessibility access granted.")
        }
    }
    
    deinit {
        unregisterHotKey()
        globalDetector = nil
    }
    
    private func setupGlobalKeyboardShortcut() {
        registerHotKey()
    }
    
    private func registerHotKey() {
        // Define the hotkey: Cmd+/
        let hotKeyID = EventHotKeyID(signature: FourCharCode(0x68746b31), id: 1)
        
        // Install event handler
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        let callback: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
            globalDetector?.detectTextFromFrontmostApp()
            return noErr
        }
        
        var eventHandler: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, nil, &eventHandler)
        
        if status == noErr {
            // Register the hotkey: Cmd+/ (key code 44)
            var hotKeyRef: EventHotKeyRef?
            let result = RegisterEventHotKey(44, UInt32(cmdKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
            
            if result == noErr {
                self.hotKeyRef = hotKeyRef
                print("Global hotkey Cmd+/ registered successfully!")
            } else {
                print("Failed to register hotkey: \(result)")
            }
        } else {
            print("Failed to install event handler: \(status)")
        }
    }
    
    private func unregisterHotKey() {
        if let hotKeyRef = self.hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
            print("Hotkey unregistered")
        }
    }
    
    private func showPopupNearCursor(with text: String) {
        let mouseLocation = NSEvent.mouseLocation
        SuggestionOverlay.show(text, at: mouseLocation)
    }
    
    private func detectTextFromFrontmostApp() {
        // Notify status bar that detection is active
        DispatchQueue.main.async {
            statusBarDelegate?.setStatusBarActive(true)
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.performTextDetection()
            
            // Reset status bar after detection
            DispatchQueue.main.async {
                statusBarDelegate?.setStatusBarActive(false)
            }
        }
    }
    
    private func performTextDetection() {
        guard AXIsProcessTrusted() else {
            DispatchQueue.main.async {
                self.showPopupNearCursor(with: "Error: Accessibility permissions required. Please enable accessibility permissions for Promptly.")
            }
            return
        }
        
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let appName = frontmostApp?.localizedName ?? "Unknown App"
        
        if let pid = frontmostApp?.processIdentifier {
            let appRef = AXUIElementCreateApplication(pid)
            var focusedElement: CFTypeRef?
            
            if AXUIElementCopyAttributeValue(appRef, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success,
               let element = focusedElement {
                
                let axElement = element as! AXUIElement
                let extractedText = self.extractTextFromElement(axElement)
                
                DispatchQueue.main.async {
                    if !extractedText.isEmpty {
                        self.showPopupNearCursor(with: extractedText)
                    } else {
                        self.showPopupNearCursor(with: "No accessible text found in focused element")
                    }
                }
            } else {
                let allText = self.extractAllTextFromApp(appRef)
                
                DispatchQueue.main.async {
                    if !allText.isEmpty {
                        self.showPopupNearCursor(with: allText)
                    } else {
                        self.showPopupNearCursor(with: "No accessible text found in \(appName)")
                    }
                }
            }
        }
    }
    
    private func extractTextFromElement(_ element: AXUIElement) -> String {
        var texts: [String] = []
        
        if let value = getStringValue(element, attribute: kAXValueAttribute as CFString) {
            texts.append(value)
        }
        
        if let title = getStringValue(element, attribute: kAXTitleAttribute as CFString) {
            texts.append(title)
        }
        
        if let description = getStringValue(element, attribute: kAXDescriptionAttribute as CFString) {
            texts.append(description)
        }
        
        if let selectedText = getStringValue(element, attribute: kAXSelectedTextAttribute as CFString) {
            texts.append("Selected: \(selectedText)")
        }
        
        return texts.filter { !$0.isEmpty }.joined(separator: "\n")
    }
    
    private func extractAllTextFromApp(_ appElement: AXUIElement) -> String {
        var allTexts: Set<String> = []
        traverseUIElements(appElement, texts: &allTexts, depth: 0, maxDepth: 5)
        return allTexts.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                      .joined(separator: "\n")
    }
    
    private func traverseUIElements(_ element: AXUIElement, texts: inout Set<String>, depth: Int, maxDepth: Int) {
        guard depth < maxDepth else { return }
        
        if let value = getStringValue(element, attribute: kAXValueAttribute as CFString) {
            texts.insert(value)
        }
        
        if let title = getStringValue(element, attribute: kAXTitleAttribute as CFString) {
            texts.insert(title)
        }
        
        var children: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
           let childArray = children as? [AXUIElement] {
            for child in childArray.prefix(20) {
                traverseUIElements(child, texts: &texts, depth: depth + 1, maxDepth: maxDepth)
            }
        }
    }
    
    private func getStringValue(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let stringValue = value as? String,
              !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return stringValue
    }
}
