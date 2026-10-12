import AppKit
import ApplicationServices
import ContextEnglishCore

enum SelectionReadError: LocalizedError {
    case accessibilityPermissionMissing
    case focusedApplicationUnavailable
    case selectionUnavailable

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "辅助功能权限未开启"
        case .focusedApplicationUnavailable:
            return "无法识别当前目标应用"
        case .selectionUnavailable:
            return "目标应用没有通过辅助功能接口返回选中文字"
        }
    }
}

struct AccessibilitySelectionReader {
    private struct ResolvedSelection {
        let text: String
        let element: AXUIElement
        let range: CFTypeRef?
        let usesTextMarkers: Bool
    }

    func readCurrentSelection() throws -> SelectionSnapshot {
        guard AXIsProcessTrusted() else {
            throw SelectionReadError.accessibilityPermissionMissing
        }

        let systemWide = AXUIElementCreateSystemWide()
        guard let focusedApplication = elementAttribute(
            systemWide,
            attribute: kAXFocusedApplicationAttribute as CFString
        ) else {
            throw SelectionReadError.focusedApplicationUnavailable
        }

        let focusedElement = elementAttribute(
            focusedApplication,
            attribute: kAXFocusedUIElementAttribute as CFString
        )

        var candidates: [AXUIElement] = []
        if let focusedElement {
            candidates.append(contentsOf: elementAndAncestors(startingAt: focusedElement))
        }
        if let hitElement = elementAtCurrentPointer(in: systemWide) {
            candidates.append(contentsOf: elementAndAncestors(startingAt: hitElement))
        }

        guard let selection = candidates.lazy.compactMap(resolveSelection(from:)).first else {
            throw SelectionReadError.selectionUnavailable
        }

        let accessibilityBounds = selectedTextBounds(for: selection)
        let appKitBounds = accessibilityBounds.flatMap(
            ScreenCoordinateConverter.appKitRect(fromAccessibilityRect:)
        )

        var processIdentifier: pid_t = 0
        AXUIElementGetPid(focusedApplication, &processIdentifier)
        let applicationID = NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
        let context = textContext(for: selection)

        return SelectionSnapshot(
            text: selection.text,
            bounds: appKitBounds,
            source: .macOSAccessibility,
            sourceApplicationID: applicationID,
            surfaceKind: surfaceKind(for: selection.element),
            context: context
        )
    }

    private func textContext(for selection: ResolvedSelection) -> SelectionTextContext? {
        if !selection.usesTextMarkers,
           let rangeReference = selection.range,
           CFGetTypeID(rangeReference) == AXValueGetTypeID() {
            let rangeValue = unsafeBitCast(rangeReference, to: AXValue.self)
            var selectedRange = CFRange()
            if AXValueGetType(rangeValue) == .cfRange,
               AXValueGetValue(rangeValue, .cfRange, &selectedRange),
               selectedRange.location >= 0,
               selectedRange.length > 0,
               let fullText = accessibleText(from: selection.element),
               fullText.utf16.count <= 200_000 {
                let nsRange = NSRange(location: selectedRange.location, length: selectedRange.length)
                if NSMaxRange(nsRange) <= fullText.utf16.count {
                    let selectedFromValue = (fullText as NSString)
                        .substring(with: nsRange)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if selectedFromValue == selection.text {
                        return SentenceContextExtractor.extract(
                            from: fullText,
                            selectedRangeUTF16: nsRange
                        )
                    }
                }
            }
        }

        if selection.usesTextMarkers,
           let markerContext = textMarkerSentenceContext(for: selection) {
            return markerContext
        }

        // Chromium/WebKit text-marker selections do not consistently expose a
        // numeric range. Only accept a unique local occurrence so that the app
        // never associates the selected word with the wrong sentence.
        for element in elementAndAncestors(startingAt: selection.element) {
            guard let fullText = accessibleText(from: element),
                  fullText.utf16.count <= 200_000 else { continue }
            if let context = SentenceContextExtractor.extractUniqueOccurrence(
                of: selection.text,
                from: fullText
            ) {
                return context
            }
        }
        return nil
    }

