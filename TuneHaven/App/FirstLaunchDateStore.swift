import Foundation

/// 首次启动日期同时记在 Keychain 和 UserDefaults。Keychain 卸载重装后仍保留，
/// 读取时取两者较早的值，避免重装或改系统时间后重新开始试用。
struct FirstLaunchDateStore {
    let defaults: UserDefaults
    let loadKeychain: () -> Data?
    let saveKeychain: (Data) throws -> Void

    static let keychainKey = AppStorageKey.appFirstLaunchDate

    static let live = FirstLaunchDateStore(
        defaults: .standard,
        loadKeychain: { KeychainHelper.load(forKey: keychainKey) },
        saveKeychain: { try KeychainHelper.save($0, forKey: keychainKey) }
    )

    func earliestDate() -> Date? {
        [keychainDate(), defaultsDate()].compactMap { $0 }.min()
    }

    /// 没有记录时写入 `now`；两边不一致时都改成较早的值。
    func recordIfNeeded(now: Date = Date()) {
        let date = earliestDate() ?? now
        if defaultsDate() != date {
            defaults.set(date, forKey: AppStorageKey.appFirstLaunchDate)
        }
        if keychainDate() != date {
            do {
                try saveKeychain(Data(String(date.timeIntervalSince1970).utf8))
            } catch {
                ErrorLogger.shared.logGeneric(error, context: "FirstLaunchDateStore 写入 Keychain 失败")
            }
        }
    }

    private func defaultsDate() -> Date? {
        defaults.object(forKey: AppStorageKey.appFirstLaunchDate) as? Date
    }

    private func keychainDate() -> Date? {
        guard let data = loadKeychain(),
              let seconds = TimeInterval(String(decoding: data, as: UTF8.self)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
