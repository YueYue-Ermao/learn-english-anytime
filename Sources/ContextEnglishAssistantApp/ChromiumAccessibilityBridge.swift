import AppKit
import ApplicationServices

@MainActor
final class ChromiumAccessibilityBridge {
    private struct EnabledTarget {
        let application: NSRunningApplication
        let manualAccessibilityEnabled: Bool
        let enhancedUserInterfaceEnabled: Bool
    }

    private var enabledTargets: [pid_t: EnabledTarget] = [:]

    func enableIfNeeded(for application: NSRunningApplication) -> Bool {
        guard AXIsProcessTrusted(),
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              isChromiumFamily(application),
              enabledTargets[application.processIdentifier] == nil else {
            return false
        }

        let element = AXUIElementCreateApplication(application.processIdentifier)

        // Querying the role is itself a Chromium-supported signal that an
        // assistive technology is present.
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)

        let manualResult = AXUIElementSetAttributeValue(
            element,
            "AXManualAccessibility" as CFString,
            kCFBooleanTrue
        )
        let enhancedResult = AXUIElementSetAttributeValue(
            element,
            "AXEnhancedUserInterface" as CFString,
            kCFBooleanTrue
        )

        let target = EnabledTarget(
            application: application,
            manualAccessibilityEnabled: manualResult == .success,
            enhancedUserInterfaceEnabled: enhancedResult == .success
        )
        guard target.manualAccessibilityEnabled || target.enhancedUserInterfaceEnabled else {
            return false
        }

        enabledTargets[application.processIdentifier] = target
        return true
    }

    func restoreAll() {
        for (processIdentifier, target) in enabledTargets {
            guard !target.application.isTerminated else { continue }
            let element = AXUIElementCreateApplication(processIdentifier)

            if target.manualAccessibilityEnabled {
                AXUIElementSetAttributeValue(
                    element,
                    "AXManualAccessibility" as CFString,
                    kCFBooleanFalse
                )
            }
            if target.enhancedUserInterfaceEnabled {
                AXUIElementSetAttributeValue(
                    element,
                    "AXEnhancedUserInterface" as CFString,
                    kCFBooleanFalse
                )
            }
        }
        enabledTargets.removeAll()
    }

    private func isChromiumFamily(_ application: NSRunningApplication) -> Bool {
        let identifier = application.bundleIdentifier?.lowercased() ?? ""
        let name = application.localizedName?.lowercased() ?? ""
        let knownIdentifierFragments = [
            "chrome",
            "chromium",
            "electron",
            "edgemac",
            "brave",
            "vivaldi",
            "operasoftware",
            "thebrowser",
            "openai.codex",
            "visual-studio-code"
        ]

        return knownIdentifierFragments.contains(where: identifier.contains)
            || name == "codex"
            || name == "chatgpt"
    }
}