    private func textMarkerSentenceContext(
        for selection: ResolvedSelection
    ) -> SelectionTextContext? {
        guard let markerRange = selection.range,
              let startMarker = parameterizedValue(
                from: selection.element,
                attribute: "AXStartTextMarkerForTextMarkerRange",
                parameter: markerRange
              ),
              let sentenceRange = parameterizedValue(
                from: selection.element,
                attribute: "AXSentenceTextMarkerRangeForTextMarker",
                parameter: startMarker
              ),
              let sentenceReference = parameterizedValue(
                from: selection.element,
                attribute: "AXStringForTextMarkerRange",
                parameter: sentenceRange
              ),
              let sentence = sentenceReference as? String else {
            return nil
        }

        return SentenceContextExtractor.extractUniqueOccurrence(
            of: selection.text,
            from: sentence
        )
    }

    private func parameterizedValue(
        from element: AXUIElement,
        attribute: String,
        parameter: CFTypeRef
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            attribute as CFString,
            parameter,
            &value
        ) == .success else {
            return nil
        }
        return value
    }

    private func accessibleText(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        ) == .success, let value else {
            return nil
        }
        if let string = value as? String {
            return string
        }
        if let attributedString = value as? NSAttributedString {
            return attributedString.string
        }
        return nil
    }

    private func resolveSelection(from element: AXUIElement) -> ResolvedSelection? {
        if let selectedText: String = attribute(
            element,
            attribute: kAXSelectedTextAttribute as CFString
        ) {
            let normalized = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                let range: AXValue? = attribute(
                    element,
                    attribute: kAXSelectedTextRangeAttribute as CFString
                )
                return ResolvedSelection(
                    text: normalized,
                    element: element,
                    range: range,
                    usesTextMarkers: false
                )
            }
        }

        let markerRangeAttribute = "AXSelectedTextMarkerRange" as CFString
        let stringForMarkerRangeAttribute = "AXStringForTextMarkerRange" as CFString
        var markerRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            markerRangeAttribute,
            &markerRange
        ) == .success, let markerRange else {
            return nil
        }

        var textReference: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            stringForMarkerRangeAttribute,
            markerRange,
            &textReference
        ) == .success,
        let text = textReference as? String else {
            return nil
        }

        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return ResolvedSelection(
            text: normalized,
            element: element,
            range: markerRange,
            usesTextMarkers: true
        )
    }

    private func selectedTextBounds(for selection: ResolvedSelection) -> CGRect? {
        guard let range = selection.range else { return nil }

        let boundsAttribute: CFString = selection.usesTextMarkers
            ? "AXBoundsForTextMarkerRange" as CFString
            : kAXBoundsForRangeParameterizedAttribute as CFString

        var boundsReference: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            selection.element,
            boundsAttribute,
            range,
            &boundsReference
        )

        guard result == .success,
              let boundsReference,
              CFGetTypeID(boundsReference) == AXValueGetTypeID() else {
            return nil
        }

        let boundsValue = unsafeBitCast(boundsReference, to: AXValue.self)
        guard AXValueGetType(boundsValue) == .cgRect else { return nil }

        var bounds = CGRect.zero
        guard AXValueGetValue(boundsValue, .cgRect, &bounds) else {
            return nil
        }
        return bounds
    }

    private func elementAndAncestors(startingAt element: AXUIElement) -> [AXUIElement] {
        var elements: [AXUIElement] = []
        var current: AXUIElement? = element

        for _ in 0..<10 {
            guard let currentElement = current else { break }
            elements.append(currentElement)
            current = elementAttribute(
                currentElement,
                attribute: kAXParentAttribute as CFString
            )
        }
        return elements
    }

    private func elementAtCurrentPointer(in systemWide: AXUIElement) -> AXUIElement? {
        guard let location = CGEvent(source: nil)?.location else { return nil }
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide,
            Float(location.x),
            Float(location.y),
            &element
        ) == .success else {
            return nil
        }
        return element
    }

    private func surfaceKind(for element: AXUIElement) -> SurfaceKind {
        var isSettable = DarwinBoolean(false)
        if AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &isSettable
        ) == .success, isSettable.boolValue {
            return .editable
        }

        guard let role: String = attribute(element, attribute: kAXRoleAttribute as CFString) else {
            return .unknown
        }

        if [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String
        ].contains(role) {
            return .editable
        }

        if role == kAXStaticTextRole as String {
            return .readOnly
        }
        return .unknown
    }

    private func elementAttribute(
        _ element: AXUIElement,
        attribute: CFString
    ) -> AXUIElement? {
        self.attribute(element, attribute: attribute)
    }

    private func attribute<T>(
        _ element: AXUIElement,
        attribute: CFString
    ) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? T
    }
}
