import Foundation

enum AppFeatures {
    /// 暂时关闭云端 AI（打标 / 平铺图 / 虚拟试穿）。改回 true 即可恢复。
    static let aiEnabled = false

    /// iCloud / CloudKit 同步。
    /// Personal Team（免费）不支持 iCloud capability，必须保持 false 才能签名安装。
    /// 加入付费 Apple Developer Program 后：改为 true，并在 entitlements 中启用 CloudKit。
    static let iCloudSyncEnabled = false
}
