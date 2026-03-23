import Foundation
#if canImport(UIKit)
import UIKit
#endif

protocol CloudDriveProvider: Identifiable {
    var id: String { get }
    var name: String { get }
    var iconName: String { get }
    var urlScheme: String { get }
    var description: String { get }
}

enum CloudDriveInstallChecker {
    @MainActor
    static func isInstalled(_ provider: any CloudDriveProvider) -> Bool {
        #if canImport(UIKit)
        guard let url = URL(string: "\(provider.urlScheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
        #else
        return false
        #endif
    }
}

struct BaiduNetdiskProvider: CloudDriveProvider {
    let id = "baidu_netdisk"
    let name = "百度网盘"
    let iconName = "cloud.fill"
    let urlScheme = "baidunetdisk"
    let description = "从百度网盘选择音乐文件导入"
}

enum CloudDriveRegistry {
    static let allProviders: [any CloudDriveProvider] = [
        BaiduNetdiskProvider()
    ]
}
