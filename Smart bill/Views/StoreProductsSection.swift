import SwiftUI
import Combine

struct StoreProductsSection: View {
    let searchText: String
    @StateObject private var model = StoreProductsViewModel()
    @State private var store = ""
    @State private var presentedSheet: StoreProductsSheet?
    @ObservedObject private var cartManager: CartManager = .shared
    @Environment(\.colorScheme) private var scheme
    private var style: SmartBillStyle { SmartBillStyle(scheme: scheme) }

    private var comparisonGroups: [ProductOfferGroup] {
        let supportedProducts = model.items.filter {
            StoreBrandMark.isSupported($0.store_name) && ($0.amount ?? 0) > 0
        }
        let grouped = Dictionary(grouping: supportedProducts, by: ProductOfferGroup.key(for:))
        return grouped.values.compactMap { products in
            guard let first = products.first else { return nil }
            let group = ProductOfferGroup(id: ProductOfferGroup.key(for: first), products: products)
            return group.cheapest == nil ? nil : group
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer()
                Button { presentedSheet = .cart } label: {
                    Label {
                        Text("السلة")
                        if cartManager.cartItemCount > 0 {
                            Text("\(cartManager.cartItemCount)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(style.accent, in: Capsule())
                        }
                    } icon: { Image(systemName: "cart") }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(style.accent)
                    .padding(.horizontal, 14).frame(minHeight: 42)
                    .background(style.surface)
                }
                .buttonStyle(.plain)
            }
            Menu {
                Button("كل المتاجر") { store = "" }
                ForEach(model.stores.filter { StoreBrandMark.isSupported($0) }, id: \.self) { name in
                    Button(name) { store = name }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease").foregroundStyle(style.accent)
                    Text(store.isEmpty ? "كل المتاجر" : store).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(style.secondary)
                }
                .foregroundStyle(style.primary)
                .padding(.horizontal, 15).frame(minHeight: SmartBillStyle.controlHeight)
                .background(style.surface)
            }
            HStack {
                Text("\(model.total) منتج في المتاجر")
                Spacer()
                Text("\(model.items.count) معروض")
            }
            .font(.caption.weight(.medium)).foregroundStyle(style.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(comparisonGroups) { group in
                    ProductCardView(group: group, style: style, cartManager: cartManager) {
                        if let product = group.cheapest {
                            presentedSheet = .details(product, group.pricedOffers)
                        }
                    }
                }
            }
            if model.loading { ProgressView().frame(maxWidth: .infinity) }
            if let error = model.error {
                Text(LocalizedStringKey(error)).font(.subheadline)
                Button("إعادة المحاولة") { reload(reset: model.items.isEmpty) }
            } else if !model.loading && model.items.isEmpty {
                Text("لا توجد منتجات تطابق البحث أو المتجر المحدد").padding(16)
            } else if model.hasMore && !model.loading {
                Button("عرض المزيد") { reload(reset: false) }.frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .tint(style.accent)
        .task(id: searchText + "|" + store) { await model.load(search: searchText, store: store) }
        .task { await model.loadStores() }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .details(let item, let offers):
                StoreProductDetails(item: item, initialOffers: offers, cartManager: cartManager)
            case .cart:
                CartView(cartManager: cartManager)
            }
        }
    }

    private func reload(reset: Bool) {
        Task { await model.load(search: searchText, store: store, reset: reset) }
    }
}

private enum StoreProductsSheet: Identifiable {
    case details(StoreProduct, [StoreProduct])
    case cart

    var id: String {
        switch self {
        case .details(let product, _): return "details-\(product.id)"
        case .cart: return "cart"
        }
    }
}

