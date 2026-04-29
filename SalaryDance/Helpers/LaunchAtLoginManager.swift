import Foundation

/// 通过用户 LaunchAgents 实现开机启动，不依赖 App Store 登录项能力。
enum LaunchAtLoginManager {
    private static let launcherID = "com.salarydance.app.launcher"

    static func setEnabled(_ enabled: Bool) {
        let fileManager = FileManager.default
        guard let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return
        }

        let launchAgentsURL = libraryURL.appendingPathComponent("LaunchAgents", isDirectory: true)
        let plistURL = launchAgentsURL.appendingPathComponent("\(launcherID).plist")

        if enabled {
            guard let bundlePath = Bundle.main.executablePath else { return }
            let plist: [String: Any] = [
                "Label": launcherID,
                "ProgramArguments": [bundlePath],
                "RunAtLoad": true,
                "KeepAlive": false
            ]

            do {
                // 用系统序列化生成 plist，避免路径里的特殊字符破坏 XML。
                let data = try PropertyListSerialization.data(
                    fromPropertyList: plist,
                    format: .xml,
                    options: 0
                )
                try fileManager.createDirectory(at: launchAgentsURL, withIntermediateDirectories: true)
                try data.write(to: plistURL, options: .atomic)
            } catch {
                assertionFailure("Failed to update launch agent: \(error.localizedDescription)")
            }
        } else {
            try? fileManager.removeItem(at: plistURL)
        }
    }
}
