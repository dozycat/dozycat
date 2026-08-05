import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var keySaved = false

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                modelSection
            }
            .tint(DS.coral)
            .navigationTitle(Text("设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var languageSection: some View {
        Section {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack {
                    Text("语言")
                        .foregroundStyle(DS.ink)
                    Spacer()
                    Text(currentLanguageLabel)
                        .foregroundStyle(DS.muted)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.faint)
                }
            }
        } footer: {
            Text("懒猫跟随系统语言。点这里去系统设置，可以为懒猫单独选语言。")
        }
    }

    private var currentLanguageLabel: String {
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    private var modelSection: some View {
        Section {
            Picker(selection: Binding(
                get: { settings.provider },
                set: { newValue in
                    settings.provider = newValue
                    settings.baseURL = ""
                    settings.model = ""
                }
            )) {
                ForEach(LLMProvider.allCases) { provider in
                    Text(provider.label).tag(provider)
                }
            } label: {
                Text("服务商")
            }

            if settings.provider == .custom {
                TextField("Base URL", text: $settings.baseURL, prompt: Text(verbatim: "https://…/v1"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            TextField(text: $settings.model,
                      prompt: Text(verbatim: settings.provider.defaultModel)) {
                Text("模型名")
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            SecureField(text: $settings.apiKey, prompt: Text(verbatim: "sk-…")) {
                Text(verbatim: "API Key")
            }
            .onChange(of: settings.apiKey) { _, _ in keySaved = false }

            Button {
                settings.persistKey()
                keySaved = true
            } label: {
                Text(keySaved ? "已保存" : "保存 Key")
            }
            .disabled(keySaved)
        } header: {
            Text("模型（自带 Key）")
        } footer: {
            Text("不配置也能聊，会用内置的懒猫回复。配置后，聊天走你自己的模型；Key 只存在钥匙串，经 iCloud 钥匙串在你的设备间端到端同步，不经过任何我们的服务器。")
        }
    }
}

#Preview {
    SettingsView()
}
