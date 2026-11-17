import SwiftUI

struct PaywallView: View {
    let triggerFeature: PremiumFeature?

    @EnvironmentObject private var subscriptionService: SubscriptionService
    @EnvironmentObject private var router: AppRouter
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProductID: String?
    @State private var isRestoring = false
    private var selectedProduct: SubscriptionProduct? {
        subscriptionService.products.first { $0.id == selectedProductID }
    }
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
            .themeNavigationBarSurface()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .foregroundColor(palette.textPrimary)
                }
            }
            .task {
                if subscriptionService.products.isEmpty { await subscriptionService.loadProducts() }
                selectAvailableProduct()
            }
            .onChange(of: subscriptionService.products.map(\.id)) { _, _ in selectAvailableProduct() }
            .onChange(of: subscriptionService.status) { _, status in
                switch status {
                case .lifetime, .subscribed: dismiss()
                default: break
                }
            }
        }
    }

    private func selectAvailableProduct() {
        guard selectedProduct == nil else { return }
        selectedProductID = (subscriptionService.products.first { $0.type == .autoRenewable } ?? subscriptionService.products.first)?.id
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 32))
                .foregroundColor(palette.accent)
                .frame(width: 76, height: 76)
                .background(palette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 24))
                .accessibilityHidden(true)

            Text("解锁更多聆听方式")
                .font(.title2.weight(.semibold))
                .foregroundColor(palette.textPrimary)

            if let feature = triggerFeature {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                    Text("\(feature.displayName) 需要 Premium")
                        .font(.subheadline)
                }
                .foregroundColor(palette.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(palette.accent.opacity(0.1))
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
        .background(palette.surface.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private func featureRow(_ feature: PremiumFeature) -> some View {
        let isHighlighted = feature == triggerFeature
        return HStack(spacing: 12) {
            Image(systemName: featureIcon(feature))
                .font(.body)
                .foregroundColor(isHighlighted ? palette.accent : palette.textSecondary)
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
                .foregroundColor(palette.accent)
                .font(.body)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isHighlighted ? palette.accent.opacity(0.05) : Color.clear)
    }

    private func featureIcon(_ feature: PremiumFeature) -> String {
        switch feature {
        case .losslessPlayback:   return "waveform"
        case .webDAVImport:       return "server.rack"
        case .onlineLyricsSearch: return "text.magnifyingglass"
        }
    }

    private func featureDescription(_ feature: PremiumFeature) -> String {
        switch feature {
        case .losslessPlayback:   return "FLAC、WAV、AIFF、ALAC、CAF"
        case .webDAVImport:       return "坚果云、NAS 等 WebDAV 服务器"
        case .onlineLyricsSearch: return "LRCLIB 在线歌词匹配与搜索"
        }
    }

    // MARK: - Product Cards

    @ViewBuilder
    private var productSection: some View {
        if subscriptionService.products.isEmpty {
            VStack(spacing: 12) {
                if subscriptionService.isLoadingProducts {
                    ProgressView("正在获取购买方案…")
                        .tint(palette.accent).foregroundColor(palette.textSecondary)
                } else {
                    Image(systemName: "wifi.slash")
                        .font(.title2)
                        .foregroundColor(palette.textSecondary)
                    Text(subscriptionService.productLoadError ?? "暂时没有可用的购买方案")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                    Button("重试") {
                        Task { await subscriptionService.loadProducts() }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(palette.accent)
                    .frame(minHeight: 44)
                }
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
            selectedProductID = product.id
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
                                .foregroundColor(palette.onAction)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(palette.actionFill)
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
                    .foregroundColor(isSelected ? palette.accent : palette.textSecondary)
            }
            .padding(16)
            .background(palette.surface.opacity(0.76))
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(isSelected ? palette.accent : palette.separator, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(subscriptionService.isPurchasing || isRestoring)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        VStack(spacing: 8) {
            Button {
                guard let product = selectedProduct else { return }
                Task {
                    do {
                        purchaseError = nil
                        let result = try await subscriptionService.purchase(product)
                        if case .success = result, subscriptionService.tier == .premium { dismiss() }
                    } catch {
                        purchaseError = error.localizedDescription
                    }
                }
            } label: {
                HStack {
                    if subscriptionService.isPurchasing {
                        ProgressView()
                            .tint(palette.onAction)
                    }
                    Text(subscriptionService.isPurchasing ? "处理中..." : buttonTitle)
                }
                .font(.headline)
                .foregroundColor(palette.onAction)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(palette.actionFill, in: Capsule())
                .opacity(selectedProduct == nil || subscriptionService.isPurchasing || isRestoring ? 0.5 : 1)
            }
            .disabled(selectedProduct == nil || subscriptionService.isPurchasing || isRestoring || subscriptionService.pendingProductID != nil)

            if subscriptionService.pendingProductID != nil {
                Label("购买正在等待批准。批准后，Premium 权益会自动更新，无需重复购买。", systemImage: "clock")
                    .font(.subheadline).foregroundColor(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(SemanticColor.danger(for: colorScheme))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var buttonTitle: String {
        guard let product = selectedProduct else { return "选择方案" }
        if subscriptionService.pendingProductID != nil { return "等待批准" }
        return product.type == .autoRenewable ? "立即订阅" : "立即购买"
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 12) {
            Button(isRestoring ? "正在恢复购买…" : "恢复购买") {
                guard !isRestoring else { return }
                isRestoring = true
                Task {
                    await subscriptionService.restorePurchases()
                    isRestoring = false
                    switch subscriptionService.status {
                    case .lifetime, .subscribed: dismiss()
                    default: break
                    }
                }
            }
            .frame(minHeight: 44)
            .disabled(isRestoring || subscriptionService.isPurchasing)
            .font(.subheadline)
            .foregroundColor(palette.accent)

            if let error = subscriptionService.restoreError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(SemanticColor.danger(for: colorScheme))
            }

            HStack(spacing: 16) {
                Link("使用条款", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Text("·").foregroundColor(palette.textSecondary)
                Link("隐私政策", destination: AppURLs.privacyPolicy)
                Text("·").foregroundColor(palette.textSecondary)
                Link("管理订阅", destination: AppURLs.manageSubscriptions)
            }
            .font(.caption)
            .foregroundColor(palette.textSecondary)

            Text("订阅将在确认购买时从您的 Apple ID 账户收费。\n订阅到期前 24 小时内自动续费，除非在到期前关闭自动续费。")
                .font(.caption2)
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(.bottom, 16)
    }
}
