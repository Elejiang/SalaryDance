import Cocoa
import Combine
import Carbon.HIToolbox

/// 使用 Carbon HotKey 注册真正全局的快捷键，不依赖当前 App 是否获得焦点。
final class GlobalShortcutMonitor: ObservableObject {
    static let shared = GlobalShortcutMonitor()

    private static let hotKeySignature = OSType(0x534C5259) // "SLRY"
    private enum HotKeyIdentifier: UInt32 {
        case shortcutAction = 1
        case offTaskToggle = 2
    }

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    var onToggle: (() -> Void)?
    var onOffTaskToggle: (() -> Void)?
    @Published private(set) var registrationError: String?

    private init() {}

    /// 根据当前配置注册快捷键；配置关闭或组合非法时不会注册。
    func start() {
        stop()
        registrationError = nil

        let config = SalaryConfigManager.shared.config
        installEventHandlerIfNeeded()
        guard eventHandler != nil else { return }

        var errors: [String] = []
        registerHotKeyIfNeeded(
            enabled: config.shortcutEnabled,
            keyCode: config.resolvedShortcutKeyCode,
            modifiers: config.shortcutModifierFlags,
            identifier: .shortcutAction,
            title: "动作快捷键",
            errors: &errors
        )
        registerHotKeyIfNeeded(
            enabled: config.offTaskShortcutEnabled,
            keyCode: config.resolvedOffTaskShortcutKeyCode,
            modifiers: config.offTaskShortcutModifierFlags,
            identifier: .offTaskToggle,
            title: "摸鱼快捷键",
            errors: &errors
        )

        registrationError = errors.isEmpty ? nil : errors.joined(separator: "；")
    }

    /// 注销快捷键，App 退出或重新注册前必须调用。
    func stop() {
        for (_, hotKeyRef) in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
    }

    /// 设置页改动快捷键后走重启注册链路。
    func restart() {
        start()
    }

    /// Carbon 事件处理器全局只需要安装一次，收到匹配 id 后回调快捷键动作。
    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else { return noErr }

                var hotKeyID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard parameterStatus == noErr,
                      hotKeyID.signature == GlobalShortcutMonitor.hotKeySignature,
                      let identifier = HotKeyIdentifier(rawValue: hotKeyID.id) else {
                    return noErr
                }

                DispatchQueue.main.async {
                    switch identifier {
                    case .shortcutAction:
                        GlobalShortcutMonitor.shared.onToggle?()
                    case .offTaskToggle:
                        GlobalShortcutMonitor.shared.onOffTaskToggle?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )

        if status != noErr {
            registrationError = "快捷键事件监听初始化失败（\(status)）"
            eventHandler = nil
        }
    }

    private func registerHotKeyIfNeeded(
        enabled: Bool,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        identifier: HotKeyIdentifier,
        title: String,
        errors: inout [String]
    ) {
        guard enabled else { return }

        guard !modifiers.isEmpty || ShortcutKey.canRegisterWithoutModifiers(keyCode) else {
            errors.append("\(title)：普通按键需要至少一个修饰键")
            return
        }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: Self.hotKeySignature,
            id: identifier.rawValue
        )
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            modifiers.carbonShortcutModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let hotKeyRef {
            hotKeyRefs[identifier.rawValue] = hotKeyRef
        } else {
            errors.append("\(title)注册失败（\(status)），可能已被其他应用占用")
        }
    }

    deinit {
        stop()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
