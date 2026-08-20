import Foundation

/// Debug 与正式版是两只独立的猫：不同 bundle id 对应各自的 TCC 权限，
/// 默认数据目录也分开，允许开发版和正式版同时运行而不争同一把账本锁。
/// 各项已有的 DOZYCAT_* 环境变量仍然拥有最高优先级。
enum AppPaths {
    static let releaseBundleID = "com.paperboytm.dozycat.pet"
    static let debugBundleID = "com.paperboytm.dozycat.pet.debug"

    static var isDebugApp: Bool {
        Bundle.main.bundleIdentifier == debugBundleID
    }

    static var dataRoot: URL {
        if let path = ProcessInfo.processInfo.environment["DOZYCAT_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let name = isDebugApp ? ".dozycat-debug" : ".dozycat"
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    static func file(_ relativePath: String) -> URL {
        dataRoot.appendingPathComponent(relativePath)
    }

    static func directory(_ relativePath: String) -> URL {
        dataRoot.appendingPathComponent(relativePath, isDirectory: true)
    }
}
