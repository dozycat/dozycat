import SwiftUI
import CoreGraphics

struct PetSettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general, sensing, model
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .general: "常规"
            case .sensing: "感知"
            case .model: "模型"
            }
        }
        var icon: String {
            switch self {
            case .general: "slider.horizontal.3"
            case .sensing: "eye"
            case .model: "sparkles"
            }
        }
    }

    private enum TestState: Equatable {
        case idle, testing, success, failure(String)
    }

    @ObservedObject private var settings = SettingsStore.shared
    @AppStorage("uiLanguage") private var uiLanguage = "zh"
    @AppStorage("uiAppearance") private var uiAppearance = "system"
    @AppStorage("presenceSensing") private var presenceSensing = false
    @AppStorage("smileMoments") private var smileMoments = true
    @State private var pane: Pane
    @State private var languageChanged = false
    @State private var screenGranted = CGPreflightScreenCaptureAccess()
    @State private var keySaved = false
    @State private var testState: TestState = .idle
    @State private var autoUpdate = Updater.shared.automaticallyChecks

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v)（\(b)）"
    }

    init(initialPane: Pane = .general) {
        _pane = State(initialValue: initialPane)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            panePicker

            ScrollView(.vertical) {
                Group {
                    switch pane {
                    case .general: generalPane
                    case .sensing: sensingPane
                    case .model: modelPane
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, 4)
                .id(pane)
                .transition(.opacity)
            }
            .scrollIndicators(.hidden)
            .frame(height: 322, alignment: .top)
            .padding(.horizontal, 28)
            .padding(.top, 22)

            footer
        }
        .frame(width: 540)
        .background(DS.paper)
        .task {
            while !Task.isCancelled {
                screenGranted = CGPreflightScreenCaptureAccess()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CatFace(size: 38, outlined: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("懒猫的设置")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.ink)
                Text("你的数据、你的节奏、你的猫")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.muted)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(settings.llmConfig == nil ? DS.coral : DS.blue)
                    .frame(width: 6, height: 6)
                Text(settings.llmConfig == nil ? "模型未连接" : "模型已就绪")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.muted)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) { DS.line.frame(height: 1) }
    }

    private var panePicker: some View {
        HStack(spacing: 6) {
            ForEach(Pane.allCases) { item in
                let active = item == pane
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { pane = item }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: item.icon)
                        Text(item.label)
                    }
                    .font(.system(size: 12, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? DS.ink : DS.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(active ? DS.card : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(active ? DS.line : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(DS.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 28)
        .padding(.top, 18)
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingGroup(title: "语言") {
                settingLine(title: "界面语言", detail: languageChanged ? "重启懒猫后生效" : nil) {
                    pillPicker(values: [
                        ("跟随系统", "system"), ("中文", "zh"), ("EN", "en")
                    ], selection: $uiLanguage) { _ in
                        DozycatPetApp.applyLanguagePreference()
                        languageChanged = true
                    }
                }
            }

            settingGroup(title: "外观") {
                settingLine(title: "亮暗", detail: "所有面板会立即切换") {
                    pillPicker(values: [
                        ("跟随系统", "system"), ("亮", "light"), ("暗", "dark")
                    ], selection: $uiAppearance) { _ in
                        PetAppDelegate.applyAppearancePreference()
                    }
                }
            }

            settingGroup(title: "本机花园") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("时间笔记、卷宗和《传》")
                            .font(.system(size: 13)).foregroundStyle(DS.ink)
                        Text(verbatim: Garden.root.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(DS.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("打开") { NSWorkspace.shared.open(Garden.root) }
                        .buttonStyle(SmallGhostPill())
                }
            }

            settingGroup(title: "更新") {
                settingLine(title: "当前版本", detail: nil) {
                    HStack(spacing: 10) {
                        Text(verbatim: appVersion)
                            .font(.system(size: 13)).foregroundStyle(DS.muted)
                        Button("检查更新") { Updater.shared.checkForUpdates() }
                            .buttonStyle(SmallGhostPill())
                    }
                }
                settingLine(title: "自动检查更新",
                            detail: "后台每天看一次官网有没有新版本") {
                    Toggle("", isOn: $autoUpdate)
                        .toggleStyle(.switch).controlSize(.small).labelsHidden()
                        .onChange(of: autoUpdate) { _, on in
                            Updater.shared.automaticallyChecks = on
                        }
                }
            }
        }
    }

    private var sensingPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            permissionCard(
                icon: "rectangle.dashed.badge.record",
                title: "屏幕文字",
                detail: "本机 OCR 只产出时间笔记；截图不落盘，密码框会闭眼。",
                granted: screenGranted,
                action: requestScreenAccess
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "video")
                        .font(.system(size: 15))
                        .foregroundStyle(DS.blue)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(DS.blue.opacity(0.10)))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("摄像头在位感知")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(DS.ink)
                        Text("判断人是否在屏幕前，顺带用本地小模型认个表情（开心/伤心这类标签）。帧过完检测即丢；开启时系统指示灯会常亮。")
                            .font(.system(size: 11)).lineSpacing(5).foregroundStyle(DS.muted)
                    }
                    Spacer()
                    Toggle("", isOn: $presenceSensing)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .onChange(of: presenceSensing) { _, on in
                            PresenceSensor.shared.setEnabled(on)
                        }
                }
                if presenceSensing {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 15))
                            .foregroundStyle(DS.coral)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(DS.coral.opacity(0.10)))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("微笑时刻")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(DS.ink)
                            Text("笑的时候把屏幕上那几行字记进记事本，回头看看是什么逗笑了你。三分钟最多一条，同一个乐子不重复记。")
                                .font(.system(size: 11)).lineSpacing(5).foregroundStyle(DS.muted)
                        }
                        Spacer()
                        Toggle("", isOn: $smileMoments)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                }
            }
            .padding(16)
            .background(cardBackground)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(DS.muted)
                Text("所有感知都可以单独关闭。见完面之前感知层不会启动；原始 OCR 最多保留十四天。")
                    .font(.system(size: 11)).lineSpacing(5).foregroundStyle(DS.muted)
            }
            .padding(.horizontal, 4)
        }
    }

    private var modelPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(LLMProvider.allCases) { provider in
                    selectionPill(LocalizedStringKey(provider.label),
                                  active: settings.provider == provider) {
                        settings.provider = provider
                        settings.baseURL = ""
                        settings.model = ""
                        keySaved = false
                        testState = .idle
                    }
                }
                Spacer()
            }

            VStack(spacing: 0) {
                if settings.provider == .custom {
                    fieldLine("Base URL", text: $settings.baseURL, prompt: "https://…/v1")
                }
                fieldLine("模型名", text: $settings.model, prompt: settings.provider.defaultModel)
                fieldLine("API Key", text: $settings.apiKey, prompt: "sk-…", secure: true)
            }
            .padding(.horizontal, 14)
            .background(cardBackground)

            HStack(spacing: 10) {
                Button(keySaved ? "已保存" : "保存") {
                    settings.persistKey()
                    keySaved = true
                    testState = .idle
                }
                .buttonStyle(InkPillStyle())
                .disabled(settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(testButtonLabel) { testModel() }
                    .buttonStyle(GhostPillStyle())
                    .disabled(settings.llmConfig == nil || testState == .testing)

                Spacer()
                Text(testMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(testColor)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Image(systemName: "key.horizontal")
                Text("Key 只存在系统钥匙串；费用与数据策略由你选择的模型服务决定。")
            }
            .font(.system(size: 10))
            .foregroundStyle(DS.muted)
        }
        .onChange(of: settings.apiKey) {
            keySaved = false
            testState = .idle
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(DS.blue).frame(width: 5, height: 5)
            Text("设置保存在这台 Mac；API Key 使用系统钥匙串。")
            Spacer()
            Text(verbatim: "dozycat · 0.1")
        }
        .font(.system(size: 10))
        .foregroundStyle(DS.faint)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .overlay(alignment: .top) { DS.line.frame(height: 1) }
    }

    private func settingGroup<Content: View>(title: LocalizedStringKey,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .tracking(2.2)
                .foregroundStyle(DS.faint)
            content()
        }
    }

    private func settingLine<Content: View>(title: LocalizedStringKey, detail: LocalizedStringKey?,
                                            @ViewBuilder accessory: () -> Content) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13)).foregroundStyle(DS.ink)
                if let detail {
                    Text(detail).font(.system(size: 10)).foregroundStyle(DS.muted)
                }
            }
            Spacer()
            accessory()
        }
    }

    private func pillPicker(values: [(LocalizedStringKey, String)], selection: Binding<String>,
                            onChange: @escaping (String) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(values, id: \.1) { item in
                selectionPill(item.0, active: selection.wrappedValue == item.1) {
                    selection.wrappedValue = item.1
                    onChange(item.1)
                }
            }
        }
    }

    private func selectionPill(_ label: LocalizedStringKey, active: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: active ? .medium : .regular))
                .foregroundStyle(active ? DS.paper : DS.inkSoft)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(Capsule().fill(active ? DS.ink : Color.clear))
                .overlay(Capsule().strokeBorder(active ? Color.clear : DS.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func permissionCard(icon: String, title: LocalizedStringKey,
                                detail: LocalizedStringKey, granted: Bool,
                                action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(granted ? DS.blue : DS.coral)
                .frame(width: 30, height: 30)
                .background(Circle().fill((granted ? DS.blue : DS.coral).opacity(0.10)))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(DS.ink)
                    Text(granted ? "已授权" : "未授权")
                        .font(.system(size: 10)).foregroundStyle(granted ? DS.blue : DS.coral)
                }
                Text(detail).font(.system(size: 11)).lineSpacing(5).foregroundStyle(DS.muted)
            }
            Spacer()
            if !granted {
                Button("去授权", action: action).buttonStyle(SmallGhostPill())
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(DS.card)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DS.line, lineWidth: 1))
    }

    private func fieldLine(_ label: LocalizedStringKey, text: Binding<String>,
                           prompt: String, secure: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12)).foregroundStyle(DS.inkSoft)
                .frame(width: 70, alignment: .leading)
            Group {
                if secure {
                    SecureField("", text: text, prompt: Text(verbatim: prompt))
                } else {
                    TextField("", text: text, prompt: Text(verbatim: prompt))
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(DS.ink)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { DS.lineSoft.frame(height: 1) }
    }

    private var testButtonLabel: LocalizedStringKey {
        testState == .testing ? "连接中…" : "测试连接"
    }

    private var testMessage: LocalizedStringKey {
        switch testState {
        case .idle: "Key 只存在你的钥匙串里"
        case .testing: "正在问模型一句话"
        case .success: "连接正常"
        case .failure: "连接失败"
        }
    }

    private var testColor: Color {
        switch testState {
        case .success: DS.blue
        case .failure: DS.coral
        default: DS.faint
        }
    }

    private func requestScreenAccess() {
        if CGPreflightScreenCaptureAccess() {
            screenGranted = true
            return
        }
        if !CGRequestScreenCaptureAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        screenGranted = CGPreflightScreenCaptureAccess()
    }

    private func testModel() {
        settings.persistKey()
        guard let config = settings.llmConfig else { return }
        testState = .testing
        Task {
            do {
                _ = try await LLMClient.reply(
                    history: [(role: "user", content: "只回复：在。")], config: config)
                testState = .success
            } catch {
                testState = .failure(error.localizedDescription)
            }
        }
    }
}

#Preview("常规") { PetSettingsView(initialPane: .general) }
#Preview("感知") { PetSettingsView(initialPane: .sensing) }
#Preview("模型") { PetSettingsView(initialPane: .model) }
