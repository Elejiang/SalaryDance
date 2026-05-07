import Cocoa
import Combine
import SwiftUI

/// 菜单栏应用的主控制器，集中管理状态栏图标、弹窗、设置窗口入口和快捷键动作序列。
final class StatusBarController: NSObject, ObservableObject, NSPopoverDelegate {
    static let shared = StatusBarController()

    @Published private(set) var isContentMasked = false
    @Published private(set) var nextShortcutAction: ShortcutAction = ShortcutAction.defaultSequence[0]

    private let viewModel = SalaryViewModel()
    private let offTaskTracker = OffTaskTracker.shared
    private let popover = NSPopover()
    private let statusItemModel = StatusBarItemModel()
    private lazy var statusItemHostingView = NSHostingView(rootView: StatusBarItemContent(model: statusItemModel))
    private var statusItem: NSStatusItem?
    private var anchorWindow: NSWindow?
    private var lastStatusItemScreen: NSScreen?
    private var lastStatusItemFrame: NSRect?
    private var localPopoverDismissMonitor: Any?
    private var globalPopoverDismissMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false
    private var shortcutActionIndex = 0
    private var lastStatusAmountText = ""
    private var lastStatusItemWidth: CGFloat?
    private var lastStatusItemHeight: CGFloat?
    private let popoverWidth: CGFloat = 280

    private override init() {
        super.init()
    }

    /// 初始化状态栏项、弹窗内容和配置监听；App 启动后只应调用一次。
    func start() {
        guard !isStarted else { return }
        isStarted = true

        popover.behavior = .transient
        popover.delegate = self
        let popoverContentController = NSHostingController(
            rootView: PopoverView(
                viewModel: viewModel,
                statusBarController: self
            )
        )
        popoverContentController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = popoverContentController
        updatePopoverContentSize()

        viewModel.$todayEarnings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusItemTitle()
            }
            .store(in: &cancellables)

