import SwiftUI
import CoreImage.CIFilterBuiltins

@MainActor
final class DeviceLinkModel: ObservableObject {
    static let shared = DeviceLinkModel()
    @Published var status = LinkCoordinator.Snapshot()
    @Published var error = ""
    let coordinator: LinkCoordinator
    private init() {
        let service = (Bundle.main.bundleIdentifier ?? "com.paperboytm.dozycat.pet") + ".device-link.v1"
        coordinator = LinkCoordinator(vault: LinkVault(storage: KeychainLinkStorage(service: service)))
        coordinator.changed = { [weak self] in self?.status = $0 }
    }
    func perform(_ operation: () throws -> Void) {
        error = ""
        do { try operation() } catch { self.error = "操作未完成，请检查本机钥匙串和局域网权限后重试。" }
    }
}

struct DeviceLinkView: View {
    @ObservedObject private var model = DeviceLinkModel.shared
    @State private var removing = false
    private var qr: NSImage? {
        guard !model.status.invitation.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(model.status.invitation.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 6, y: 6)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.status.paired ? "已绑定手机" : "让手机和电脑上的懒猫相认")
                .font(.system(size: 16, weight: .medium))
            Text("在同一 Wi-Fi 中扫码连接，不需要账号。")
                .font(.system(size: 12)).foregroundStyle(DS.muted)
            if let qr {
                HStack {
                    Spacer()
                    Image(nsImage: qr).interpolation(.none).resizable()
                        .frame(width: 190, height: 190).padding(12).background(.white)
                        .accessibilityLabel("两分钟内有效的一次性设备连接码")
                    Spacer()
                }
                Text("打开手机「设置 → 我的设备」扫码。二维码只允许一次连接尝试。")
                    .font(.system(size: 11)).foregroundStyle(DS.muted)
            }
            if !model.status.message.isEmpty {
                Text(model.status.message).font(.system(size: 12))
            }
            if model.status.phase == "compare" {
                Text(model.status.fingerprint).font(.system(size: 18, design: .monospaced)).textSelection(.enabled)
                Text("请完整核对手机上的八组字符，再允许连接。")
                    .font(.system(size: 12)).foregroundStyle(DS.muted)
                Button(model.status.approved ? "已确认，等待手机" : "一致，允许这台手机") { [fingerprint = model.status.fingerprint] in
                    model.perform { try model.coordinator.approve(expectedFingerprint: fingerprint) }
                }.disabled(model.status.approved)
                Button("不一致，取消连接") { model.coordinator.cancel() }
            } else if model.status.phase == "connected" {
                Text("加密连接已就绪。小传自动同步尚未开放。")
                    .font(.system(size: 12)).foregroundStyle(DS.muted)
                Button("断开连接") { model.coordinator.cancel() }
            } else if ["idle", "error"].contains(model.status.phase) {
                Button(model.status.paired ? "等待已绑定手机连接" : "添加手机") {
                    model.perform { try model.coordinator.host() }
                }
            } else {
                Button("取消连接") { model.coordinator.cancel() }
            }
            if model.status.paired {
                if removing {
                    Text("移除后需重新扫码。不会远程删除手机已收到的数据。")
                        .font(.system(size: 12)).foregroundStyle(DS.muted)
                    HStack {
                        Button("确认移除", role: .destructive) {
                            model.perform { try model.coordinator.removeDevice(); removing = false }
                        }
                        Button("保留手机") { removing = false }
                    }
                } else { Button("移除已绑定手机") { removing = true } }
            }
            if !model.error.isEmpty { Text(model.error).font(.system(size: 12)).foregroundStyle(DS.coral) }
        }
        .buttonStyle(.bordered)
        .task { model.perform { try model.coordinator.refresh() } }
        .onDisappear { if model.status.phase != "connected" { model.coordinator.cancel() } }
    }
}
