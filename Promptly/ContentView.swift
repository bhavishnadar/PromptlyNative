//
//  ContentView.swift
//  Promptly
//
//  Created by Bhavish Nader on 20/08/2025.
//

import SwiftUI
import ApplicationServices
import Carbon
import UserNotifications

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
    let original_score: Int?
    let improved_score: Int?
    let improvement: Int?
}

// Global reference for Carbon hotkey callback
var globalDetector: AccessibilityTextDetector?
var statusBarDelegate: StatusBarDelegate?

// Protocol to access app delegate settings
protocol AppSettingsDelegate: AnyObject {
    func getUseNotifications() -> Bool
}

var appSettingsDelegate: AppSettingsDelegate?

protocol StatusBarDelegate: AnyObject {
    func setStatusBarActive(_ active: Bool)
    func setStatusBarLoading(_ loading: Bool)
}

// Global state for text replacement feature
struct EnhancedPromptState {
    let enhancedPrompt: String
    let originalText: String
    let timestamp: Date
    let sourceApp: String
    let sourceElement: AXUIElement?
    
    var isValid: Bool {
        // Valid for 5 minutes after analysis
        Date().timeIntervalSince(timestamp) < 300
    }
}

var lastEnhancedPromptState: EnhancedPromptState?

// Beautiful toast notification system
class SuggestionOverlay {
    static func show(_ text: String, at position: NSPoint) {
        // Show loading indicator
        statusBarDelegate?.setStatusBarLoading(true)
        
        // Send API request and show toast notification
        sendTextToAPI(text) { response in
            DispatchQueue.main.async {
                // Hide loading indicator
                statusBarDelegate?.setStatusBarLoading(false)
                
                showToastNotification(originalText: text, apiResponse: response, at: position)
            }
        }
    }
    
    private static func sendTextToAPI(_ text: String, completion: @escaping (String) -> Void) {
        guard let url = URL(string: "https://promptly-backend-wwdj.onrender.com/score") else {
            DispatchQueue.main.async {
                statusBarDelegate?.setStatusBarLoading(false)
            }
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
            DispatchQueue.main.async {
                statusBarDelegate?.setStatusBarLoading(false)
            }
            completion("Failed to send request")
        }
    }
    
    private static func showToastNotification(originalText: String, apiResponse: String, at position: NSPoint) {
        // Check user preference for display mode
        let useNotifications = appSettingsDelegate?.getUseNotifications() ?? true
        
        if useNotifications {
            showAsNotification(originalText: originalText, apiResponse: apiResponse)
        } else {
            showAsAlert(originalText: originalText, apiResponse: apiResponse)
        }
    }
    