        SalaryConfigManager.shared.$config
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.viewModel.refreshNow()
                self?.updateStatusItemTitle()
                self?.updateNextShortcutAction()
                self?.updateRefreshCadence()
                self?.updatePopoverContentSize()
            }
            .store(in: &cancellables)

        offTaskTracker.$sessions
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.viewModel.refreshNow()
                self?.updateStatusItemTitle()
                self?.updateRefreshCadence()
                self?.updatePopoverContentSize()
            }
            .store(in: &cancellables)

        updateStatusItemTitle()
        updateNextShortcutAction()
        updateRefreshCadence()
    }

    /// 清理状态栏项和 Combine 订阅，主要用于 App 退出或未来测试场景。
    func stop() {
        closePopover()
        removeStatusItem()
        cancellables.removeAll()
        isStarted = false
    }

    /// App 已隐藏所有状态栏入口时，再次启动 App 用 App 图标恢复一个可点击入口。
    func revealStatusItemAppIcon() {
        if !SalaryConfigManager.shared.config.statusBarShowsAppIcon {
            SalaryConfigManager.shared.config.statusBarShowsAppIcon = true
        } else {
            updateStatusItemTitle()
        }
    }

    /// 执行用户配置的快捷键动作序列，每按一次推进到下一项。
    func handleShortcutPress() {
        let sequence = SalaryConfigManager.shared.config.resolvedShortcutActionSequence
        let action = sequence[shortcutActionIndex % sequence.count]
        shortcutActionIndex = (shortcutActionIndex + 1) % sequence.count
        updateNextShortcutAction()
        performShortcutAction(action)
    }

    func revealContent() {
        setContentMasked(false)
    }

    func hideContent() {
        setContentMasked(true)
    }

    /// 从弹窗或状态栏打开设置时先关闭弹窗，避免两个窗口层级互相遮挡。
    func showSettings() {
        closePopover()
        SettingsWindowController.shared.show()
    }

    func dismissPopover() {
        closePopover()
    }

    func quitApplication() {
        NSApp.terminate(nil)
    }

    func toggleOffTaskStatus() {
        offTaskTracker.toggle(config: SalaryConfigManager.shared.config)
        viewModel.refreshNow()
        updateStatusItemTitle()
        updateRefreshCadence()
    }

    @objc private func statusItemClicked() {
        if popover.isShown {
            closePopover()
        } else {
            let config = SalaryConfigManager.shared.config
            showPopover(masked: config.opensPrivatePopoverFromStatusItemClick, from: .statusItem)
        }
    }

    /// 将快捷键动作映射到具体行为；状态栏实时显示和弹窗打开互不共享脱敏状态。
    private func performShortcutAction(_ action: ShortcutAction) {
        switch action {
        case .showStatusBarEarnings:
            SalaryConfigManager.shared.config.statusBarShowsEarnings = true
            viewModel.refreshNow()
            updateStatusItemTitle()
            updateRefreshCadence()
        case .hideStatusBarEarnings:
            SalaryConfigManager.shared.config.statusBarShowsEarnings = false
            updateStatusItemTitle()
            updateRefreshCadence()
        case .openPrivatePopover:
            showPopover(masked: true, from: .shortcut)
        case .openPlainPopover:
            showPopover(masked: false, from: .shortcut)
        case .closePopover:
            closePopover()
        }
    }

    /// 弹窗来源会影响未来可能的定位策略，目前两种来源共用同一套兜底定位。
    private enum PopoverSource {
        case statusItem
        case shortcut
    }

    /// 打开弹窗前强制刷新一次数据，避免用户看到上一轮定时器留下的旧金额。
    private func showPopover(masked: Bool, from source: PopoverSource) {
        setContentMasked(masked)
        viewModel.refreshNow()
        updatePopoverContentSize()

        switch source {
        case .statusItem:
            if showPopoverFromStatusItem() { return }
            showPopoverFromMenuBarAnchor()
        case .shortcut:
            if showPopoverFromStatusItem() { return }
            showPopoverFromMenuBarAnchor()
        }
    }

    /// 优先从真实状态栏按钮弹出；按钮被 Hidden Bar 隐藏或不可见时返回 false 走锚点兜底。
    @discardableResult
    private func showPopoverFromStatusItem() -> Bool {
        guard let button = statusItem?.button,
              let window = button.window,
              window.isVisible,
              window.occlusionState.contains(.visible),
              !button.isHidden,
              button.alphaValue > 0.01 else {
            return false
        }

        let screenFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard screenFrame.width > 1,
              screenFrame.height > 1,
              let screen = window.screen ?? screen(for: screenFrame.midPoint),
              screenFrame.intersects(screen.menuBarBand) else {
            return false
        }

        rememberStatusItemFrame(screenFrame, on: screen)
        hideAnchorWindow()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        finishPopoverPresentation()
        return true
    }

    /// 状态栏按钮不可用时创建透明锚点窗口，尽量贴近上次可见的菜单栏位置。
    private func showPopoverFromMenuBarAnchor() {
        // Hidden Bar 等工具隐藏状态栏图标时，真实 button 不可用，用缓存位置或右上角兜底。
        let screen = fallbackPopoverScreen()
        let anchorSize = NSSize(width: 1, height: 1)
        let margin: CGFloat = 12
        let halfPopoverWidth = max(popover.contentSize.width, 280) / 2
        let maxCenterX = screen.visibleFrame.maxX - halfPopoverWidth - margin
        let minCenterX = screen.visibleFrame.minX + halfPopoverWidth + margin
        let preferredCenterX = cachedStatusItemCenterX(on: screen)
            ?? (screen.visibleFrame.maxX - halfPopoverWidth - margin)
        let centerX = min(maxCenterX, max(minCenterX, preferredCenterX))
        let menuBarBottomY = screen.visibleFrame.maxY
        let y = min(screen.frame.maxY - anchorSize.height, menuBarBottomY + 1)
        let x = centerX - anchorSize.width / 2
        let anchorFrame = NSRect(origin: NSPoint(x: x, y: y), size: anchorSize)

        let window = anchorWindow ?? NSWindow(
            contentRect: anchorFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        anchorWindow = window
        window.setFrame(anchorFrame, display: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let contentView = window.contentView ?? NSView(frame: NSRect(origin: .zero, size: anchorSize))
        contentView.frame = NSRect(origin: .zero, size: anchorSize)
        window.contentView = contentView

        window.orderFrontRegardless()
        popover.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        finishPopoverPresentation()
    }

    /// 弹窗展示完成后开启失焦关闭监听，并根据内容重新收敛高度。
    private func finishPopoverPresentation() {
        focusPopoverWindow()
        startPopoverDismissMonitoring()
        updateRefreshCadence()
        DispatchQueue.main.async { [weak self] in
            self?.focusPopoverWindow()
            self?.updatePopoverContentSize()
        }
    }

    /// 菜单栏点击打开的 `NSPopover` 有时不会立即成为 key window，SwiftUI material 会按非激活窗口绘制成发灰半透明状态。
    private func focusPopoverWindow() {
        guard popover.isShown,
              let popoverWindow = popover.contentViewController?.view.window else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        popoverWindow.makeKeyAndOrderFront(nil)
    }

    /// 关闭弹窗时恢复非脱敏状态；脱敏只属于弹窗本身，不影响状态栏金额。
    private func closePopover() {
        stopPopoverDismissMonitoring()
        if popover.isShown {
            popover.performClose(nil)
        }
        setContentMasked(false)
        hideAnchorWindow()
        updateRefreshCadence()
    }

    /// 同时监听本 App 和其他 App 的鼠标点击，实现点击弹窗外关闭。
    private func startPopoverDismissMonitoring() {
        stopPopoverDismissMonitoring()

        let mouseEvents: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]

        localPopoverDismissMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            guard let self else { return event }

            if self.shouldKeepPopoverOpen(for: event) {
                return event
            }

            self.closePopover()
            return event
        }

        globalPopoverDismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            DispatchQueue.main.async {
                self?.closePopover()
            }
        }
    }

    private func stopPopoverDismissMonitoring() {
        if let localPopoverDismissMonitor {
            NSEvent.removeMonitor(localPopoverDismissMonitor)
            self.localPopoverDismissMonitor = nil
        }

        if let globalPopoverDismissMonitor {
            NSEvent.removeMonitor(globalPopoverDismissMonitor)
            self.globalPopoverDismissMonitor = nil
        }
    }

    /// 判断一次本地点击是否发生在弹窗或状态栏按钮内，避免内部点击误关弹窗。
    private func shouldKeepPopoverOpen(for event: NSEvent) -> Bool {
        guard popover.isShown else { return false }

        if let popoverWindow = popover.contentViewController?.view.window,
           event.window == popoverWindow {
            return true
        }

        guard let button = statusItem?.button,
              event.window == button.window else {
            return false
        }

        let pointInButton = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(pointInButton)
    }

    private func setContentMasked(_ masked: Bool) {
        isContentMasked = masked
    }

    /// 根据配置更新菜单栏内容；没有任何状态栏内容时移除状态项，避免留下空白或兜底图标。
    private func updateStatusItemTitle() {
        let config = SalaryConfigManager.shared.config
        let showsEarnings = config.displaysEarningsInStatusBar
        let isOffTaskActive = offTaskTracker.isActive
        let showsOffTaskIcon = config.statusBarDisplaysOffTaskStatusIcon(isOffTaskActive: isOffTaskActive)
        let showsIcon = config.statusBarDisplaysAppIcon
        let usesHostedContent = showsEarnings || showsOffTaskIcon
        guard showsIcon || usesHostedContent else {
            removeStatusItem()
            return
        }

        guard let statusItem = ensureStatusItem(),
              let button = statusItem.button else { return }

        let tooltip = statusItemTooltip(config: config, showsOffTaskIcon: showsOffTaskIcon)
        if button.toolTip != tooltip {
            button.toolTip = tooltip
        }

        if !button.title.isEmpty {
            button.title = ""
        }
        if button.attributedTitle.length > 0 {
            button.attributedTitle = NSAttributedString(string: "")
        }

        let amount = showsEarnings
            ? viewModel.formattedEarnings(showCurrencySymbol: config.statusBarDisplaysCurrencySymbol)
            : ""
        let shouldAnimate = showsEarnings
            && !lastStatusAmountText.isEmpty
            && lastStatusAmountText != amount
        let animationStyle = config.resolvedStatusBarSalaryAnimationStyle

        if !usesHostedContent {
            if abs(statusItem.length - NSStatusItem.squareLength) > 0.5 {
                statusItem.length = NSStatusItem.squareLength
            }
            lastStatusItemWidth = nil
            lastStatusItemHeight = nil
            if !statusItemHostingView.isHidden {
                statusItemHostingView.isHidden = true
            }
            if button.image == nil {
                button.image = NSImage(systemSymbolName: "yensign.circle.fill", accessibilityDescription: "薪动")
            }
            if button.imagePosition != .imageOnly {
                button.imagePosition = .imageOnly
            }
            statusItemModel.update(.empty)
            lastStatusAmountText = ""
            rememberVisibleStatusItemFrame(from: button)
            return
        }

        if button.image != nil {
            button.image = nil
        }
        if button.imagePosition != .noImage {
            button.imagePosition = .noImage
        }
        if statusItemHostingView.isHidden {
            statusItemHostingView.isHidden = false
        }

        let height = NSStatusBar.system.thickness
        let width = statusItemWidth(showsIcon: showsIcon, amount: showsEarnings ? amount : nil, showsOffTaskIcon: showsOffTaskIcon)
        updateStatusItemGeometry(statusItem: statusItem, width: width, height: height)

        let state = StatusBarItemState(
            showsIcon: showsIcon,
            amount: showsEarnings ? amount : nil,
            salaryColorHex: config.resolvedStatusBarSalaryColorHex,
            animationStyle: animationStyle,
            showsOffTaskIcon: showsOffTaskIcon,
            offTaskIsActive: isOffTaskActive
        )
        statusItemModel.update(state)

        if shouldAnimate, animationStyle == .bounce {
            animateStatusItemBounce(statusItemHostingView)
        }
        lastStatusAmountText = amount

        rememberVisibleStatusItemFrame(from: button)
    }

    /// 状态栏项可被配置隐藏，后续实时薪资、摸鱼图标或恢复入口再次需要展示时再创建。
    @discardableResult
    private func ensureStatusItem() -> NSStatusItem? {
        if let statusItem {
            return statusItem
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "yensign.circle.fill", accessibilityDescription: "薪动")
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked)
            button.toolTip = "薪动"
            statusItemHostingView.frame = button.bounds
            statusItemHostingView.autoresizingMask = [.width, .height]
            statusItemHostingView.removeFromSuperview()
            button.addSubview(statusItemHostingView)
        }

        return item
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        statusItemModel.update(.empty)
        lastStatusAmountText = ""
        lastStatusItemWidth = nil
        lastStatusItemHeight = nil
        statusItemHostingView.removeFromSuperview()
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    /// 状态栏项宽度变化会触发系统菜单栏重新布局；只在尺寸真正变化时更新。
    private func updateStatusItemGeometry(statusItem: NSStatusItem, width: CGFloat, height: CGFloat) {
        let needsWidthUpdate = abs(statusItem.length - width) > 0.5
        if needsWidthUpdate {
            statusItem.length = width
        }

        let needsFrameUpdate = lastStatusItemWidth.map { abs($0 - width) > 0.5 } ?? true
            || lastStatusItemHeight.map { abs($0 - height) > 0.5 } ?? true
            || abs(statusItemHostingView.frame.width - width) > 0.5
            || abs(statusItemHostingView.frame.height - height) > 0.5

        if needsFrameUpdate {
            statusItemHostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
            lastStatusItemWidth = width
            lastStatusItemHeight = height
        }
    }

    private func statusItemTooltip(config: SalaryConfig, showsOffTaskIcon: Bool) -> String {
        guard showsOffTaskIcon else { return "薪动" }

        if offTaskTracker.isActive {
            return "薪动 · 摸鱼中"
        }

        return "薪动 · \(offTaskTracker.startAvailability(config: config).shortMessage)"
    }

    /// 按实际金额文本测量状态栏宽度，保证数字滚动时不截断。
    private func statusItemWidth(showsIcon: Bool, amount: String?, showsOffTaskIcon: Bool) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let textWidth = amount.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) } ?? 0
        let iconWidth: CGFloat = showsIcon ? 16 + 4 : 0
        let offTaskIconWidth: CGFloat = showsOffTaskIcon ? 16 + (amount == nil && !showsIcon ? 0 : 4) : 0
        let horizontalPadding: CGFloat = 12
        return max(NSStatusItem.squareLength, ceil(textWidth + iconWidth + offTaskIconWidth + horizontalPadding))
    }

    /// 记录最近一次可用的状态栏坐标，给 Hidden Bar 隐藏后的弹窗定位兜底。
    private func rememberVisibleStatusItemFrame(from button: NSStatusBarButton) {
        guard let window = button.window else { return }
        let screenFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        if let screen = window.screen ?? screen(for: screenFrame.midPoint),
           isUsableStatusItemFrame(screenFrame, on: screen) {
            rememberStatusItemFrame(screenFrame, on: screen)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopPopoverDismissMonitoring()
        setContentMasked(false)
        hideAnchorWindow()
        updateRefreshCadence()
    }

    private func hideAnchorWindow() {
        anchorWindow?.orderOut(nil)
    }

    private func screen(for point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    /// 选择兜底屏幕：优先缓存位置，其次鼠标所在屏幕，最后主屏。
    private func fallbackPopoverScreen() -> NSScreen {
        screenForCachedStatusItemFrame()
            ?? lastStatusItemScreen
            ?? screen(for: NSEvent.mouseLocation)
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func cachedStatusItemCenterX(on screen: NSScreen) -> CGFloat? {
        guard let lastStatusItemFrame,
              lastStatusItemFrame.intersects(screen.menuBarBand) else {
            return nil
        }
        return lastStatusItemFrame.midX
    }

    private func screenForCachedStatusItemFrame() -> NSScreen? {
        guard let lastStatusItemFrame else { return nil }
        return screen(for: lastStatusItemFrame.midPoint)
    }

    private func rememberStatusItemFrame(_ frame: NSRect, on screen: NSScreen) {
        guard isUsableStatusItemFrame(frame, on: screen) else { return }
        lastStatusItemFrame = frame
        lastStatusItemScreen = screen
    }

    private func isUsableStatusItemFrame(_ frame: NSRect, on screen: NSScreen) -> Bool {
        frame.width > 1
            && frame.height > 1
            && frame.intersects(screen.menuBarBand)
            && frame.intersects(screen.frame)
    }

    /// 按当前展示状态调整刷新频率，实时展示时高频，后台空闲时可降频。
    private func updateRefreshCadence() {
        let config = SalaryConfigManager.shared.config
        let needsLiveUpdates = popover.isShown || config.displaysEarningsInStatusBar || offTaskTracker.isActive
        // 没有实时展示时降到低频刷新；如果用户本来设置得更慢，则尊重更慢的配置。
        let interval: TimeInterval = needsLiveUpdates || !config.usesLowFrequencyUpdatesWhenIdle
            ? config.resolvedRefreshIntervalSeconds
            : max(60, config.resolvedRefreshIntervalSeconds)
        viewModel.setUpdateInterval(interval)
    }

    /// 弹窗高度由 SwiftUI fittingSize 和配置估算共同决定，防止内容被截断。
    private func updatePopoverContentSize() {
        let fallbackSize = preferredPopoverContentSize(for: SalaryConfigManager.shared.config)
        let measuredHeight: CGFloat?

        if let contentView = popover.contentViewController?.view {
            contentView.layoutSubtreeIfNeeded()
            let fittingSize = contentView.fittingSize
            measuredHeight = fittingSize.height.isFinite && fittingSize.height > 0 ? fittingSize.height : nil
        } else {
            measuredHeight = nil
        }

        let targetHeight = measuredHeight ?? fallbackSize.height
        let maxHeight = max(220, (NSScreen.main?.visibleFrame.height ?? 700) - 72)
        popover.contentSize = NSSize(
            width: popoverWidth,
            height: min(maxHeight, max(80, ceil(targetHeight)))
        )
    }

    /// 根据配置估算弹窗高度，作为 SwiftUI 首次布局前的保守兜底。
    private func preferredPopoverContentSize(for config: SalaryConfig) -> NSSize {
        let showsSalaryBlock = config.popoverDisplaysWorkStatus
            || config.popoverDisplaysCurrentEarnings
            || config.popoverDisplaysRemainingEarnings
            || config.popoverDisplaysAnySalaryRate
            || config.popoverDisplaysWorkProgress
        let showsOffTaskPanel = config.popoverDisplaysAnyOffTaskInformation

        var height: CGFloat = 24
        var outerSections = 0

        if showsSalaryBlock {
            outerSections += 1
            var salaryHeight: CGFloat = 0
            var salarySections = 0

            if config.popoverDisplaysWorkStatus || config.popoverDisplaysWorkProgress {
                salarySections += 1
                if config.popoverDisplaysWorkProgress {
                    salaryHeight += config.workProgressDisplaysSegmentLabels ? 94 : 76
                } else {
                    salaryHeight += 44
                }
            }

            if config.popoverDisplaysCurrentEarnings || config.popoverDisplaysRemainingEarnings {
                salarySections += 1
                if config.popoverDisplaysCurrentEarnings && config.popoverDisplaysRemainingEarnings {
                    salaryHeight += 76
                } else if config.popoverDisplaysCurrentEarnings {
                    salaryHeight += 60
                } else {
                    salaryHeight += 24
                }
            }

            let metricCount = popoverMetricCount(for: config)
            if metricCount > 0 {
                salarySections += 1
                let rows = CGFloat((metricCount + 2) / 3)
                salaryHeight += rows * 62 + max(0, rows - 1) * 8 + 2
            }

            salaryHeight += CGFloat(max(0, salarySections - 1)) * 10
            height += salaryHeight
        }

        if showsOffTaskPanel {
            outerSections += 1
            var offTaskHeight: CGFloat = 16
            var offTaskSections = 0

            if config.popoverDisplaysOffTaskStatus {
                offTaskSections += 1
                offTaskHeight += 28
            }

            if config.popoverDisplaysTodayOffTaskSummary {
                // 摸鱼“今日摸鱼”跟随状态常驻展示，兜底高度需要预留两行文案空间。
                offTaskSections += 1
                offTaskHeight += 30
            }

            let metricCount = popoverOffTaskMetricCount(for: config)
            if metricCount > 0 {
                offTaskSections += 1
                let rows = CGFloat((metricCount + 1) / 2)
                offTaskHeight += rows * 42 + max(0, rows - 1) * 7
            }

            offTaskHeight += CGFloat(max(0, offTaskSections - 1)) * 9
            height += offTaskHeight
        }

        if (showsSalaryBlock || showsOffTaskPanel) && config.popoverDisplaysQuote {
            outerSections += 1
            height += 1
        }

        if config.popoverDisplaysQuote {
            outerSections += 1
            height += 54
        }

        outerSections += 1
        height += 28
        height += CGFloat(max(0, outerSections - 1)) * 12

        return NSSize(width: popoverWidth, height: max(150, ceil(height)))
    }

    /// 统计开启的薪资指标数量，用于预估 BalancedSalaryMetricGrid 的行数。
    private func popoverMetricCount(for config: SalaryConfig) -> Int {
        [
            config.popoverDisplaysSecondSalary,
            config.popoverDisplaysMinuteSalary,
            config.popoverDisplaysHourlySalary,
            config.popoverDisplaysDailySalary,
            config.popoverDisplaysMonthlySalary,
            config.popoverDisplaysYearlySalary
        ].filter { $0 }.count
    }

    /// 统计开启的摸鱼指标数量，用于估算双列指标网格高度。
    private func popoverOffTaskMetricCount(for config: SalaryConfig) -> Int {
        [
            config.popoverDisplaysTodayOffTaskSalary,
            config.popoverDisplaysWeekOffTaskSalary,
            config.popoverDisplaysSalaryCycleOffTaskSalary,
            config.popoverDisplaysHistoricalOffTaskSalary,
            config.popoverDisplaysTodayOffTaskDuration,
            config.popoverDisplaysWeekOffTaskDuration,
            config.popoverDisplaysSalaryCycleOffTaskDuration,
            config.popoverDisplaysHistoricalOffTaskDuration
        ].filter { $0 }.count
    }

    /// 状态栏“跳动”动画只作用在承载视图图层，不改变状态栏项的真实宽度。
    private func animateStatusItemBounce(_ view: NSView) {
        view.wantsLayer = true

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1.0, 1.10, 0.98, 1.0]
        scale.duration = 0.28
        scale.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut)
        ]

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0.82, 1.0]
        opacity.duration = 0.18
        opacity.timingFunction = CAMediaTimingFunction(name: .easeOut)

        view.layer?.add(scale, forKey: "salaryStatusScale")
        view.layer?.add(opacity, forKey: "salaryStatusOpacity")
    }

    /// 配置变化后重算下一次快捷键动作，防止删除动作后索引越界。
    private func updateNextShortcutAction() {
        let sequence = SalaryConfigManager.shared.config.resolvedShortcutActionSequence
        shortcutActionIndex = shortcutActionIndex % sequence.count
        nextShortcutAction = sequence[shortcutActionIndex]
    }
}

