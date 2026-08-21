import SwiftUI
import AVFoundation
import CoreGraphics

/// 首次见面：四页、四个决定。解释永远先于系统弹窗。
struct OnboardingView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var presenceSensor = PresenceSensor.shared
    @AppStorage("presenceSensing") private var cameraOn = false
    @State private var page: Int
    @State private var screenGranted = CGPreflightScreenCaptureAccess()
    @State private var cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var pasted = false

    private let pageCount = 4

    init(initialPage: Int = 0) {
        _page = State(initialValue: max(0, min(3, initialPage)))
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                pageContent
                    .id(page)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity.combined(with: .move(edge: .leading))
                    ))

                if page > 0 {
                    Button {
                        move(to: page - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.muted)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(DS.lineSoft))
                    }
                    .buttonStyle(.plain)
                    .help("上一步")
                    .padding(.top, 20)
                    .padding(.leading, 22)
                }
            }
            .frame(height: 492, alignment: .top)
            .clipped()

            pageDots
                .padding(.bottom, 20)
        }
        .frame(width: 480)
        .clipShape(DesktopCardChrome.shape())
        .background(DesktopCardChrome.surface())
        .onExitCommand { finish() }
        .task(id: page) {
            while !Task.isCancelled, page == 1 {
                screenGranted = CGPreflightScreenCaptureAccess()
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case 0: helloPage
        case 1: screenPage
        case 2: cameraPage
        default: modelPage
        }
    }

    private var helloPage: some View {
        pageShell(eyebrow: "一 · 见面", cat: .doze,
                  title: "你好，我是懒猫。") {
            VStack(spacing: 0) {
                factRow(color: DS.coral, title: "我住在屏幕角落，不占地方",
                        detail: "点我可以说话；停一停，才会看见能量数字")
                factRow(color: DS.blue, title: "一切都发生在这台电脑上",
                        detail: "时间笔记、人物卡和回忆，都是能翻开的 markdown")
                factRow(color: DS.ink, title: "一个字都不会上传",
                        detail: "模型 Key 也只进你的系统钥匙串")
            }

            primaryButton("认识一下") { move(to: 1) }
                .padding(.top, 22)
        }
    }

    private var screenPage: some View {
        pageShell(eyebrow: "二 · 屏幕录制", cat: .curious,
                  title: "我想看看你在忙什么。") {
            VStack(spacing: 0) {
                statusRow("本机 OCR，只记时间笔记", trailing: "不看内容含义")
                statusRow("像素只在内存过一遍", trailing: "磁盘从不出现截图")
                statusRow("密码框自动闭眼", trailing: "⌁⌁")
                statusRow("原料只留十四天", trailing: "到期即焚")
                statusRow("屏幕录制", trailing: screenGranted ? "✓ 已授权" : "尚未授权",
                          accent: screenGranted ? DS.blue : DS.coral)
            }

            primaryButton(screenGranted ? "已授权，下一页" : "去授权") {
                if screenGranted { move(to: 2) } else { requestScreenAccess() }
            }
            .padding(.top, 20)

            quietButton("不给也行，我就只当个陪坐的") { move(to: 2) }
        }
    }

    private var cameraPage: some View {
        pageShell(eyebrow: "三 · 摄像头（可选）", cat: .happy,
                  title: "要不要让我知道你在不在？") {
            VStack(spacing: 0) {
                statusRow("帧过完人脸检测就丢", trailing: "不存 · 不传")
                statusRow("顺带认个表情", trailing: "本地小模型 · 只出标签")
                statusRow("开着时指示灯常亮", trailing: "这盏灯是诚实的",
                          accent: DS.blue)
                statusRow("默认不开", trailing: "以后随时能改")
                if cameraStatus == .denied || cameraStatus == .restricted {
                    statusRow("摄像头权限", trailing: "系统已关闭", accent: DS.coral)
                } else if cameraOn {
                    statusRow("摄像头在位感知", trailing: onboardingCameraStatus,
                              accent: presenceSensor.status == .running ? DS.blue : DS.coral)
                }
            }

            HStack(spacing: 12) {
                Button("先不用") { move(to: 3) }
                    .buttonStyle(InkPillStyle())
                Button(presenceSensor.status == .running ? "已开启" : "让它看") {
                    requestCameraAccess()
                }
                .buttonStyle(GhostPillStyle())
                .disabled(presenceSensor.status == .running)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 22)

            if cameraOn && cameraStatus == .authorized {
                quietButton("下一页") { move(to: 3) }
            }
        }
    }

    private var onboardingCameraStatus: LocalizedStringKey {
        switch presenceSensor.status {
        case .running: "✓ 正在采集"
        case .starting: "正在启动…"
        case .permissionDenied: "权限未生效"
        case .cameraUnavailable: "没有可用摄像头"
        case .failed: "未能采集"
        case .disabled: "尚未启动"
        }
    }

    private var modelPage: some View {
        pageShell(eyebrow: "四 · 模型 Key", cat: .doze,
                  title: "配一个模型，我才会写字。") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(LLMProvider.allCases) { provider in
                        let active = settings.provider == provider
                        Button {
                            settings.provider = provider
                            settings.baseURL = ""
                            settings.model = ""
                        } label: {
                            Text(verbatim: provider.label)
                                .font(.system(size: 11, weight: active ? .medium : .regular))
                                .foregroundStyle(active ? DS.paper : DS.inkSoft)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(Capsule().fill(active ? DS.ink : Color.clear))
                                .overlay(Capsule().stroke(active ? Color.clear : DS.lineStrong,
                                                          lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    SecureField("sk-··············", text: $settings.apiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.ink)
                    Button(pasted ? "已粘贴" : "粘贴") { pasteKey() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.muted)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DS.card))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.lineStrong, lineWidth: 1))

                statusRow("Key 只存系统钥匙串", trailing: "除了模型谁也不发")
                statusRow("不配也能陪坐、记账、提醒", trailing: "批注和《传》会缺席")
            }

            primaryButton(settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          ? "先开始" : "存好，开始") {
                if !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    settings.persistKey()
                }
                finish()
            }
            .padding(.top, 20)

            if !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                quietButton("清空 Key，先跳过") {
                    settings.apiKey = ""
                    settings.persistKey()
                    finish()
                }
            }
        }
    }

    private func pageShell<Content: View>(eyebrow: LocalizedStringKey, cat: CatMood,
                                          title: LocalizedStringKey,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            DeskCat(mood: cat, size: 72)
                .frame(height: 66)
                .padding(.top, 28)
            Text(eyebrow)
                .font(.system(size: 9, weight: .medium))
                .tracking(2.6)
                .foregroundStyle(DS.faint)
                .padding(.top, 8)
            Text(title)
                .font(.system(size: 21, weight: .semibold, design: .serif))
                .foregroundStyle(DS.ink)
                .padding(.top, 12)
                .padding(.bottom, 18)
            content()
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func factRow(color: Color, title: LocalizedStringKey,
                         detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(color).frame(width: 6, height: 6).padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13)).foregroundStyle(DS.ink)
                Text(detail).font(.system(size: 11)).foregroundStyle(DS.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { DS.lineSoft.frame(height: 1) }
    }

    private func statusRow(_ title: LocalizedStringKey, trailing: LocalizedStringKey,
                           accent: Color = DS.faint) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(DS.inkSoft)
            Spacer(minLength: 12)
            Text(trailing)
                .font(.system(size: 11))
                .foregroundStyle(accent)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { DS.lineSoft.frame(height: 1) }
    }

    private func primaryButton(_ title: LocalizedStringKey,
                               action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(InkPillStyle())
            .frame(maxWidth: .infinity)
    }

    private func quietButton(_ title: LocalizedStringKey,
                             action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(DS.muted)
            .padding(.top, 13)
            .frame(maxWidth: .infinity)
    }

    private var pageDots: some View {
        HStack(spacing: 9) {
            ForEach(0..<pageCount, id: \.self) { index in
                Button {
                    move(to: index)
                } label: {
                    Capsule()
                        .fill(index == page ? DS.coral : DS.lineStrong)
                        .frame(width: index == page ? 18 : 5, height: 5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("第 \(index + 1) 页")
            }
        }
        .animation(.easeOut(duration: 0.18), value: page)
    }

    private func move(to next: Int) {
        withAnimation(.easeOut(duration: 0.22)) { page = max(0, min(pageCount - 1, next)) }
    }

    private func requestScreenAccess() {
        if CGPreflightScreenCaptureAccess() {
            screenGranted = true
            return
        }
        if !CGRequestScreenCaptureAccess() {
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                if !CGPreflightScreenCaptureAccess(),
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        screenGranted = CGPreflightScreenCaptureAccess()
    }

    private func requestCameraAccess() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
                cameraOn = granted
                PresenceSensor.shared.setEnabled(granted)
                if granted { move(to: 3) }
            }
        }
    }

    private func pasteKey() {
        guard let value = NSPasteboard.general.string(forType: .string), !value.isEmpty else {
            NSSound.beep()
            return
        }
        settings.apiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
        pasted = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            pasted = false
        }
    }

    private func finish() {
        PetPanels.shared.closeOnboarding()
    }
}

#Preview("首启") {
    OnboardingView()
}
