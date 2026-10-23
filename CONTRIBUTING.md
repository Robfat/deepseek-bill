# 贡献指南

欢迎 issue 和 PR。

## 开发

```bash
./build.sh          # 编译 + 打包 + ad-hoc 签名
open DeepSeekBill.app
```

源码结构：

| 文件 | 职责 |
| --- | --- |
| `main.swift` | AppKit 入口 |
| `AppDelegate.swift` | 菜单栏、桌面层窗口、显示/隐藏逻辑 |
| `Views.swift` | SwiftUI 界面（毛玻璃卡片、图表、列表） |
| `API.swift` | 官方接口调用与解析 |
| `Model.swift` | 状态与刷新 |
| `Config.swift` | 凭据读取 |

## 提交前

- 不要提交 `~/Library/Application Support/DeepSeekBill/config.json` 或任何真实凭据
- 界面改动请附一张截图
- 接口字段如有变化，请说明平台返回的原始结构

## 许可

贡献的代码默认按 MIT 协议提交。
