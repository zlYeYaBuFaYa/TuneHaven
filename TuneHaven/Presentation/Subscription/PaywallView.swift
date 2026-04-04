import SwiftUI

struct PaywallView: View {
    let triggerFeature: PremiumFeature?

    @EnvironmentObject private var subscriptionService: SubscriptionService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProduct: SubscriptionProduct?
    @State private var purchaseError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    featureListSection
                    productSection
                    purchaseButton
                    footerSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .adaptiveBackground()
            .navigationTitle("TuneHaven Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.surface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(palette.primary)
                }
            }
            .task {
                if subscriptionService.products.isEmpty {
                    await subscriptionService.loadProducts()
                }
                if selectedProduct == nil {
                    selectedProduct = subscriptionService.products.first { $0.type == .autoRenewable }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [palette.primary, palette.primaryDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("解锁全部高级功能")
                .font(.title3.weight(.semibold))
                .foregroundColor(palette.textPrimary)

            if let feature = triggerFeature {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                    Text("\(feature.displayName) 需要 Premium")
                        .font(.subheadline)
                }
                .foregroundColor(palette.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(palette.primary.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Feature List

    private var featureListSection: some View {
        VStack(spacing: 0) {
            ForEach(PremiumFeature.allCases, id: \.self) { feature in
                featureRow(feature)
                if feature != PremiumFeature.allCases.last {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func featureRow(_ feature: PremiumFeature) -> some View {
        let isHighlighted = feature == triggerFeature
        return HStack(spacing: 12) {
            Image(systemName: featureIcon(feature))
                .font(.body)
                .foregroundColor(isHighlighted ? palette.primary : palette.textSecondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.displayName)
                    .font(.subheadline.weight(isHighlighted ? .semibold : .regular))
                    .foregroundColor(palette.textPrimary)
                Text(featureDescription(feature))
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(palette.primary)
                .font(.body)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isHighlighted ? palette.primary.opacity(0.05) : Color.clear)
    }

    private func featureIcon(_ feature: PremiumFeature) -> String {
        switch feature {
        case .losslessPlayback:   return "waveform"
        case .premiumTheme:       return "paintbrush.fill"
        case .webDAVImport:       return "server.rack"
        case .onlineLyricsSearch: return "text.magnifyingglass"
        }
    }

    private func featureDescription(_ feature: PremiumFeature) -> String {
        switch feature {
        case .losslessPlayback:   return "FLAC、WAV、AIFF、ALAC、CAF"
        case .premiumTheme:       return "暮光玫瑰、星际穹顶等高级主题"
        case .webDAVImport:       return "坚果云、NAS 等 WebDAV 服务器"
        case .onlineLyricsSearch: return "LRCLIB 在线歌词匹配与搜索"
        }
    }

    // MARK: - Product Cards

    @ViewBuilder
    private var productSection: some View {
        if subscriptionService.products.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.title2)
                    .foregroundColor(palette.textTertiary)
                Text("商品加载失败，请检查网络")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                Button("重试") {
                    Task { await subscriptionService.loadProducts() }
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(palette.primary)
            }
            .padding(.vertical, 20)
        } else {
            VStack(spacing: 12) {
                ForEach(subscriptionService.products) { product in
                    productCard(product)
                }
            }
        }
    }

    private func productCard(_ product: SubscriptionProduct) -> some View {
        let isSelected = selectedProduct?.id == product.id
        return Button {
            selectedProduct = product
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(product.displayName)
                            .font(.headline)
                            .foregroundColor(palette.textPrimary)
                        if product.type == .nonConsumable {
                            Text("推荐")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(palette.primary)
                                .clipShape(Capsule())
                        }
                    }
                    Text(product.type == .autoRenewable
                         ? "\(product.displayPrice)/年 · 自动续费"
                         : "\(product.displayPrice) · 一次性永久解锁")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? palette.primary : palette.textTertiary)
            }
            .padding(16)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? palette.primary : palette.separator, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        VStack(spacing: 8) {
            Button {
                guard let product = selectedProduct else { return }
                Task {
                    do {
                        purchaseError = nil
                        try await subscriptionService.purchase(product)
                        if subscriptionService.tier == .premium { dismiss() }
                    } catch {
                        purchaseError = error.localizedDescription
                    }
                }
            } label: {
                HStack {
                    if subscriptionService.isPurchasing {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(subscriptionService.isPurchasing ? "处理中..." : buttonTitle)
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(selectedProduct == nil || subscriptionService.isPurchasing
                              ? palette.textTertiary
                              : palette.primary)
                )
            }
            .disabled(selectedProduct == nil || subscriptionService.isPurchasing)

            if let error = purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var buttonTitle: String {
        guard let product = selectedProduct else { return "选择方案" }
        return product.type == .autoRenewable ? "立即订阅" : "立即购买"
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 12) {
            Button("恢复购买") {
                Task { await subscriptionService.restorePurchases() }
            }
            .font(.subheadline)
            .foregroundColor(palette.primary)

            if let error = subscriptionService.restoreError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack(spacing: 16) {
                let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
                let privacyURL = URL(string: "https://tunehaven.app/privacy")
                if let termsURL {
                    Link("使用条款", destination: termsURL)
                }
                if termsURL != nil && privacyURL != nil {
                    Text("·").foregroundColor(palette.textTertiary)
                }
                if let privacyURL {
                    Link("隐私政策", destination: privacyURL)
                }
            }
            .font(.caption)
            .foregroundColor(palette.textSecondary)

            Text("订阅将在确认购买时从您的 Apple ID 账户收费。\n订阅到期前 24 小时内自动续费，除非在到期前关闭自动续费。")
                .font(.caption2)
                .foregroundColor(palette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(.bottom, 16)
    }
}
