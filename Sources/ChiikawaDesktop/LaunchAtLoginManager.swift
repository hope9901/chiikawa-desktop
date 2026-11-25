import Foundation

/// Manages macOS LaunchAgent (`~/Library/LaunchAgents/com.chiikawa.desktop.plist`)
/// so the user can toggle "시작프로그램 등록 (로그인 시 자동 실행)" directly from the app menu.
public final class LaunchAtLoginManager {
    public static let shared = LaunchAtLoginManager()

    private let label = "com.chiikawa.desktop"

    private init() {}

    private var launchAgentPlistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    public var isEnabled: Bool {
        return FileManager.default.fileExists(atPath: launchAgentPlistURL.path)
    }

    private var executablePath: String {
        if let execURL = Bundle.main.executableURL {
            return execURL.path
        }
        return ProcessInfo.processInfo.arguments.first ?? "/Applications/ChiikawaDesktop.app/Contents/MacOS/ChiikawaDesktop"
    }

    private var workingDirectoryPath: String {
        return Bundle.main.bundleURL.deletingLastPathComponent().path
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        let fm = FileManager.default
        let plistURL = launchAgentPlistURL

        if enabled {
            let launchAgentsDir = plistURL.deletingLastPathComponent()
            try? fm.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

            let plistDict: [String: Any] = [
                "Label": label,
                "ProgramArguments": [executablePath],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Interactive"
            ]

            do {
                let data = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
                try data.write(to: plistURL, options: .atomic)
                return true
            } catch {
                NSLog("[ChiikawaDesktop] Failed to write LaunchAgent plist: \(error)")
                return false
            }
        } else {
            do {
                if fm.fileExists(atPath: plistURL.path) {
                    try fm.removeItem(at: plistURL)
                }
                return true
            } catch {
                NSLog("[ChiikawaDesktop] Failed to remove LaunchAgent plist: \(error)")
                return false
            }
        }
    }

    @discardableResult
    public func toggle() -> Bool {
        let nextState = !isEnabled
        _ = setEnabled(nextState)
        return isEnabled
    }
}
