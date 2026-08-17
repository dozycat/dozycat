import AppKit
import Sparkle

/// 自动更新（Sparkle）。直发版（非 MAS）用它检查、下载、安装新版本。
/// 清单在 Info.plist 的 SUFeedURL（官网 appcast.xml），更新包用 EdDSA
/// 私钥签名、公钥（SUPublicEDKey）在 app 里校验——中间人换不了包。
///
/// 菜单栏应用（LSUIElement）也能弹更新窗：Sparkle 自带 UI。默认后台每天
/// 查一次（Info.plist SUEnableAutomaticChecks / SUScheduledCheckInterval），
/// 用户可在设置里关；也能手动「检查更新」。
@MainActor
final class Updater {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController

    private init() {
        // startingUpdater: true —— 起进程即开始按计划后台查更。
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// 手动检查（设置里的按钮）：无更新也会给用户一个明确的回应。
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// 后台自动检查开关（持久化在 Sparkle 自己的 defaults）。
    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// 上次检查时间——设置里显示「刚刚检查过」。
    var lastCheckDate: Date? { controller.updater.lastUpdateCheckDate }
}
