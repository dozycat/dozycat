import SwiftUI

/// 桌宠设置窗——懒猫设计语言（纸色、墨字、珊瑚点缀），不是系统 Form。
/// BYOK 配置与 iOS 共用同一个 SettingsStore / Keychain 条目。
struct PetSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @State private var keySaved = false

    var body: some View {
        VStack(spacing: 0) {
            hero
            section(title: "语言") {
                HStack {
                    Text("跟随系统")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.ink)
                    Spacer()
                    Text(currentLanguageLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(DS.muted)
                }
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
                    Button(keySaved ? "已保存" : "保存 Key") {
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
        .preferredColorScheme(.light)
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
                    Text(provider.label)
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
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}

#Preview {
    PetSettingsView()
}
