import SwiftUI

struct SettingsSubscriptionSection: View {
    @Binding var isExpanded: Bool

    @EnvironmentObject private var subscriptionService: SubscriptionService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.settingsListRowBg) private var listRowBg

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $isExpanded) {
                statusRow

                if subscriptionService.tier != .premium || subscriptionService.status.isTrial {
                    Button {
                        router.present(.paywall(feature: nil))
                    } label: {
                        Label {
                            Text("查看 Premium 权益")
                                .font(.subheadline)
                                .foregroundColor(palette.primary)
                        } icon: {
                            Image(systemName: "sparkles")
                                .foregroundColor(palette.primary)
                        }
                    }
                    .listRowBackground(listRowBg)
                }

                Button {
                    Task { await subscriptionService.restorePurchases() }
                } label: {
                    Label {
                        Text("恢复购买")
                            .font(.subheadline)
                            .foregroundColor(palette.textPrimary)
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(palette.primary)
                    }
                }
                .listRowBackground(listRowBg)

                Link(destination: AppURLs.manageSubscriptions) {
                    Label {
                        Text("管理订阅")
                            .font(.subheadline)
                            .foregroundColor(palette.textPrimary)
                    } icon: {
                        Image(systemName: "arrow.up.right.square")
                            .foregroundColor(palette.primary)
                    }
                }
                .listRowBackground(listRowBg)

                if let error = subscriptionService.restoreError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(SemanticColor.danger(for: colorScheme))
                        .listRowBackground(listRowBg)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("曲库本地优先，基础播放无需订阅。Premium 解锁无损播放、高级主题、WebDAV 与在线歌词。")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                    Text("隐私政策可在浏览器中打开。若链接暂时无法访问，请稍后再试或通过 App Store 产品页查看。")
                        .font(.caption2)
                        .foregroundColor(palette.textTertiary)
                }
                .listRowBackground(listRowBg)
            } label: {
                Label {
                    Text("订阅管理")
                        .foregroundColor(palette.textPrimary)
                } icon: {
                    SettingsSectionIcon(systemName: "crown")
                }
            }
            .tint(palette.textSecondary)
            .listRowBackground(listRowBg)
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch subscriptionService.status {
        case .trial(let days):
            HStack {
                Label {
                    Text("试用期")
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                } icon: {
                    Image(systemName: "clock")
                        .foregroundColor(palette.primary)
                }
                Spacer()
                Text("剩余 \(days) 天")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }
            .listRowBackground(listRowBg)
        case .subscribed(let date):
            HStack {
                Label {
                    Text("年度订阅")
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(palette.primary)
                }
                Spacer()
                Text("到期：\(date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }
            .listRowBackground(listRowBg)
        case .lifetime:
            HStack {
                Label {
                    Text("终身会员")
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                } icon: {
                    Image(systemName: "crown.fill")
                        .foregroundColor(palette.primary)
                }
                Spacer()
                Text("永久有效")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }
            .listRowBackground(listRowBg)
        case .expired:
            HStack {
                Label {
                    Text("免费版")
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                } icon: {
                    Image(systemName: "person")
                        .foregroundColor(palette.textSecondary)
                }
                Spacer()
                Text("功能受限")
                    .font(.subheadline)
                    .foregroundColor(palette.textTertiary)
            }
            .listRowBackground(listRowBg)
        }
    }
}