/// SwiftUI 状态栏视图的轻量模型，避免直接把完整配置暴露给状态栏渲染层。
private struct StatusBarItemState: Equatable {
    static let empty = StatusBarItemState(
        showsIcon: false,
        amount: nil,
        salaryColorHex: SalaryColor.defaultStatusBarSalaryHex,
        animationStyle: .rolling,
        showsOffTaskIcon: false,
        offTaskIsActive: false
    )

    let showsIcon: Bool
    let amount: String?
    let salaryColorHex: String
    let animationStyle: StatusBarSalaryAnimationStyle
    let showsOffTaskIcon: Bool
    let offTaskIsActive: Bool
}

private final class StatusBarItemModel: ObservableObject {
    @Published private(set) var state = StatusBarItemState.empty

    /// 每秒刷新只发布一次状态，并跳过完全相同的值，避免状态栏 SwiftUI 树重复重绘。
    func update(_ nextState: StatusBarItemState) {
        guard state != nextState else { return }
        state = nextState
    }
}

/// 自定义状态栏内容，保持最初的紧凑格式，只在金额变化时做数字滚动。
private struct StatusBarItemContent: View {
    @ObservedObject var model: StatusBarItemModel

    var body: some View {
        let state = model.state

        HStack(spacing: statusItemSpacing(for: state)) {
            if state.showsIcon {
                Image(systemName: "yensign.circle.fill")
                    .font(.system(size: NSFont.systemFontSize + 1, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 16, height: 16)
            }

            if let amount = state.amount {
                amountText(amount, state: state)
            }

            if state.showsOffTaskIcon {
                Image(systemName: state.offTaskIsActive ? "fish.fill" : "fish")
                    .font(.system(size: NSFont.systemFontSize, weight: .semibold))
                    .foregroundStyle(state.offTaskIsActive ? Color.orange : Color.secondary)
                    .frame(width: 16, height: 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .fixedSize()
        .allowsHitTesting(false)
    }

    private func statusItemSpacing(for state: StatusBarItemState) -> CGFloat {
        let visibleCount = [state.showsIcon, state.amount != nil, state.showsOffTaskIcon].filter { $0 }.count
        return visibleCount > 1 ? 4 : 0
    }

    /// 数字滚动复用 SwiftUI numericText，只让变动字符产生过渡。
    @ViewBuilder
    private func amountText(_ amount: String, state: StatusBarItemState) -> some View {
        let text = Text(amount)
            .font(.system(size: NSFont.systemFontSize, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Color(nsColor: SalaryColor.nsColor(
                hex: state.salaryColorHex,
                fallbackHex: SalaryColor.defaultStatusBarSalaryHex
            )))
            .lineLimit(1)

        if state.animationStyle == .rolling {
            text
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.15), value: amount)
        } else {
            text
        }
    }
}

private extension NSRect {
    /// AppKit 多处需要中点定位，封装后避免重复手写 x/y。
    var midPoint: NSPoint {
        NSPoint(x: midX, y: midY)
    }
}

private extension NSScreen {
    /// 菜单栏所在的窄区域，用于判断缓存的状态栏按钮坐标是否仍可信。
    var menuBarBand: NSRect {
        let height = max(24, frame.maxY - visibleFrame.maxY)
        return NSRect(x: frame.minX, y: frame.maxY - height - 4, width: frame.width, height: height + 8)
    }
}

/// 设置窗口控制器负责预热和置顶展示，避免用户多次点击后不知道窗口已打开。
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    /// App 启动后提前创建设置窗口，降低首次点击“设置”的等待感。
    func prewarm() {
        guard window == nil else { return }
        let settingsWindow = makeWindow()
        settingsWindow.contentView?.layoutSubtreeIfNeeded()
        settingsWindow.contentView?.displayIfNeeded()
    }

    /// 打开设置窗口并主动清掉默认焦点，避免左下角按钮或首个控件莫名获得焦点。
    func show() {
        let settingsWindow = window ?? makeWindow()

        NSApp.activate(ignoringOtherApps: true)
        if settingsWindow.isMiniaturized {
            settingsWindow.deminiaturize(nil)
        }
        settingsWindow.makeKeyAndOrderFront(nil)
        settingsWindow.orderFrontRegardless()
        DispatchQueue.main.async { [weak settingsWindow] in
            settingsWindow?.makeFirstResponder(nil)
        }
    }

    /// 创建可复用设置窗口，关闭后不释放，后续打开保持较快响应。
    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: SettingsView())
        let newWindow = SettingsWindow(contentViewController: hostingController)
        newWindow.title = "薪动 - 设置"
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.setContentSize(NSSize(width: 860, height: 680))
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.collectionBehavior.insert(.moveToActiveSpace)
        window = newWindow
        return newWindow
    }
}

/// 设置窗口的 AppKit 外壳，补齐 SwiftUI 设置页缺少的失焦和 Command-W 行为。
private final class SettingsWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            endEditingWhenClickingOutsideTextInput(event)
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// 点击输入框外部时结束编辑，使数字输入能及时触发格式校验。
    private func endEditingWhenClickingOutsideTextInput(_ event: NSEvent) {
        guard let contentView,
              let hitView = contentView.hitTest(contentView.convert(event.locationInWindow, from: nil)),
              !hitView.isInsideTextInput else {
            return
        }

        makeFirstResponder(nil)
    }
}

private extension NSView {
    /// 向上查找父视图，判断点击是否仍在文本输入控件内部。
    var isInsideTextInput: Bool {
        if self is NSTextField || self is NSTextView {
            return true
        }
        return superview?.isInsideTextInput ?? false
    }
}
