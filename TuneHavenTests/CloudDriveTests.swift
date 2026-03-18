import Testing
import Foundation
@testable import TuneHaven

// MARK: - CloudDriveProvider Protocol Tests

@Suite("CloudDriveProvider Tests")
struct CloudDriveProviderTests {

    // MARK: - BaiduNetdiskProvider 属性

    @Test("BaiduNetdiskProvider id 正确")
    func testBaiduProviderId() {
        let provider = BaiduNetdiskProvider()
        #expect(provider.id == "baidu_netdisk")
    }

    @Test("BaiduNetdiskProvider name 为百度网盘")
    func testBaiduProviderName() {
        let provider = BaiduNetdiskProvider()
        #expect(provider.name == "百度网盘")
    }

    @Test("BaiduNetdiskProvider iconName 为 cloud.fill")
    func testBaiduProviderIconName() {
        let provider = BaiduNetdiskProvider()
        #expect(provider.iconName == "cloud.fill")
    }

    @Test("BaiduNetdiskProvider urlScheme 为 baidunetdisk")
    func testBaiduProviderURLScheme() {
        let provider = BaiduNetdiskProvider()
        #expect(provider.urlScheme == "baidunetdisk")
    }

    @Test("BaiduNetdiskProvider description 非空")
    func testBaiduProviderDescription() {
        let provider = BaiduNetdiskProvider()
        #expect(!provider.description.isEmpty)
    }

    @Test("BaiduNetdiskProvider 遵循 Identifiable 协议")
    func testBaiduProviderIdentifiable() {
        let provider = BaiduNetdiskProvider()
        let _: String = provider.id
        #expect(true)
    }

    // MARK: - CloudDriveRegistry

    @Test("CloudDriveRegistry 包含百度网盘")
    func testRegistryContainsBaidu() {
        let providers = CloudDriveRegistry.allProviders
        let hasBaidu = providers.contains { $0.id == "baidu_netdisk" }
        #expect(hasBaidu, "CloudDriveRegistry 应包含百度网盘")
    }

    @Test("CloudDriveRegistry 至少有 1 个 Provider")
    func testRegistryNotEmpty() {
        #expect(!CloudDriveRegistry.allProviders.isEmpty)
    }

    @Test("CloudDriveRegistry 中每个 Provider 的 id 唯一")
    func testRegistryUniqueIds() {
        let ids = CloudDriveRegistry.allProviders.map { $0.id }
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count, "所有 Provider id 应该唯一")
    }

    @Test("CloudDriveRegistry 中每个 Provider 的 name 非空")
    func testRegistryProviderNamesNotEmpty() {
        for provider in CloudDriveRegistry.allProviders {
            #expect(!provider.name.isEmpty, "\(provider.id) 的 name 不应为空")
        }
    }

    @Test("CloudDriveRegistry 中每个 Provider 的 iconName 非空")
    func testRegistryProviderIconNamesNotEmpty() {
        for provider in CloudDriveRegistry.allProviders {
            #expect(!provider.iconName.isEmpty, "\(provider.id) 的 iconName 不应为空")
        }
    }

    @Test("CloudDriveRegistry 中每个 Provider 的 urlScheme 非空")
    func testRegistryProviderURLSchemesNotEmpty() {
        for provider in CloudDriveRegistry.allProviders {
            #expect(!provider.urlScheme.isEmpty, "\(provider.id) 的 urlScheme 不应为空")
        }
    }

    @Test("CloudDriveRegistry 中每个 Provider 的 urlScheme 可构造合法 URL")
    func testRegistryProviderURLSchemesValid() {
        for provider in CloudDriveRegistry.allProviders {
            let url = URL(string: "\(provider.urlScheme)://")
            #expect(url != nil, "\(provider.id) 的 urlScheme 应能构造合法 URL")
        }
    }
}

// MARK: - SandboxPathManager CloudDrive Extension Tests
// TODO: 待 SandboxPathManager.cloudDriveTempURL 实现后恢复测试