    private static func showAsNotification(originalText: String, apiResponse: String) {
        // Parse JSON and prepare notification
        var scoreData: ScoreResponse?
        if let data = apiResponse.data(using: .utf8) {
            scoreData = try? JSONDecoder().decode(ScoreResponse.self, from: data)
        }
        
        // Store enhanced prompt globally for replacement feature
        if let scores = scoreData {
            storeEnhancedPromptState(originalText: originalText, enhancedPrompt: scores.improve.prompt)
        }
        
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = "PROMPT_ANALYSIS"
        content.sound = .default
        
        if let scores = scoreData {
            // Format the score data nicely for notification
            let overallScore = scores.score.overall
            let icon = getScoreIcon(for: overallScore)
            let key_issues = scores.score.key_issues
            
            content.title = "\(icon) Prompt Quality Score: \(overallScore)/100"
            
            var body = "📊 Scores: Specificity \(scores.score.specificity) • Context \(scores.score.context) • Clarity \(scores.score.clarity) • Structure \(scores.score.structure)"
            
            if let improvement = scores.improve.improvement, improvement > 0 {
                body += "\n🚀 Improvement: +\(improvement) points"
            }
            
            // Add key issues (truncate if too long)
            if !key_issues.isEmpty {
                body += "\n🔍 Key Issues: \(key_issues.prefix(2).joined(separator: ", "))"
                if key_issues.count > 2 {
                    body += "..."
                }
            }
            
            // Different message based on whether improvement metrics are available
            if scores.improve.improvement != nil {
                body += "\n✨ Enhanced prompt available"
            } else {
                body += "\n💡 Feedback available"
            }
            content.body = body
            
            // Store data for actions
            content.userInfo = [
                "originalText": originalText,
                "enhancedPrompt": scores.improve.prompt,
                "hasScores": true,
                "isEnhancement": scores.improve.improvement != nil
            ]
        } else {
            content.title = "⚡ Promptly Analysis"
            content.body = String(apiResponse.prefix(200)) + (apiResponse.count > 200 ? "..." : "")
            content.userInfo = [
                "originalText": originalText,
                "enhancedPrompt": "",
                "hasScores": false
            ]
        }
        
        // Create and deliver notification
        let request = UNNotificationRequest(
            identifier: "promptly-analysis-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error delivering notification: \(error)")
                // Fallback to simple alert if notification fails
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = content.title
                    alert.informativeText = content.body
                    alert.runModal()
                }
            }
        }
    }
    
    private static func showAsAlert(originalText: String, apiResponse: String) {
        // Parse JSON and show formatted alert (traditional popup mode)
        var scoreData: ScoreResponse?
        if let data = apiResponse.data(using: .utf8) {
            scoreData = try? JSONDecoder().decode(ScoreResponse.self, from: data)
        }
        
        // Store enhanced prompt globally for replacement feature
        if let scores = scoreData {
            storeEnhancedPromptState(originalText: originalText, enhancedPrompt: scores.improve.prompt)
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
            
            if let improvement = scores.improve.improvement, 
               let originalScore = scores.improve.original_score,
               let improvedScore = scores.improve.improved_score,
               improvement > 0 {
                details += "\n🚀 Improvement: +\(improvement) points (\(originalScore) → \(improvedScore))"
            }
            
            // Add key issues
            if !key_issues.isEmpty {
                details += "\n\n🔍 Key Issues:"
                for (index, issue) in key_issues.enumerated() {
                    details += "\n   \(index + 1). \(issue)"
                }
            }
            
            // Different message based on whether improvement metrics are available
            if scores.improve.improvement != nil {
                details += "\n\n✨ Enhanced prompt available"
            } else {
                details += "\n\n💡 Feedback available"
            }
            
            alert.informativeText = details
        } else {
            alert.messageText = "⚡ Promptly Analysis"
            alert.informativeText = apiResponse.prefix(300) + (apiResponse.count > 300 ? "..." : "")
        }
        
        if let scores = scoreData {
            // Different button labels based on whether it's an enhancement or feedback
            if scores.improve.improvement != nil {
                alert.addButton(withTitle: "Copy Enhanced Prompt")
                alert.addButton(withTitle: "Copy Original Text")
                alert.addButton(withTitle: "Show Enhanced Prompt")
            } else {
                alert.addButton(withTitle: "Copy Feedback")
                alert.addButton(withTitle: "Show Feedback")
            }
            alert.addButton(withTitle: "Close")
            
            let response = alert.runModal()
            
            let isEnhancement = scores.improve.improvement != nil
            
            if response == .alertFirstButtonReturn {
                // Copy Enhanced Prompt or Feedback
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(scores.improve.prompt, forType: .string)
                
            } else if response == .alertSecondButtonReturn {
                if isEnhancement {
                    // Copy Original Text (only for enhancements)
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(originalText, forType: .string)
                } else {
                    // Show Feedback (for low-score responses)
                    showEnhancedPromptDetail(enhanced_prompt: scores.improve.prompt, originalText: originalText, isEnhancement: isEnhancement)
                }
                
            } else if response == .alertThirdButtonReturn {
                if isEnhancement {
                    // Show Enhanced Prompt in detail
                    showEnhancedPromptDetail(enhanced_prompt: scores.improve.prompt, originalText: originalText, isEnhancement: isEnhancement)
                }
                // For low-score responses, third button is "Close" - no action needed
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
    
    private static func showEnhancedPromptDetail(enhanced_prompt: String, originalText: String, isEnhancement: Bool = true) {
        let detailAlert = NSAlert()
        detailAlert.messageText = isEnhancement ? "✨ Enhanced Prompt" : "💡 AI Feedback"
        detailAlert.informativeText = enhanced_prompt
        detailAlert.alertStyle = .informational
        
        detailAlert.addButton(withTitle: isEnhancement ? "Copy Enhanced Prompt" : "Copy Feedback")
        if isEnhancement {
            detailAlert.addButton(withTitle: "Copy Original Text")
        }
        detailAlert.addButton(withTitle: "Close")
        
        let response = detailAlert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Copy Enhanced Prompt or Feedback
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(enhanced_prompt, forType: .string)
            
        } else if response == .alertSecondButtonReturn {
            if isEnhancement {
                // Copy Original Text (only available for enhancements)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(originalText, forType: .string)
            }
            // For low-score responses, second button is "Close" - no action needed
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
    
    private static func storeEnhancedPromptState(originalText: String, enhancedPrompt: String) {
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let sourceApp = frontmostApp?.localizedName ?? "Unknown App"
        
        lastEnhancedPromptState = EnhancedPromptState(
            enhancedPrompt: enhancedPrompt,
            originalText: originalText,
            timestamp: Date(),
            sourceApp: sourceApp,
            sourceElement: nil // TODO: Store focused element for precise replacement
        )
        
        print("Enhanced prompt stored for replacement. App: \(sourceApp)")
    }
}

class AccessibilityTextDetector {
    private var analyzeHotKeyRef: EventHotKeyRef?
    private var replaceHotKeyRef: EventHotKeyRef?
    
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
        // Install event handler for both hotkeys
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        let callback: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
            var hotKeyID = EventHotKeyID(signature: 0, id: 0)
            GetEventParameter(theEvent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            
            if hotKeyID.id == 1 {
                // Cmd+/ - Analyze text
                globalDetector?.detectTextFromFrontmostApp()
            } else if hotKeyID.id == 2 {
                // Cmd+. - Replace with enhanced prompt
                globalDetector?.replaceWithEnhancedPrompt()
            }
            
            return noErr
        }
        
        var eventHandler: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, nil, &eventHandler)
        
        if status == noErr {
            // Register Cmd+/ (key code 44) for analysis
            let analyzeHotKeyID = EventHotKeyID(signature: FourCharCode(0x68746b31), id: 1)
            var analyzeHotKeyRef: EventHotKeyRef?
            let analyzeResult = RegisterEventHotKey(44, UInt32(cmdKey), analyzeHotKeyID, GetApplicationEventTarget(), 0, &analyzeHotKeyRef)
            
            if analyzeResult == noErr {
                self.analyzeHotKeyRef = analyzeHotKeyRef
                print("Global hotkey Cmd+/ registered successfully!")
            } else {
                print("Failed to register Cmd+/ hotkey: \(analyzeResult)")
            }
            
            // Register Cmd+. (key code 47) for replacement
            let replaceHotKeyID = EventHotKeyID(signature: FourCharCode(0x68746b32), id: 2)
            var replaceHotKeyRef: EventHotKeyRef?
            let replaceResult = RegisterEventHotKey(47, UInt32(cmdKey), replaceHotKeyID, GetApplicationEventTarget(), 0, &replaceHotKeyRef)
            
            if replaceResult == noErr {
                self.replaceHotKeyRef = replaceHotKeyRef
                print("Global hotkey Cmd+. registered successfully!")
            } else {
                print("Failed to register Cmd+. hotkey: \(replaceResult)")
            }
        } else {
            print("Failed to install event handler: \(status)")
        }
    }
    
    private func unregisterHotKey() {
        if let analyzeHotKeyRef = self.analyzeHotKeyRef {
            UnregisterEventHotKey(analyzeHotKeyRef)
            self.analyzeHotKeyRef = nil
        }
        
        if let replaceHotKeyRef = self.replaceHotKeyRef {
            UnregisterEventHotKey(replaceHotKeyRef)
            self.replaceHotKeyRef = nil
        }
        
        print("Hotkeys unregistered")
    }
    
    private func showPopupNearCursor(with text: String) {
        let mouseLocation = NSEvent.mouseLocation
        SuggestionOverlay.show(text, at: mouseLocation)
    }
    
    private func showReplacementFeedback(with message: String) {
        // Check user preference for display mode
        let useNotifications = appSettingsDelegate?.getUseNotifications() ?? true
        
        if useNotifications {
            showReplacementAsNotification(message: message)
        } else {
            showReplacementAsAlert(message: message)
        }
    }
    
    private func showReplacementAsNotification(message: String) {
        let content = UNMutableNotificationContent()
        content.title = "✨ Promptly"
        content.body = message
        content.sound = .default
        
        // Create and deliver notification
        let request = UNNotificationRequest(
            identifier: "promptly-replacement-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error delivering replacement notification: \(error)")
                // Fallback to simple alert if notification fails
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "✨ Promptly"
                    alert.informativeText = message
                    alert.runModal()
                }
            }
        }
    }
    
    private func showReplacementAsAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "✨ Promptly"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func detectTextFromFrontmostApp() {
        // Notify status bar that detection is active
        DispatchQueue.main.async {
            statusBarDelegate?.setStatusBarActive(true)
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.performTextDetection()
            
            // Reset status bar after detection (only if no API call will follow)
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
                        self.showPopupNearCursor(with: "💡 No text selected. Please select some text and try again.\n\nTip: Highlight text in any app, then press Cmd+/ to analyze it with Promptly.")
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.showPopupNearCursor(with: "💡 Please select some text first.\n\nHighlight the text you want to analyze in \(appName), then press Cmd+/ to get AI-powered prompt suggestions.")
                }
            }
        } else {
            DispatchQueue.main.async {
                self.showPopupNearCursor(with: "💡 Please select some text first.\n\nHighlight the text you want to analyze in any app, then press Cmd+/ to get AI-powered prompt suggestions.")
            }
        }
    }
    
    private func extractTextFromElement(_ element: AXUIElement) -> String {
        // First priority: Check for selected text
        if let selectedText = getStringValue(element, attribute: kAXSelectedTextAttribute as CFString) {
            return selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Second priority: Get content of text field/area where cursor is positioned
        if let value = getStringValue(element, attribute: kAXValueAttribute as CFString) {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // No relevant text found
        return ""
    }
    
    func replaceWithEnhancedPrompt() {
        // Check if we have a valid enhanced prompt to replace with
        guard let state = lastEnhancedPromptState, state.isValid else {
            DispatchQueue.main.async {
                self.showReplacementFeedback(with: "💡 No recent enhanced prompt available.\n\nFirst analyze some text with Cmd+/, then use Cmd+. to replace it within 5 minutes.")
            }
            return
        }
        
        // Notify status bar that replacement is active
        DispatchQueue.main.async {
            statusBarDelegate?.setStatusBarActive(true)
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.performTextReplacement(with: state)
            
            // Reset status bar after replacement
            DispatchQueue.main.async {
                statusBarDelegate?.setStatusBarActive(false)
            }
        }
    }
    
    private func performTextReplacement(with state: EnhancedPromptState) {
        guard AXIsProcessTrusted() else {
            DispatchQueue.main.async {
                self.showReplacementFeedback(with: "Error: Accessibility permissions required for text replacement.")
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
                let success = replaceTextInElement(axElement, with: state.enhancedPrompt)
                
                DispatchQueue.main.async {
                    if success {
                        // Clear the stored state after successful replacement
                        lastEnhancedPromptState = nil
                        self.showReplacementFeedback(with: "✅ Text replaced with enhanced prompt!")
                    } else {
                        // Fallback: Copy to clipboard
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(state.enhancedPrompt, forType: .string)
                        self.showReplacementFeedback(with: "📋 Enhanced prompt copied to clipboard.\n\nCouldn't replace text automatically, but it's ready to paste!")
                    }
                }
            } else {
                DispatchQueue.main.async {
                    // Fallback: Copy to clipboard
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(state.enhancedPrompt, forType: .string)
                    self.showReplacementFeedback(with: "📋 Enhanced prompt copied to clipboard.\n\nNo focused text field found in \(appName), but it's ready to paste!")
                }
            }
        }
    }
    
    private func replaceTextInElement(_ element: AXUIElement, with newText: String) -> Bool {
        // First, check if there's selected text - if so, replace only the selection
        if let selectedText = getStringValue(element, attribute: kAXSelectedTextAttribute as CFString),
           !selectedText.isEmpty {
            // Try to replace selected text by setting the selected text attribute
            let newValue = newText as CFString
            let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, newValue)
            
            if result == .success {
                return true
            }
            
            // Fallback: Get current text, replace the selection manually, then set the whole value
            if let currentText = getStringValue(element, attribute: kAXValueAttribute as CFString) {
                // Get selection range to manually replace
                var selectionRange: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectionRange) == .success,
                   let range = selectionRange {
                    
                    // Extract range values
                    let rangeValue = range as! AXValue
                    var cfRange = CFRange()
                    if AXValueGetValue(rangeValue, AXValueType.cfRange, &cfRange) {
                            // Ensure the range is within bounds
                            let textLength = currentText.count
                            let location = max(0, min(cfRange.location, textLength))
                            let length = max(0, min(cfRange.length, textLength - location))
                            
                            if location >= 0 && location < textLength && length > 0 {
                                // Use NSString for safer index calculation
                                let nsString = currentText as NSString
                                let range = NSRange(location: location, length: length)
                                
                                // Replace the selected portion with the new text
                                let modifiedText = nsString.replacingCharacters(in: range, with: newText)
                                
                                // Set the modified text
                                let modifiedValue = modifiedText as CFString
                                let setResult = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, modifiedValue)
                                return setResult == .success
                            }
                    }
                }
            }
        }
        
        // Fallback: If no selection or selection replacement failed, replace entire content
        // This maintains the current behavior as a last resort
        let newValue = newText as CFString
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue)
        
        return result == .success
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
