import AppKit

@MainActor
final class GlobalEventMonitor {
    var onSelectionGestureFinished: (() -> Void)?
    var onCancellationGesture: (() -> Void)?

    private var globalMouseUpMonitor: Any?
    private var globalCancellationMonitor: Any?
    private var localMonitor: Any?

    var isRunning: Bool {
        globalMouseUpMonitor != nil
    }

    @discardableResult
    func start() -> Bool {
        stop()

        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.onSelectionGestureFinished?()
            }
        }

        globalCancellationMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.onCancellationGesture?()
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseUp, .leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]
        ) { [weak self] event in
            // Lookup panels contain interactive controls. Their clicks must not
            // be interpreted as a new selection or cancellation gesture.
            if event.window is NSPanel {
                return event
            }
            DispatchQueue.main.async {
                if event.type == .leftMouseUp {
                    self?.onSelectionGestureFinished?()
                } else {
                    self?.onCancellationGesture?()
                }
            }
            return event
        }

        return isRunning
    }

    func stop() {
        if let globalMouseUpMonitor {
            NSEvent.removeMonitor(globalMouseUpMonitor)
            self.globalMouseUpMonitor = nil
        }

        if let globalCancellationMonitor {
            NSEvent.removeMonitor(globalCancellationMonitor)
            self.globalCancellationMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    deinit {
        if let globalMouseUpMonitor {
            NSEvent.removeMonitor(globalMouseUpMonitor)
        }
        if let globalCancellationMonitor {
            NSEvent.removeMonitor(globalCancellationMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }
}
