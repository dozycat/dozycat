# macOS 应用身份

只保留两种应用：

| 配置 | 应用 | Bundle ID | 图标 |
| --- | --- | --- | --- |
| Release | `/Applications/dozycat.app` | `com.paperboytm.dozycat.pet` | 珊瑚色猫咪 |
| Debug | `/Applications/dozycat-debug.app` | `com.paperboytm.dozycat.pet.debug` | 蓝色猫咪 + DEV |

开发版运行 `scripts/install-debug.sh` 构建并更新固定安装位置（需要本机 Developer ID 证书）。正式版仍使用 `scripts/package-dmg.sh` 生成 DMG。

测试包、恢复副本和 DerivedData 放在 `build.noindex/`，避免 Spotlight 列出 smoke、old、candidate 等重复应用。`scripts/prepare-build-dir.sh` 会把已有 `build/` 移过去，并保留 `build -> build.noindex` 符号链接兼容旧路径；打包和 Debug 安装脚本会自动调用它。手动构建时也请使用 `-derivedDataPath build.noindex/DerivedData`。

运行 `scripts/make-icon.sh` 可重建两套 AppIcon：正式版主图来自 iOS，Debug 主图为 `Assets/AppIconDebug.png`。