/// Products are compared only when their normalized names and package sizes match.
private struct ProductOfferGroup: Identifiable {
    let id: String
    let products: [StoreProduct]
    var name: String { products.first?.name ?? "" }
    var size: String? { products.first?.size }
    var pricedOffers: [StoreProduct] {
        products
            .filter { StoreBrandMark.isSupported($0.store_name) && ($0.amount ?? 0) > 0 }
            .sorted {
                let left = $0.amount ?? .infinity
                let right = $1.amount ?? .infinity
                return left == right ? $0.store_name.localizedStandardCompare($1.store_name) == .orderedAscending : left < right
            }
    }
    var cheapest: StoreProduct? { pricedOffers.first }
    var savings: Double? {
        guard let low = pricedOffers.first?.amount, let high = pricedOffers.last?.amount, pricedOffers.count > 1 else { return nil }
        return high - low
    }

    nonisolated static func key(for item: StoreProduct) -> String {
        let name = item.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ar"))
            .replacingOccurrences(of: "[\\p{Punctuation}\\s]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let size = (item.size ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ar"))
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        return "\(name)|\(size)"
    }
}

private struct ProductCardView: View {
    let group: ProductOfferGroup
    let style: SmartBillStyle
    @ObservedObject var actionStore: ProductActionStore = .shared
    @ObservedObject var cartManager: CartManager = .shared
    @State private var showingAddedConfirmation = false
    let open: () -> Void

