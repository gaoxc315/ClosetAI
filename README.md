# ClosetAI

> 🤖 本项目 100% 由 AI 构建，欢迎各位开发者自由使用。如果在使用过程中遇到任何问题，建议直接去问问 AI —— 毕竟它比我更了解这段代码。

> A family wardrobe management iOS app built with SwiftUI. Organize clothes by family member and custom categories, build outfits by hand, and optionally turn on cloud AI (auto-tagging, AI collage, virtual try-on) with your own DashScope API key.

[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-26.0+-blue)](https://developer.apple.com/ios/)
[![Xcode](https://img.shields.io/badge/Xcode-26-blue)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## 📽️ Demo
- 衣橱页面
<img src="https://picui.ogmua.cn/s1/2026/11/11/6af488bd2eddf.webp" width="320">
- 穿搭页面
<img src="https://picui.ogmua.cn/s1/2026/11/11/6af488b89d6bc.webp" width="320">
- 设置页面
<img src="https://picui.ogmua.cn/s1/2026/11/11/6af488d599e2f.webp" width="320">

---

## ✨ Features

> **当前默认关闭云端 AI。** 所有功能在本地运行，不需要 API Key。如需恢复 AI，见下文「开启云端 AI」。

### 衣橱管理（Wardrobe）
- 👨‍👩‍👧 **家庭成员分级** — 顶部成员栏（全部 / 各成员 / 未分配）筛选衣物；添加衣物时可指定归属，详情页可随时改
- 🗂️ **左侧分类栏** — 分类上下等分铺满左侧，停在底部 Tab 栏之上，底色与页面一致；分类可在设置中自定义
- 🧱 **三列网格** — 任意屏幕宽度都固定三列，图片按正方形裁切，不会撑出屏幕
- 🖼️ **背景消除 + 平铺图** — 本地 Vision 去背景，生成标准化 flat-lay 展示图
- 🔍 **双指缩放** — 详情页平铺图支持双指放大、拖动、双击切换，可全屏查看
- 🔎 **搜索** — 跨类别、颜色、风格、备注、成员名的实时搜索
- ✏️ **标签编辑** — 单选大类（来自自定义分类），多选季节 / 场合，自由编辑小类 / 图案 / 备注

### 穿搭（Outfit）
- 👥 **按成员区分** — 穿搭页顶部成员栏筛选（全部 / 各成员）；旧穿搭会按所含衣物自动推断归属
- ✋ **手动组搭** — 按成员、分类筛选，手动选取最多 4 件单品，本地生成拼图
- 🎨 **AI 平铺图 / 虚拟试穿** — 需开启云端 AI

### 设置（Settings）
- ☁️ **iCloud 同步** — 衣物、穿搭、分类与图片经 CloudKit 私有库同步；换机登录同一 Apple ID 即可恢复
- 🏷️ **衣橱分类** — 增删、改名、换图标；按住 ≡ 自由拖动排序，顺序即衣橱左侧显示顺序（「全部」固定在最上）。改名会同步已有衣物，删除分类不会删除衣物
- 👨‍👩‍👧 **家庭成员** — 增删、改名；按住 ≡ 自由拖动排序，顺序即衣橱 / 穿搭顶部成员栏的顺序。删除成员后其衣物回到「未分配」
- 📊 **统计** — 衣物总数、颜色分布、近 90 天未穿
- 🗑️ **数据管理** — 清空已删除的衣物

---

## 🏗️ Architecture

```
ClosetAI/
├── App/                  # ClosetAIApp, ContentView（TabView：衣橱 / 穿搭 / 设置）
├── Models/               # ClothingTags, ClothingItemModel, OutfitModel
├── Persistence/          # CoreData + CloudKit（ClothingItem / FamilyMember / Outfit / WearLog / CategoryConfig）
├── Services/
│   ├── AliyunService.swift          # DashScope API（打标 / 拼图 / 试穿，AI 关闭时不调用）
│   └── ImageProcessingService.swift # 去背景、平铺图、本地拼图、Documents 双写
├── ViewModels/
│   ├── WardrobeViewModel.swift  # 衣物 CRUD、成员筛选与排序、搜索、统计
│   └── OutfitViewModel.swift    # 穿搭保存、成员归属推断、拼图
├── Views/
│   ├── Components/       # ViewExtensions（Toast、Tab 样式项、系统 Tab 栏封装）, AsyncImageView（本地图、缩放）, TagView
│   ├── Wardrobe/         # WardrobeView, ClothingDetailView, FamilyMemberViews, CameraView
│   ├── Outfit/           # OutfitView, ManualOutfitView, TryOnView
│   └── Settings/         # SettingsView（统计、iCloud 同步状态、分类管理、成员入口）
├── Utilities/
│   ├── AppFeatures.swift    # 功能开关（aiEnabled）
│   ├── CategoryStore.swift  # 自定义衣橱分类（Core Data CategoryConfig + CloudKit）
│   └── AppColors.swift
├── ClosetAI.entitlements # iCloud CloudKit 容器
└── Resources/            # Assets（含 AppIcon）, model_person.png（试穿默认模特图占位）
```

**Pattern:** SwiftUI + MVVM + Core Data（`NSPersistentCloudKitContainer`）

**数据存储：**
- 衣物、成员、穿搭、穿着记录、自定义分类 → Core Data，经 CloudKit 私有库同步
- 图片 → Documents 本地缓存 + Core Data Binary（`allowsExternalBinaryDataStorage`，随 CloudKit 同步）
- 当前成员筛选 → UserDefaults（仅本机 UI 状态）
- iCloud 容器：`iCloud.com.gaoxiancheng.closetai`

**Dependency:** [Kingfisher](https://github.com/onevcat/Kingfisher)（已声明，目前代码未使用）

---

## 📱 Requirements

| Item | Requirement |
|------|-------------|
| iOS | 26.0+ |
| Xcode | 26 |
| Device | iPhone（拍照需相机） |
| Apple ID | 真机需登录 iCloud；CloudKit 需付费开发者账号启用容器 |
| Tool（可选） | [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) |
| API（可选） | [阿里云 DashScope](https://dashscope.aliyun.com/) 按量计费 API Key，仅开启 AI 时需要 |

---

## 🚀 Getting Started

### 1. Clone

```bash
git clone https://github.com/<your-username>/ClosetAI.git
cd ClosetAI
```

仓库已包含 `ClosetAI.xcodeproj`，可直接打开。

### 2. Configure Signing & iCloud

在 Xcode 的 **Signing & Capabilities** 中选择你的 Team。工程已包含 CloudKit entitlement（容器 `iCloud.com.gaoxiancheng.closetai`）。

若改 Bundle Identifier，请同步修改：

1. `ClosetAI.entitlements` 中的 iCloud 容器 ID  
2. `PersistenceController.cloudKitContainerID`  
3. `project.yml` / Xcode 的 `PRODUCT_BUNDLE_IDENTIFIER`  

首次在真机运行时，Xcode 会在 CloudKit **Development** 环境自动创建 schema。上架前请在 [CloudKit Console](https://icloud.developer.apple.com/) 将 schema 部署到 **Production**。

如果使用 XcodeGen，同步修改 `project.yml` 后执行 `xcodegen generate`。

> ⚠️ `xcodegen generate` 会按 `project.yml` 重新生成工程，覆盖在 Xcode 里手动改过的设置。

### 3. Run on Device

```bash
open ClosetAI.xcodeproj
```

选择你的 iPhone，按 **Run**（⌘R）。首次安装需在手机 **设置 → 通用 → VPN 与设备管理** 中信任开发者证书。免费 Apple ID 签名的 App 7 天后需重新安装。

命令行编译（Xcode 不在默认路径时需指定 `DEVELOPER_DIR`）：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project ClosetAI.xcodeproj -scheme ClosetAI -destination 'generic/platform=iOS' build
```

---

## 🤖 开启云端 AI（可选）

AI 功能由 `ClosetAI/Utilities/AppFeatures.swift` 控制：

```swift
enum AppFeatures {
    static let aiEnabled = false   // 改为 true 恢复 AI
}
```

| Function | Model | API |
|----------|-------|-----|
| 服装自动打标 | `qwen-vl-plus` | DashScope OpenAI-compatible endpoint |
| AI 穿搭平铺图 | `wan2.6-image` | DashScope multimodal generation |
| 虚拟试穿 | `wan2.6-image` | DashScope multimodal generation |

注意：
- 当前版本已移除设置页里的 API Key 与默认模特图配置入口。开启 AI 后需要自行恢复这部分 UI，或在代码中提供 Key。
- 必须使用 DashScope **按量计费** 的 API Key。**通义 Coding Plan 的 `sk-sp-` Key 不能用于这些接口**，调用会返回 401。

---

## ☁️ 换机 / 多设备

1. 旧机登录 iCloud，打开 ClosetAI，在 **设置 → iCloud 同步** 确认状态为「已开启」，等待衣橱同步完成  
2. 新机登录 **同一 Apple ID**，安装并打开 ClosetAI  
3. 等待 CloudKit 拉取；衣物、穿搭、分类与图片会自动出现，无需重新导入  

未登录 iCloud 时 App 仍可离线使用，数据仅保存在本机。

---

## 🔒 Privacy & Security

- **默认本地 + 私有 iCloud** — 衣物与图片同步到你的 Apple ID 私有 CloudKit 数据库，不经过第三方服务器  
- **无统计、无追踪**
- **开启 AI 后** — 衣物照片和模特（人像）照片会上传到阿里云 DashScope；API Key 存于 iOS Keychain，但仍在客户端，存在被提取的风险，不建议把带额度的 Key 打包分发给他人

---

## 🗺️ Roadmap

- [ ] 缩略图缓存，优化大衣橱滚动性能
- [ ] 穿搭与衣物改用 CoreData 关系，彻底删除衣物时同步清理穿搭
- [ ] 删除分类时可选择将衣物迁移到其他分类
- [ ] 穿着日历
- [x] iCloud / CloudKit 同步
- [ ] Widget — 每日穿搭提醒

---

## 🤝 Contributing

欢迎提交 Pull Request。较大的改动请先开 Issue 讨论。

1. 按上面的 Getting Started 跑通项目
2. 新增 Swift 文件后，确认已加入 `ClosetAI.xcodeproj` 的编译目标（或改 `project.yml` 后执行 `xcodegen generate`）

---

## 📄 License

[MIT](LICENSE)

---

## 📚 Technical Documentation

See [TECH_REPORT_v2.0.md](TECH_REPORT_v2.0.md) for detailed architecture notes, CoreData schema, and build instructions.
