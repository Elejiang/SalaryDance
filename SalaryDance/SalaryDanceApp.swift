import SwiftUI

/// App 入口。主体界面由状态栏控制器管理，这里只接入 macOS 生命周期。
@main
struct SalaryDanceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

/// 负责启动和停止全局单例：状态栏、快捷键，以及设置窗口预热。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        StatusBarController.shared.start()
        // 启动时同步登录项，覆盖首次安装默认值和外部导入配置后的系统状态差异。
        LaunchAtLoginManager.setEnabled(SalaryConfigManager.shared.config.launchAtLogin)
        GlobalShortcutMonitor.shared.onToggle = {
            StatusBarController.shared.handleShortcutPress()
        }
        GlobalShortcutMonitor.shared.onOffTaskToggle = {
            StatusBarController.shared.toggleOffTaskStatus()
        }
        GlobalShortcutMonitor.shared.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            SettingsWindowController.shared.prewarm()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalShortcutMonitor.shared.stop()
        StatusBarController.shared.stop()
    }
}
