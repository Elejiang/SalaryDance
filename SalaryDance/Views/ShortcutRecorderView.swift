import SwiftUI

enum ShortcutRecorderTarget {
    case shortcutAction
    case offTaskToggle
}

/// 快捷键录制器只在设置页录制期间监听本地按键，录制完成后交给全局监听器重新注册。
final class ShortcutRecorder: ObservableObject {
    static let shared = ShortcutRecorder()

    @Published var isRecording = false
    @Published var activeTarget: ShortcutRecorderTarget?
    @Published var message: String?
    private var monitor: Any?

    private init() {}

    /// 开始录制新的组合键；Esc 取消，其他按键会校验是否适合注册为全局快捷键。
    func start(target: ShortcutRecorderTarget) {
        if isRecording {
            stop()
        }
        isRecording = true
        activeTarget = target
        message = "按下新的快捷键组合"
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else { return event }

            // Esc 用于退出录制，不写入配置。
            if event.keyCode == 53 {
                self.stop()
                return nil
            }

            let flags = event.modifierFlags.intersection(.shortcutModifierMask)
            let keyCode = event.keyCode

            guard ShortcutKey.isRecordable(keyCode) else {
                self.message = "请再按一个非修饰键"
                return nil
            }

            guard !flags.isEmpty || ShortcutKey.canRegisterWithoutModifiers(keyCode) else {
                self.message = "普通按键需要搭配 ⌘、⌥、⌃ 或 ⇧"
                return nil
            }

            // 录制成功后立即持久化，并重启全局监听使新快捷键即时生效。
            let configManager = SalaryConfigManager.shared
            switch target {
            case .shortcutAction:
                configManager.config.shortcutModifiers = Int(flags.rawValue)
                configManager.config.shortcutKeyCode = keyCode
            case .offTaskToggle:
                configManager.config.offTaskShortcutModifiers = Int(flags.rawValue)
                configManager.config.offTaskShortcutKeyCode = keyCode
            }
            self.stop()
            GlobalShortcutMonitor.shared.restart()
            return nil
        }
    }

    /// 停止录制并移除本地事件监听，防止设置窗口关闭后仍吞掉按键。
    func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        isRecording = false
        activeTarget = nil
        message = nil
    }

    func isRecording(_ target: ShortcutRecorderTarget) -> Bool {
        isRecording && activeTarget == target
    }
}

/// 设置页里的快捷键录制控件，展示当前组合键和录制状态。
struct ShortcutRecorderView: View {
    @ObservedObject var recorder = ShortcutRecorder.shared
    let config: SalaryConfig
    var target: ShortcutRecorderTarget = .shortcutAction

    var body: some View {
        HStack(spacing: 8) {
            if recorder.isRecording(target) {
                Text(recorder.message ?? "按下快捷键...")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 4).stroke(Color.accentColor, lineWidth: 1.5))
            } else {
                Text(displayString)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            }

            Button(recorder.isRecording(target) ? "取消" : "录制") {
                if recorder.isRecording(target) {
                    recorder.stop()
                } else {
                    recorder.start(target: target)
                }
            }
            .controlSize(.small)
        }
    }

    private var displayString: String {
        switch target {
        case .shortcutAction:
            return config.shortcutDisplayString
        case .offTaskToggle:
            return config.offTaskShortcutDisplayString
        }
    }
}
