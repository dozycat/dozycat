import SwiftUI

/// 桌宠设置窗——懒猫设计语言（纸色、墨字、珊瑚点缀），不是系统 Form。
/// BYOK 配置与 iOS 共用同一个 SettingsStore / Keychain 条目。
struct PetSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var keySaved = false
    @AppStorage("uiLanguage") private var uiLanguage = "zh"
    @AppStorage("uiAppearance") private var uiAppearance = "system"
    @AppStorage("presenceSensing") private var presenceSensing = false
    @State private var languageChanged = false

    var body: some View {
        VStack(spacing: 0) {
            hero
            section(title: "语言") {
                HStack {
                    Text("界面语言")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.ink)
                    Spacer()
                    languagePill("跟随系统", value: "system")
                    languagePill("中文", value: "zh")
                    languagePill("EN", value: "en")
                }
                if languageChanged {
                    caption("重启懒猫后生效。")
                }
            }
            section(title: "外观") {
                HStack {
                    Text("亮暗")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.ink)
                    Spacer()
                    appearancePill("跟随系统", value: "system")
                    appearancePill("亮", value: "light")
                    appearancePill("暗", value: "dark")
                }
            }
            section(title: "感知") {
                HStack {
                    Text("摄像头在位感知")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.ink)
                    Spacer()
                    Toggle("", isOn: $presenceSensing)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .onChange(of: presenceSensing) { _, on in
                            PresenceSensor.shared.setEnabled(on)
                        }
                }
                caption("开着时它知道你在不在屏幕前：看视频不再被误当成休息，真离开两分钟就开始回血。画面在内存里过一遍人脸检测就丢，不截图不落盘；摄像头指示灯会常亮。")
            }
            section(title: "模型") {
                providerPicker
                if settings.provider == .custom {
                    underlinedField("Base URL", text: $settings.baseURL, prompt: "https://…/v1")
                }
                underlinedField("模型名", text: $settings.model,
                                prompt: settings.provider.defaultModel)
                underlinedField("API Key", text: $settings.apiKey, prompt: "sk-…", secure: true)
                    .onChange(of: settings.apiKey) { keySaved = false }

                HStack {
                    Spacer()
                    Button(keySaved ? String(localized: "已保存") : String(localized: "保存 Key")) {
                        settings.persistKey()
                        keySaved = true
                    }
                    .buttonStyle(InkPillStyle())
                    .disabled(keySaved)
                    .opacity(keySaved ? 0.5 : 1)
                    Spacer()
                }
                .padding(.top, 6)
                caption("Key 只在你的钥匙串里。")
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .frame(width: 380)
        .background(DS.paper)
    }

    // MARK: 组件

    private var hero: some View {
        VStack(spacing: 8) {
            CatFace(size: 76, breathing: true)
            Text("设置")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(DS.ink)
        }
        .padding(.top, 20)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }

    private func section(title: LocalizedStringKey,
                         @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11))
                .tracking(2.2)
                .foregroundStyle(DS.muted)
                .padding(.top, 18)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { DS.line.frame(height: 1) }
        .padding(.top, 14)
    }

    private func languagePill(_ label: LocalizedStringKey, value: String) -> some View {
        let active = uiLanguage == value
        return Button {
            guard uiLanguage != value else { return }
            uiLanguage = value
            DozycatPetApp.applyLanguagePreference()
            languageChanged = true
        } label: {
            Text(label)
                .font(.system(size: 12, weight: active ? .medium : .regular))
                .foregroundStyle(active ? DS.paper : DS.inkSoft)
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .background(Capsule().fill(active ? DS.ink : Color.clear))
                .overlay(Capsule().stroke(active ? Color.clear : DS.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func appearancePill(_ label: LocalizedStringKey, value: String) -> some View {
        let active = uiAppearance == value
        return Button {
            guard uiAppearance != value else { return }
            uiAppearance = value
            PetAppDelegate.applyAppearancePreference()  // 立即生效，不用重启
        } label: {
            Text(label)
                .font(.system(size: 12, weight: active ? .medium : .regular))
                .foregroundStyle(active ? DS.paper : DS.inkSoft)
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .background(Capsule().fill(active ? DS.ink : Color.clear))
                .overlay(Capsule().stroke(active ? Color.clear : DS.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var providerPicker: some View {
        HStack(spacing: 8) {
            ForEach(LLMProvider.allCases) { provider in
                let active = settings.provider == provider
                Button {
                    settings.provider = provider
                    settings.baseURL = ""
                    settings.model = ""
                    keySaved = false
                } label: {
                    Text(verbatim: provider.label)
                        .font(.system(size: 12, weight: active ? .medium : .regular))
                        .foregroundStyle(active ? DS.paper : DS.inkSoft)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 14)
                        .background(
                            Capsule().fill(active ? DS.ink : Color.clear)
                        )
                        .overlay(
                            Capsule().stroke(active ? Color.clear : DS.lineStrong, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func underlinedField(_ label: LocalizedStringKey, text: Binding<String>,
                                 prompt: String, secure: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(DS.ink)
                .frame(width: 74, alignment: .leading)
            Group {
                if secure {
                    SecureField("", text: text, prompt: Text(verbatim: prompt))
                } else {
                    TextField("", text: text, prompt: Text(verbatim: prompt))
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(DS.ink)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { DS.lineSoft.frame(height: 1) }
    }

    private func caption(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(size: 11))
            .lineSpacing(4)
            .foregroundStyle(DS.faint)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var currentLanguageLabel: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let displayLocale = Locale(identifier: code)
        return displayLocale.localizedString(forLanguageCode: code) ?? code
    }
}

#Preview {
    PetSettingsView()
}
