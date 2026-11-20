import SwiftUI

/// The supermarket catalog; receipt scanning and history live in their own tabs.
struct CategoriesView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var searchText = ""
    private var style: SmartBillStyle { SmartBillStyle(scheme: scheme) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("منتجاتي")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text("أسعار ومنتجات المتاجر")
                            .font(.subheadline).foregroundStyle(style.secondary)
                    }
                    searchField
                    StoreProductsSection(searchText: searchText)
                }
                .padding(SmartBillStyle.horizontalInset).padding(.bottom, 12)
                .frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .foregroundStyle(style.primary)
            .background(style.background)
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(style.background, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
        }
        .tint(style.accent)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(style.accent)
            TextField("ابحث عن منتج...", text: $searchText)
                .font(.body).autocorrectionDisabled().submitLabel(.search)
                .accessibilityIdentifier("catalogSearch")
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(style.secondary).frame(width: 44, height: 44)
                }.accessibilityLabel("مسح البحث")
            }
        }
        .padding(.horizontal, 16).frame(minHeight: SmartBillStyle.controlHeight)
        .background(style.surface).buttonStyle(.plain)
    }
}

#Preview { CategoriesView() }
