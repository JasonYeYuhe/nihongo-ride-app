# 设计资源 / Design assets

## App 图标(「Dash」系列)

由产品方提供。键盘小人骑行穿越目标语言所在国地图,红色路标上是该语言的标志性字符。

| 文件 | 目标语言 | 地图 | 标志字符 | 对应产品 |
|------|---------|------|---------|---------|
| `icons/jp.png` | 日语 | 日本 | え | **Nihongo Ride**(当前) |
| `icons/cn.png` | 中文 | 中国 | 中 | (未来) |
| `icons/fr.png` | 法语 | 法国 | é | (未来) |
| `icons/es.png` | 西班牙语 | 西班牙 | ñ | (未来) |
| `icons/kr.png` | 韩语 | 韩国 | 한 | (未来) |

原始尺寸 1254×1254。

## 由日文图标生成的 macOS 资源

- `AppIcon-1024.png` —— 1024 主图(运行时 Dock 图标也用它,见 `Sources/NihongoRideApp/Resources/AppIcon.png`)。
- `AppIcon.icns` —— 直接可用的 icns。
- `AppIcon.iconset/` —— 10 张标准尺寸(`iconutil` 源)。
- `AppIcon.appiconset/` —— **Xcode 用**:打包正式 App 时,把它拖进 Xcode 工程的 `Assets.xcassets`,在 target 设置里选作 App Icon 即可。

> SPM 的 `swift run` 不编译 asset catalog,所以开发运行时改为在 `AppDelegate` 里用 `NSApp.applicationIconImage` 加载 PNG;正式签名打包仍走 Xcode + `AppIcon.appiconset`。

重新生成(换图标时):见仓库脚本说明或用 `sips` + `iconutil`。
