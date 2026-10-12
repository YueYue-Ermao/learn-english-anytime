import AppKit
import ContextEnglishCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let permissionManager = AccessibilityPermissionManager()
    private let pauseManager = PauseManager()
    private let settings = AppSettings()
    private let speechService = SpeechService()
    private let eventMonitor = GlobalEventMonitor()
    private let panelController = LookupPanelController()
    private let setupWindowController = SetupWindowController()
    private lazy var serviceSettingsWindowController = ServiceSettingsWindowController(settings: settings)
    private let chromiumAccessibilityBridge = ChromiumAccessibilityBridge()

    private var coordinator: SelectionCoordinator?
    private var favoritesRepository: FavoritesRepository?
    private var localTranslationService: LocalTranslationProviding?
    private var learningCenterWindowController: LearningCenterWindowController?
    private var expressionWindowController: ExpressionWindowController?
    private var statusBarController: StatusBarController?
    private var permissionPollTimer: Timer?
    private var lastPermissionState: Bool?
    private var applicationActivationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = NSApplication.shared.setActivationPolicy(.regular)

        let dictionary: DictionaryProviding
        if let offlineDictionary = try? SQLiteDictionary.bundled() {
            dictionary = offlineDictionary
        } else {
            dictionary = PrototypeDictionary()
            updateDiagnostic("离线词典加载失败，已使用原型词典")
        }

        let favorites: FavoritesRepository
        do {
            let store = try UserDataStore.openDefault()
            favorites = store
            favoritesRepository = store
        } catch {
            let fallback = InMemoryFavoritesRepository()
            favorites = fallback
            favoritesRepository = fallback
            updateDiagnostic("收藏数据库初始化失败，本次运行暂存内存：\(error.localizedDescription)")
        }

        let translationService = ContextualTranslationClient(settings: settings)
        let grammarService = GrammarQuestionClient(settings: settings)
        let localTranslationService: LocalTranslationProviding?
        if #available(macOS 15.0, *) {
            let service = AppleLocalTranslationService()
            panelController.installTranslationHost(service.hostView)
            localTranslationService = service
            self.localTranslationService = service
        } else {
            localTranslationService = nil
        }
        let expressionWindow = ExpressionWindowController(
            translationService: translationService,
            favorites: favorites
        )
        expressionWindow.onSpeak = { [weak self] text, locale in
            self?.speechService.speak(text, locale: locale)
        }
        expressionWindow.onOpenServiceSettings = { [weak self] in
            self?.serviceSettingsWindowController.present()
        }
        expressionWindowController = expressionWindow

        let learningCenter = LearningCenterWindowController(
            repository: favorites,
            grammarService: grammarService
        )
        learningCenter.onSpeak = { [weak self] text, locale in
            self?.speechService.speak(text, locale: locale)
        }
        learningCenter.onOpenServiceSettings = { [weak self] in
            self?.serviceSettingsWindowController.present()
        }
        learningCenter.onOpenExpressionComposer = { [weak expressionWindow] in
            expressionWindow?.present()
        }
        learningCenter.onOpenSetup = { [weak self] in
            self?.showSetupWindow()
        }
        learningCenterWindowController = learningCenter
        configureApplicationMenu()

        let coordinator = SelectionCoordinator(
            selectionReader: AccessibilitySelectionReader(),
            triggerPolicy: TriggerPolicy(),
            pauseManager: pauseManager,
            dictionary: dictionary,
            panelController: panelController,
            settings: settings,
            favorites: favorites,
            localTranslationService: localTranslationService,
            translationService: translationService
        )
        self.coordinator = coordinator

        panelController.onSpeak = { [weak self] text, locale in
            self?.speechService.speak(text, locale: locale)
        }
        coordinator.onPauseChanged = { [weak self] in
            self?.refreshStatus()
        }
        coordinator.onDiagnosticChanged = { [weak self] message in
            self?.updateDiagnostic(message)
        }
        coordinator.onDirectDisplayChanged = { [weak self] _ in
            self?.refreshStatus()
        }

        eventMonitor.onSelectionGestureFinished = { [weak self, weak coordinator] in
            self?.updateDiagnostic("已收到鼠标松开事件")
            coordinator?.selectionGestureFinished()
        }
        eventMonitor.onCancellationGesture = { [weak coordinator] in
            coordinator?.cancellationGestureDetected()
        }

        let status = StatusBarController()
        status.onOpenLearningCenter = { [weak learningCenter] section in
            learningCenter?.present(section: section)
        }
        status.onRequestPermission = { [weak self] in
            self?.requestPermissionAndOpenSettings()
        }
        status.onOpenSetup = { [weak self] in
            self?.showSetupWindow()
        }
        status.onPause = { [weak coordinator] duration in
            coordinator?.pauseGlobally(for: duration)
        }
        status.onResume = { [weak coordinator] in
            coordinator?.resumeGlobally()
        }
        status.onShowDemo = { [weak coordinator] in
            coordinator?.showPrototypeDemo()
        }
        status.onDirectDisplayChanged = { [weak coordinator] enabled in
            coordinator?.setDirectDisplayEnabled(enabled)
        }
        status.onOpenWordbook = { [weak learningCenter] in
            learningCenter?.present(section: .words)
        }
        status.onOpenServiceSettings = { [weak self] in
            self?.serviceSettingsWindowController.present()
        }
        status.onOpenExpressionComposer = { [weak expressionWindow] in
            expressionWindow?.present()
        }
        status.onRefreshRequested = { [weak self] in
            self?.refreshStatus()
        }
        statusBarController = status

        setupWindowController.onRequestPermission = { [weak self] in
            self?.requestPermissionAndOpenSettings()
        }
        setupWindowController.onRefresh = { [weak self] in
            self?.refreshStatus()
        }
        setupWindowController.onShowDemo = { [weak coordinator] in
            coordinator?.showPrototypeDemo()
        }
        setupWindowController.onDismiss = { [weak self] in
            self?.setupWindowController.dismissToMenuBar()
        }

        refreshStatus()
        learningCenter.present()

        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatus()
            }
        }

        applicationActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
            Task { @MainActor in
                self?.enableChromiumCompatibilityIfNeeded(for: application)
            }
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        learningCenterWindowController?.present(section: .words)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventMonitor.stop()
        permissionPollTimer?.invalidate()
        if let applicationActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationActivationObserver)
        }
        chromiumAccessibilityBridge.restoreAll()
        speechService.stop()
    }

    private func refreshStatus() {
        let pausedUntil = pauseManager.activePause(for: .global)?.pausedUntil
        let isTrusted = permissionManager.isTrusted

        if isTrusted, !eventMonitor.isRunning {
            let started = eventMonitor.start()
            updateDiagnostic(started ? "监听器已启动，等待跨应用选区" : "监听器创建失败")
        } else if !isTrusted, eventMonitor.isRunning {
            eventMonitor.stop()
            updateDiagnostic("等待辅助功能权限")
        } else if lastPermissionState == false, isTrusted {
            eventMonitor.stop()
            let started = eventMonitor.start()
            updateDiagnostic(started ? "权限已生效，监听器已重新启动" : "权限已生效，但监听器创建失败")
        }
        lastPermissionState = isTrusted

        if isTrusted, let frontmostApplication = NSWorkspace.shared.frontmostApplication {
            enableChromiumCompatibilityIfNeeded(for: frontmostApplication)
        }

        statusBarController?.update(
            isTrusted: isTrusted,
            pausedUntil: pausedUntil,
            directDisplayEnabled: settings.directDisplayEnabled
        )
        setupWindowController.updatePermissionStatus(isTrusted: isTrusted)
    }

    private func requestPermissionAndOpenSettings() {
        _ = permissionManager.requestIfNeeded()
        permissionManager.openSystemSettings()
        refreshStatus()
    }

    private func showSetupWindow() {
        refreshStatus()
        setupWindowController.present(isTrusted: permissionManager.isTrusted)
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Context English Assistant")
        appMenuItem.submenu = appMenu

        let openCenter = NSMenuItem(
            title: "打开学习中心",
            action: #selector(openLearningCenterFromApplicationMenu),
            keyEquivalent: "l"
        )
        openCenter.target = self
        appMenu.addItem(openCenter)
        appMenu.addItem(.separator())

        let quit = NSMenuItem(
            title: "退出 Context English Assistant",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quit)

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc private func openLearningCenterFromApplicationMenu() {
        learningCenterWindowController?.present(section: .words)
    }

    private func updateDiagnostic(_ message: String) {
        statusBarController?.updateDiagnostic(message)
        setupWindowController.updateDiagnostic(message)
    }

    private func enableChromiumCompatibilityIfNeeded(for application: NSRunningApplication) {
        if chromiumAccessibilityBridge.enableIfNeeded(for: application) {
            let name = application.localizedName ?? "当前应用"
            updateDiagnostic("已为 \(name) 开启 Chromium/Electron 选区兼容层")
        }
    }
}
