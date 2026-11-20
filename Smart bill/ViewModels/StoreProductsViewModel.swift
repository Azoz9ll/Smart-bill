import Foundation
import Combine

@MainActor
final class StoreProductsViewModel: ObservableObject {
    @Published var items: [StoreProduct] = []
    @Published var stores: [String] = []
    @Published var total = 0
    @Published var loading = false
    @Published var error: String?
    private var page = 0
    private var generation = UUID()
    private let service = StoreProductsService()
    var hasMore: Bool { items.count < total }

    func load(search: String, store: String, reset: Bool = true) async {
        if !reset && loading { return }
        let token = reset ? UUID() : generation
        generation = token
        if reset { items = []; total = 0; page = 0 }
        loading = true
        error = nil
        do {
            if reset { try await Task.sleep(for: .milliseconds(300)) }
            let result = try await service.fetch(page: page + 1, search: search, store: store)
            try Task.checkCancellation()
            guard generation == token else { return }
            items += result.products
            total = result.total
            page = result.page
            stores = Array(Set(stores + result.products.map(\.store_name))).sorted()
        } catch is CancellationError {
        } catch {
            guard generation == token else { return }
            if let serviceError = error as? StoreProductsServiceError {
                self.error = serviceError.errorDescription
            } else {
                self.error = "تعذر تحميل المنتجات. تحقق من اتصال الشبكة وحاول مرة أخرى."
            }
        }
        if generation == token { loading = false }
    }

    // The endpoint has no store facet; enumerate the catalog independently of search.
    func loadStores() async {
        var next = 1
        var names = Set<String>()
        do {
            while true {
                let result = try await service.fetch(page: next, search: "", store: "")
                try Task.checkCancellation()
                names.formUnion(result.products.map(\.store_name))
                if next * result.per_page >= result.total { break }
                next += 1
            }
            stores = names.sorted()
        } catch { /* Product request presents connection errors and retry. */ }
    }
}
