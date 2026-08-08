import SwiftUI
import AVFoundation
import CoreGraphics

/// 首次见面：一页一页把要的权限说明白——要什么、为了什么、代价是什么。
/// 权限弹窗只在用户看完说明、自己点「去授权」之后才出现，绝不开局就弹。
/// esc 或走完流程都算见过面（onboarded），感知从那一刻才启动。
struct OnboardingView: View {
    @State private var page = 0
    @State private var screenGranted = CGPreflightScreenCaptureAccess()
    @State private var cameraOn = false

    private let pages = 4

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(height: 320, alignment: .top)
                .padding(.horizontal, 36)
                .padding(.top, 34)

            HStack(spacing: 6) {
                ForEach(0..<pages, id: \.self) { i in
                    Circle()
                        .fill(i == page ? DS.coral : DS.lineStrong)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.bottom, 18)

            HStack {
                if page > 0 {
                    Button("上一步") { withAnimation(.easeOut(duration: 0.18)) { page -= 1 } }
                        .buttonStyle(GhostPillStyle())
                }
                Spacer()
                Button(page == pages - 1 ? "开始吧" : "下一步") {
                    if page == pages - 1 {
                        PetPanels.shared.closeOnboarding()
                    } else {
                        withAnimation(.easeOut(duration: 0.18)) { page += 1 }
                    }
                }
                .buttonStyle(InkPillStyle())
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 480)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(DS.paper.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(DS.lineStrong, lineWidth: 1))
        .onExitCommand { PetPanels.shared.closeOnboarding() }
        // 从系统设置回来，授权状态要自己刷新
        .task(id: page) {
            while !Task.isCancelled, page == 1 {
                screenGranted = CGPreflightScreenCaptureAccess()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case 0: hello
        case 1: screenPage
        case 2: cameraPage
        default: modelPage
        }
    }

    // MARK: 第一页 · 见面

    private var hello: some View {
        VStack(alignment: .leading, spacing: 18) {
            CatFace(size: 64, breathing: true)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 2)
            title("你好，我是懒猫。")
            prose("""
            我住在你的屏幕角落，看你干活的节奏，陪你记那些来不及记的事。
            """)
            prose("""
            我的一切都在这台电脑上——时间笔记、人物卡、回忆，都是你随时能翻开的 \
            markdown 文件，一个字都不上传。
            """)
            prose("接下来两页，把我要的权限一次说清楚，你再决定给不给。")
        }
    }

    // MARK: 第二页 · 屏幕录制

    private var screenPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("我想看看你在忙什么")
            prose("""
            每隔几十秒，我会读一眼前台窗口上的字（本机 OCR），把「你在做什么、\
            谁说了什么」记成时间笔记——这是回忆和搜索的地基。
            """)
            prose("""
            像素只在内存里过一遍，磁盘上从不出现截图；密码框亮着的时候我闭眼；\
            这些原料只留十四天，永不同步、永不出门。
            """)
            prose("这需要系统的「屏幕录制」权限。不给也行，我就只当个陪坐的。")

            HStack(spacing: 12) {
                if screenGranted {
                    Label("已授权", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.blue)
                } else {
                    Button("去授权") { requestScreenAccess() }
                        .buttonStyle(InkPillStyle())
                }
            }
            .padding(.top, 4)
        }
    }

    private func requestScreenAccess() {
        // 从没问过：这一下会弹系统提示；问过被拒：得去系统设置手动开
        if !CGRequestScreenCaptureAccess() {
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                if !CGPreflightScreenCaptureAccess(),
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        screenGranted = CGPreflightScreenCaptureAccess()
    }

    // MARK: 第三页 · 摄像头（可选）

    private var cameraPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("要不要让我知道你在不在？")
            prose("""
            开着的话，我用摄像头判断你是坐在屏幕前、还是真的走开了——看视频不再\
            被我误当成休息，真离开两分钟就开始给你回血。
            """)
            prose("""
            画面在内存里过一遍「有没有人脸」就丢，不截图、不落盘；代价是摄像头的\
            指示灯会常亮——这盏灯是诚实的。
            """)
            prose("默认不开。开了之后随时可以在设置里关。")

            HStack(spacing: 12) {
                if cameraOn {
                    Label("已开启", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.blue)
                } else {
                    Button("开启") {
                        PresenceSensor.shared.setEnabled(true)
                        cameraOn = true
                    }
                    .buttonStyle(InkPillStyle())
                    Button("先不用") { withAnimation(.easeOut(duration: 0.18)) { page += 1 } }
                        .buttonStyle(GhostPillStyle())
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: 第四页 · 模型 Key

    private var modelPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("配一个模型，我才会写字")
            prose("""
            没有 Key 我也活着——能量、提醒、桌宠都照常。但写笔记、做梦和聊天，\
            需要一个你自己的模型 Key（OpenAI、DeepSeek，或任何兼容端点）。
            """)
            prose("费用走你自己的账，一天几分钱；Key 只存在你的钥匙串里。")

            Button("去设置") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(GhostPillStyle())
            .padding(.top, 4)
        }
    }

    // MARK: 排版件

    private func title(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 21, weight: .light))
            .foregroundStyle(DS.ink)
    }

    private func prose(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 13))
            .lineSpacing(6)
            .foregroundStyle(DS.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
    }
}
