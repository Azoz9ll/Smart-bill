import Foundation

enum StoreProductsServiceError: LocalizedError {
    case configuration
    case invalidRequest
    case invalidURL
    case invalidResponse
    case invalidPayload
    case connection
    case server(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .configuration:
            return "خدمة المنتجات غير مهيأة. اضبط عنوان HTTPS لخادم SmartBill في إعدادات التشغيل."
        case .invalidRequest:
            return "رقم صفحة المنتجات غير صالح."
        case .invalidURL:
            return "عنوان خدمة المنتجات غير صالح."
        case .invalidResponse, .invalidPayload:
            return "استجابة خدمة المنتجات غير صالحة. حاول مرة أخرى لاحقًا."
        case .connection:
            return "تعذر الاتصال بخدمة المنتجات. تحقق من الإنترنت وحاول مرة أخرى."
        case .server(let statusCode) where statusCode == 401 || statusCode == 403:
            return "لا يسمح الخادم بقراءة المنتجات."
        case .server(let statusCode) where statusCode == 404:
            return "مسار خدمة المنتجات غير موجود على الخادم."
        case .server(let statusCode) where statusCode >= 500:
            return SmartBillLanguage.selected == .english
                ? "The product service is temporarily unavailable (server status: \(statusCode))."
                : "خدمة المنتجات غير متاحة مؤقتًا (رمز الخادم: \(statusCode))."
        case .server(let statusCode):
            return SmartBillLanguage.selected == .english
                ? "Could not load products (server status: \(statusCode))."
                : "تعذر تحميل المنتجات (رمز الخادم: \(statusCode))."
        }
    }
}

struct StoreProduct: Codable, Identifiable, Sendable {
    let id: Int
    let store_name: String
    let name: String
    let price: String
    let old_price: String?
    let currency: String
    let product_url: String
    let image_url: String?
    let size: String?
    let updated_at: String
    var amount: Double? {
        guard let value = Double(price), value.isFinite, value >= 0 else { return nil }
        return value
    }
    var originalURL: URL? {
        guard let url = URL(string: product_url), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
}

struct StoreProductsPage: Codable, Sendable {
    let products: [StoreProduct]
    let total: Int
    let page: Int
    let per_page: Int
}

struct StoreProductsService {
    var session: URLSession = .shared
    func fetch(page: Int, search: String, store: String) async throws -> StoreProductsPage {
        guard page > 0 else { throw StoreProductsServiceError.invalidRequest }
        let endpoint: URL
        do {
            endpoint = try ServerConfig.endpoint(
                "get_store_products.php",
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "per_page", value: "30"),
                    URLQueryItem(name: "search", value: search),
                    URLQueryItem(name: "store", value: store)
                ]
            )
        } catch {
            throw StoreProductsServiceError.configuration
        }
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw StoreProductsServiceError.connection
        }
        guard let http = response as? HTTPURLResponse else { throw StoreProductsServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw StoreProductsServiceError.server(statusCode: http.statusCode) }
        let result: StoreProductsPage
        do {
            result = try JSONDecoder().decode(StoreProductsPage.self, from: data)
        } catch {
            throw StoreProductsServiceError.invalidPayload
        }
        guard result.page > 0, result.per_page > 0, result.total >= 0,
              result.products.count <= result.per_page else {
            throw StoreProductsServiceError.invalidPayload
        }
        return result
    }
}