    private var best: StoreProduct { group.cheapest ?? group.products[0] }
    private var key: String { group.id }
    private var quantityInCart: Int { cartManager.quantity(for: key) }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 10) {
                    CachedProductImage(source: best.image_url)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background(style.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                    Text(group.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(style.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)

                    if let size = group.size, !size.isEmpty {
                        Text(size)
                            .font(.caption)
                            .foregroundStyle(style.secondary)
                            .lineLimit(1)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(best.amount.map(SmartBillFormatting.money) ?? "السعر غير متاح")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(style.accent)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Spacer(minLength: 0)
                        if let percent = best.catalogDiscountPercent {
                            Text("−\(percent)%")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color(red: 0.72, green: 0.34, blue: 0.08))
                        }
                    }
                    Text(best.store_name)
                        .font(.caption)
                        .foregroundStyle(style.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .padding(.top, 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .topLeading) {
                Button {
                    actionStore.toggleFavorite(for: key)
                } label: {
                    Image(systemName: actionStore.isFavorite(key) ? "star.fill" : "star")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(actionStore.isFavorite(key) ? Color.orange : style.accent)
                        .frame(width: 34, height: 34)
                        .background(style.card, in: Circle())
                        .overlay(Circle().strokeBorder(style.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(actionStore.isFavorite(key) ? "إزالة من المفضلة" : "إضافة إلى المفضلة")
                .padding(9)
            }
            .overlay(alignment: .topTrailing) {
                if let percent = best.catalogDiscountPercent {
                    DiscountBadge(percent: percent)
                        .padding(9)
                }
            }

            Button {
                if cartManager.add(best, productKey: key) { showingAddedConfirmation = true }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                    if quantityInCart > 0 {
                        Text("\(quantityInCart)")
                            .font(.caption.weight(.bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(style.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(quantityInCart > 0 ? "إضافة أخرى إلى السلة، الكمية \(quantityInCart)" : "إضافة إلى السلة"))
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(style.card, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).strokeBorder(style.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .shadow(color: .black.opacity(0.055), radius: 12, y: 5)
        .alert("تمت الإضافة إلى السلة", isPresented: $showingAddedConfirmation) {
            Button("حسنًا", role: .cancel) { }
        } message: { Text(group.name) }
    }
}

private struct DiscountBadge: View {
    let percent: Int

    var body: some View {
        Text("خصم \(percent)%")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color(red: 0.91, green: 0.48, blue: 0.20), in: Capsule())
    }
}

private struct StoreBrandMark: View {
    let storeName: String
    let style: SmartBillStyle

    static func isSupported(_ name: String) -> Bool {
        mark(for: name) != nil
    }

    private static func mark(for name: String) -> String? {
        let normalized = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ar"))
        if normalized.contains("panda") || normalized.contains("باندا") { return "P" }
        if normalized.contains("tamimi") || normalized.contains("تميمي") || normalized.contains("التميمي") { return "T" }
        if normalized.contains("danube") || normalized.contains("دانوب") || normalized.contains("الدانوب") { return "D" }
        return nil
    }

    var body: some View {
        Text(Self.mark(for: storeName) ?? "")
            .font(.system(.caption, design: .rounded, weight: .heavy))
            .foregroundStyle(style.accent)
            .frame(width: 42, height: 42)
            .background(style.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel(Text(storeName))
    }
}

@MainActor
final class ProductActionStore: ObservableObject {
    static let shared = ProductActionStore()

    @Published private(set) var favoriteKeys: Set<String>

    private let defaults = UserDefaults.standard
    private let favoritesKey = "smartbill.productFavorites"

    private init() {
        favoriteKeys = Set(UserDefaults.standard.stringArray(forKey: "smartbill.productFavorites") ?? [])
    }

    func isFavorite(_ key: String) -> Bool { favoriteKeys.contains(key) }

    func toggleFavorite(for key: String) {
        if favoriteKeys.contains(key) { favoriteKeys.remove(key) }
        else { favoriteKeys.insert(key) }
        defaults.set(favoriteKeys.sorted(), forKey: favoritesKey)
    }

}

@MainActor
final class CartManager: ObservableObject {
    static let shared = CartManager()

    @Published private(set) var items: [CartLineItem]

    private let defaults = UserDefaults.standard
    private let storageKey = "smartbill.cartItems.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: "smartbill.cartItems.v1"),
           let restored = try? JSONDecoder().decode([CartLineItem].self, from: data) {
            items = restored.filter { $0.quantity > 0 && $0.unitPrice.isFinite && $0.unitPrice > 0 }
        } else {
            items = []
        }
        #if DEBUG
        print("[SmartBill Cart] restore manager=\(ObjectIdentifier(self)) count=\(items.count) items=\(items.map { "\($0.productID):\($0.name)x\($0.quantity)" })")
        #endif
    }

    var cartItemCount: Int { items.count }
    var totalQuantity: Int { items.reduce(0) { $0 + $1.quantity } }
    var totalValue: Double { items.reduce(0) { $0 + $1.subtotal } }
    func quantity(for productKey: String) -> Int {
        items.first(where: { $0.productKey == productKey })?.quantity ?? 0
    }

    @discardableResult
    func add(_ product: StoreProduct, productKey: String) -> Bool {
        guard let price = product.amount, price.isFinite, price > 0 else {
            #if DEBUG
            print("[SmartBill Cart] rejected productID=\(product.id) rawPrice=\(product.price) manager=\(ObjectIdentifier(self))")
            #endif
            return false
        }
        if let index = items.firstIndex(where: { $0.productKey == productKey }) {
            items[index].quantity += 1
        } else {
            items.append(CartLineItem(product: product, productKey: productKey))
        }
        persist()
        #if DEBUG
        print("[SmartBill Cart] add productID=\(product.id) name=\(product.name) manager=\(ObjectIdentifier(self)) count=\(items.count) quantity=\(quantity(for: productKey))")
        #endif
        return true
    }

    func increment(_ item: CartLineItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].quantity += 1
        persist()
    }

    func decrement(_ item: CartLineItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        if items[index].quantity <= 1 { items.remove(at: index) }
        else { items[index].quantity -= 1 }
        persist()
    }

    func remove(_ item: CartLineItem) {
        items.removeAll { $0.id == item.id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct CartLineItem: Codable, Identifiable, Equatable {
    let id: String
    let productID: Int
    let productKey: String
    let name: String
    let imageURL: String?
    let unitPrice: Double
    let storeName: String
    let currency: String
    let size: String?
    var quantity: Int
    var subtotal: Double { unitPrice * Double(quantity) }

    init(product: StoreProduct, productKey: String, quantity: Int = 1) {
        id = "product|\(productKey)"
        productID = product.id
        self.productKey = productKey
        name = product.name
        imageURL = product.image_url
        unitPrice = product.amount ?? 0
        storeName = product.store_name
        currency = product.currency
        size = product.size
        self.quantity = quantity
    }
}

struct StoreProductDetails: View {
    let item: StoreProduct
    let initialOffers: [StoreProduct]

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = StoreProductsViewModel()
    @State private var loadedProductID: Int?
    @State private var showingAddedConfirmation = false
    @State private var showingCart = false
    @ObservedObject private var cartManager: CartManager
    @ObservedObject private var actionStore: ProductActionStore

    private var style: SmartBillStyle { SmartBillStyle(scheme: scheme) }
    private var productKey: String { ProductOfferGroup.key(for: item) }
    private var offers: [StoreProduct] {
        var byID: [Int: StoreProduct] = [:]
        for offer in initialOffers + model.items + [item] {
            guard ProductOfferGroup.key(for: offer) == productKey,
                  StoreBrandMark.isSupported(offer.store_name),
                  (offer.amount ?? 0) > 0 else { continue }
            byID[offer.id] = offer
        }
        return byID.values.sorted {
            let left = $0.amount ?? .infinity
            let right = $1.amount ?? .infinity
            return left == right ? $0.store_name.localizedStandardCompare($1.store_name) == .orderedAscending : left < right
        }
    }
    private var cheapestOffer: StoreProduct? { offers.first }

    init(
        item: StoreProduct,
        initialOffers: [StoreProduct] = [],
        cartManager: CartManager? = nil,
        actionStore: ProductActionStore? = nil
    ) {
        self.item = item
        self.initialOffers = initialOffers
        _cartManager = ObservedObject(wrappedValue: cartManager ?? CartManager.shared)
        _actionStore = ObservedObject(wrappedValue: actionStore ?? ProductActionStore.shared)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    productInformation
                    storeComparison
                    if let error = model.error, !offers.isEmpty {
                        Text(LocalizedStringKey(error))
                            .font(.caption)
                            .foregroundStyle(style.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(style.background)
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomActionBar }
            .navigationTitle("تفاصيل المنتج")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { dismiss() }
                }
            }
            .task(id: item.id) { await loadMatchingOffers() }
            .alert("تمت الإضافة إلى السلة", isPresented: $showingAddedConfirmation) {
                Button("متابعة التسوق", role: .cancel) { }
                Button("عرض السلة") { showingCart = true }
            } message: { Text((cheapestOffer ?? item).name) }
        }
        .tint(style.accent)
        .sheet(isPresented: $showingCart) { CartView(cartManager: cartManager) }
    }

    private var productInformation: some View {
        VStack(alignment: .leading, spacing: 15) {
            CachedProductImage(source: item.image_url)
                .frame(maxWidth: .infinity)
                .aspectRatio(1.2, contentMode: .fit)
                .background(style.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(item.name)
                    .font(.title3.bold())
                    .foregroundStyle(style.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let size = item.size, !size.isEmpty {
                    Text(size)
                        .font(.subheadline)
                        .foregroundStyle(style.secondary)
                }
                HStack(spacing: 8) {
                    Text(cheapestOffer?.amount.map(SmartBillFormatting.money) ?? item.amount.map(SmartBillFormatting.money) ?? "السعر غير متاح")
                        .font(.title2.bold())
                        .foregroundStyle(style.accent)
                        .monospacedDigit()
                    if let percent = cheapestOffer?.catalogDiscountPercent {
                        DiscountBadge(percent: percent)
                    }
                }
                if let cheapestOffer {
                    Label("أفضل سعر لدى \(cheapestOffer.store_name)", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(style.accent)
                }
                if let url = item.originalURL {
                    Link("فتح صفحة المنتج في المتجر", destination: url)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var storeComparison: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("الأسعار في المتاجر")
                .font(.headline)
                .foregroundStyle(style.primary)
            if model.loading && offers.isEmpty {
                stateCard {
                    ProgressView().tint(style.accent)
                    Text("جاري تحميل أسعار المتاجر")
                        .font(.subheadline)
                        .foregroundStyle(style.secondary)
                }
            } else if let error = model.error, offers.isEmpty {
                stateCard {
                    Text(LocalizedStringKey(error))
                        .font(.subheadline)
                        .foregroundStyle(style.secondary)
                        .multilineTextAlignment(.center)
                    Button("إعادة المحاولة") { Task { await loadMatchingOffers(force: true) } }
                        .font(.subheadline.weight(.semibold))
                }
            } else if offers.isEmpty {
                stateCard {
                    Text("لا توجد أسعار مطابقة لهذا المنتج في المتاجر المدعومة")
                        .font(.subheadline)
                        .foregroundStyle(style.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(offers.enumerated()), id: \.element.id) { index, offer in
                        StoreOfferRow(offer: offer, isCheapest: index == 0, style: style)
                    }
                }
            }
        }
    }

    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Button {
                if cartManager.add(cheapestOffer ?? item, productKey: productKey) {
                    showingAddedConfirmation = true
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                    Text(cartManager.quantity(for: productKey) > 0
                         ? "أُضيفت للسلة (\(cartManager.quantity(for: productKey)))"
                         : "إضافة إلى السلة")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(style.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                actionStore.toggleFavorite(for: productKey)
            } label: {
                Image(systemName: actionStore.isFavorite(productKey) ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(actionStore.isFavorite(productKey) ? Color.orange : style.accent)
                    .frame(width: 52, height: 52)
                    .background(style.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(style.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(actionStore.isFavorite(productKey) ? "إزالة من المفضلة" : "إضافة إلى المفضلة")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(style.background.opacity(0.97))
    }

    private func stateCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 10, content: content)
            .frame(maxWidth: .infinity)
            .padding(18)
            .background(style.surface)
    }

    private func loadMatchingOffers(force: Bool = false) async {
        guard !model.loading else { return }
        if force || loadedProductID != item.id {
            loadedProductID = item.id
            await model.load(search: item.name, store: "", reset: true)
        }
        // The catalog API pages by search/store and exposes only per-store row IDs.
        // Fetch the name search pages, then keep exact normalized name-and-size matches.
        while !Task.isCancelled && model.error == nil && model.hasMore {
            await model.load(search: item.name, store: "", reset: false)
        }
    }
}

struct CartView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cartManager: CartManager
    private var style: SmartBillStyle { SmartBillStyle(scheme: scheme) }

    init(cartManager: CartManager? = nil) {
        _cartManager = StateObject(wrappedValue: cartManager ?? CartManager.shared)
    }

    var body: some View {
        NavigationStack {
            Group {
                if cartManager.items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "cart").font(.system(size: 38)).foregroundStyle(style.accent)
                        Text("السلة فارغة").font(.headline).foregroundStyle(style.primary)
                        Text("أضف منتجات من قائمة المتاجر لتظهر هنا").font(.subheadline).foregroundStyle(style.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(cartManager.items) { item in cartRow(item) }
                        }
                        .padding(16).frame(maxWidth: 680).frame(maxWidth: .infinity)
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) { totalBar }
                }
            }
            .background(style.background)
            .navigationTitle("سلة المشتريات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } }
            }
        }
        .tint(style.accent)
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            #if DEBUG
            print("[SmartBill Cart] viewAppear manager=\(ObjectIdentifier(cartManager)) count=\(cartManager.items.count) items=\(cartManager.items.map { "\($0.productID):\($0.name)x\($0.quantity)" })")
            #endif
        }
    }

    private func cartRow(_ item: CartLineItem) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                CachedProductImage(source: item.imageURL)
                    .frame(width: 76, height: 76)
                    .background(style.background, in: RoundedRectangle(cornerRadius: 13))
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(style.primary).lineLimit(2)
                    if let size = item.size, !size.isEmpty { Text(size).font(.caption).foregroundStyle(style.secondary) }
                    Text(item.storeName).font(.caption).foregroundStyle(style.secondary)
                }
                Spacer(minLength: 0)
                Button(role: .destructive) { cartManager.remove(item) } label: {
                    Image(systemName: "trash").frame(width: 38, height: 38)
                }
                .accessibilityLabel("حذف \(item.name)")
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("سعر الوحدة: \(SmartBillFormatting.money(item.unitPrice))")
                        .font(.caption).foregroundStyle(style.secondary)
                    Text("المجموع: \(SmartBillFormatting.money(item.subtotal))")
                        .font(.subheadline.weight(.bold)).foregroundStyle(style.accent)
                }
                Spacer()
                HStack(spacing: 14) {
                    Button { cartManager.decrement(item) } label: {
                        Image(systemName: item.quantity == 1 ? "minus" : "minus")
                            .frame(width: 36, height: 36).background(style.background, in: Circle())
                    }.accessibilityLabel("تقليل الكمية")
                    Text("\(item.quantity)").font(.subheadline.bold()).monospacedDigit().frame(minWidth: 20)
                    Button { cartManager.increment(item) } label: {
                        Image(systemName: "plus").frame(width: 36, height: 36)
                            .foregroundStyle(.white).background(style.accent, in: Circle())
                    }.accessibilityLabel("زيادة الكمية")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14).background(style.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(style.border, lineWidth: 1))
    }

    private var totalBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("الإجمالي").font(.caption).foregroundStyle(style.secondary)
                Text(SmartBillFormatting.money(cartManager.totalValue)).font(.title3.bold()).foregroundStyle(style.primary)
            }
            Spacer()
            Text("\(cartManager.totalQuantity) منتجات").font(.subheadline.weight(.semibold)).foregroundStyle(style.accent)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(style.card.shadow(color: .black.opacity(0.08), radius: 8, y: -3))
    }
}

private struct StoreOfferRow: View {
    let offer: StoreProduct
    let isCheapest: Bool
    let style: SmartBillStyle

    var body: some View {
        HStack(spacing: 12) {
            StoreBrandMark(storeName: offer.store_name, style: style)
            VStack(alignment: .leading, spacing: 5) {
                Text(offer.store_name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(style.primary)
                    .lineLimit(1)
                if isCheapest {
                    Text("الأقل سعراً")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(style.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 5) {
                Text(offer.amount.map(SmartBillFormatting.money) ?? "السعر غير متاح")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isCheapest ? style.accent : style.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                HStack(spacing: 6) {
                    if let old = offer.catalogPreviousAmount {
                        Text(SmartBillFormatting.money(old))
                            .font(.caption2)
                            .foregroundStyle(style.secondary)
                            .strikethrough()
                            .monospacedDigit()
                    }
                    if let percent = offer.catalogDiscountPercent {
                        Text("−\(percent)%")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color(red: 0.72, green: 0.34, blue: 0.08))
                    }
                }
            }
        }
        .padding(14)
        .background(isCheapest ? style.accent.opacity(0.08) : style.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isCheapest ? style.accent.opacity(0.34) : style.border, lineWidth: 1)
        }
    }
}

private extension StoreProduct {
    var catalogPreviousAmount: Double? {
        guard let old_price,
              let value = Double(old_price.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.isFinite, value > (amount ?? 0) else { return nil }
        return value
    }

    var catalogDiscountPercent: Int? {
        guard let old = catalogPreviousAmount, let amount, old > 0 else { return nil }
        return Int(((old - amount) / old * 100).rounded())
    }
}

@MainActor
private enum ProductImageCache {
    static let images = NSCache<NSURL, UIImage>()
    static let session = URLSession(configuration: {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32_000_000, diskCapacity: 128_000_000)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return config
    }())
}

struct CachedProductImage: View {
    let source: String?
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "shippingbox").resizable().scaledToFit().padding(24).foregroundStyle(.secondary) }
        }
        .task(id: source) {
            image = nil
            guard let source, let url = URL(string: source), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
            if let cached = ProductImageCache.images.object(forKey: url as NSURL) { image = cached; return }
            do {
                let (data, response) = try await ProductImageCache.session.data(from: url)
                try Task.checkCancellation()
                guard (response as? HTTPURLResponse)?.statusCode == 200, let decoded = UIImage(data: data) else { return }
                ProductImageCache.images.setObject(decoded, forKey: url as NSURL, cost: data.count)
                image = decoded
            } catch { }
        }
    }
}
