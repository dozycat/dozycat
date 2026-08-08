import AppKit
import SwiftUI

/// 卡片面板：搜索、对话、能量、《传》共用的浮动宿主（FloatingPanel 的换代）。
///
/// 做法对齐原生 mac 应用的浮动面板惯例（参照 Finder「前往文件夹」一类）：
/// - borderless + nonactivating，canBecomeKey——像 Spotlight 一样接键盘，
///   但不把激活从前台 app 抢过来，唤起/收起都不引发前台切换的闪动；
/// - NSVisualEffectView(behindWindow) 打底，maskImage 裁圆角——layer 的
///   cornerRadius 裁不掉窗后模糊，必须用 mask 图；
/// - 点到面板之外（失去 key）自动收起，esc 在 responder chain 里就近处理；
/// - 进出场动画做在窗口层（alpha + 位移，CA 合成），内容不参与重渲染；
/// - 内容高度变化时锚住顶边动画调整，输入框不跳。
final class CardPanel: NSPanel {
    /// 收起完成后由 PetPanels 清引用、同步猫的心情。
    var onClose: (() -> Void)?

    private let hosting: NSHostingView<AnyView>
    private var resignObserver: NSObjectProtocol?
    private var dismissing = false
    /// onboarding 这类流程面板要挺住失焦（用户中途去系统设置授权，回来还得在）。
    private let dismissOnResignKey: Bool

    init(content: some View, width: CGFloat, cornerRadius: CGFloat = 22,
         vibrancy: Bool = true, dismissOnResignKey: Bool = true) {
        self.dismissOnResignKey = dismissOnResignKey
        hosting = NSHostingView(rootView: AnyView(content))
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        // 阴影交给窗口系统绘制。SwiftUI shadow 不参与 fittingSize，会在透明
        // NSPanel 的矩形边界被裁成直角残片（尤其明显在 Chat 左下角）。
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none  // 进出场自己画，别再叠系统的

        let container = NSView()
        container.wantsLayer = true

        if vibrancy {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.maskImage = Self.roundedCornerMask(radius: cornerRadius)
            effect.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(effect)
            NSLayoutConstraint.activate([
                effect.topAnchor.constraint(equalTo: container.topAnchor),
                effect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                effect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                effect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }

        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false
        hosting.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        contentView = container
        setContentSize(hosting.fittingSize)
    }

    override var canBecomeKey: Bool { true }

    /// esc 收面板——放 responder chain 里，SwiftUI 焦点没接住时由窗口兜底，
    /// 不再需要全局事件监听。
    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    // MARK: - 进出场

    func showCentered(yRatio: CGFloat = 0.62) {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let size = hosting.fittingSize
        setContentSize(size)
        // clamp 进可见区：小屏上 900pt 宽的能量面板不能掉出屏幕
        var origin = NSPoint(x: f.midX - size.width / 2,
                             y: f.minY + f.height * yRatio - size.height / 2)
        origin.x = max(f.minX + 16, min(origin.x, f.maxX - size.width - 16))
        origin.y = max(f.minY + 16, min(origin.y, f.maxY - size.height - 16))
        present(origin: origin)
    }

    /// 挨着桌宠窗弹出（对话面板）；找不到锚点就居中。
    func show(near anchor: NSWindow?) {
        guard let anchor, let screen = anchor.screen ?? NSScreen.main else {
            showCentered(yRatio: 0.4)
            return
        }
        let size = hosting.fittingSize
        setContentSize(size)
        let f = screen.visibleFrame
        var origin = NSPoint(x: anchor.frame.maxX - size.width - 20,
                             y: anchor.frame.minY + 200)
        origin.x = max(f.minX + 16, min(origin.x, f.maxX - size.width - 16))
        origin.y = max(f.minY + 16, min(origin.y, f.maxY - size.height - 16))
        present(origin: origin)
    }

    /// 提醒与收尾倒计时贴着右上角出现；保留菜单栏和 20pt 呼吸空间。
    func showTopRight(margin: CGFloat = 24) {
        guard let screen = NSScreen.main else { return }
        let size = hosting.fittingSize
        setContentSize(size)
        let f = screen.visibleFrame
        let origin = NSPoint(x: f.maxX - size.width - margin,
                             y: f.maxY - size.height - margin)
        present(origin: origin)
    }

    /// 唤起：从最终位置上方 10pt 淡入落下（对齐设计稿「220ms 弹性下落」的意图，
    /// 但走窗口层 CA 合成）。同时挂上失焦自动收起。
    private func present(origin: NSPoint) {
        let final = NSRect(origin: origin, size: frame.size)
        setFrame(final.offsetBy(dx: 0, dy: 10), display: false)
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(final, display: true)
        }
        guard dismissOnResignKey else { return }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: self, queue: .main
        ) { [weak self] _ in
            self?.dismiss()
        }
    }

    /// 收起：淡出后 orderOut，最后回调 onClose 让持有者清引用。
    func dismiss() {
        guard !dismissing else { return }
        dismissing = true
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.13
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.orderOut(nil)
            // 面板一次性使用：内容状态都在共享 model 里，重开即恢复。
            let callback = self.onClose
            self.onClose = nil
            callback?()
        })
    }

    /// 内容尺寸变了（证物板增减、结案报告展开）：锚住顶边动画到新高度。
    func resizeToFitKeepingTop(animated: Bool = true) {
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0,
              abs(size.height - frame.height) > 0.5 || abs(size.width - frame.width) > 0.5
        else { return }
        // 搜索三幕会同时改宽高；横向守住中心、纵向守住上沿，切场景时才不会跳边。
        let target = NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height,
                            width: size.width, height: size.height)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().setFrame(target, display: true)
            }
        } else {
            setFrame(target, display: true)
        }
    }

    #if DEBUG
    func writeDebugSnapshot(to path: String) {
        contentView?.writeDebugPNG(to: path)
    }
    #endif

    /// 可拉伸的圆角遮罩：用来裁 behind-window blur（cap insets 让四角不变形）。
    private static func roundedCornerMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

#if DEBUG
extension NSView {
    func writeDebugPNG(to path: String) {
        layoutSubtreeIfNeeded()
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return }
        cacheDisplay(in: bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
#endif
