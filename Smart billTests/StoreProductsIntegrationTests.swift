import XCTest
import UIKit
@testable import Smart_bill

@MainActor
final class StoreProductsIntegrationTests: XCTestCase {
    func testRealCatalogAndImages() async throws {
        let service = StoreProductsService()
        let page = try await service.fetch(page: 1, search: "", store: "")
        XCTAssertGreaterThan(page.total, 0)
        for item in page.products {
            XCTAssertGreaterThan(item.amount, 0)
            XCTAssertEqual(item.currency, "SAR")
            let results = try await service.fetch(page: 1, search: item.name, store: item.store_name)
            XCTAssertTrue(results.products.contains { $0.id == item.id })
            let source = try XCTUnwrap(item.image_url)
            let url = try XCTUnwrap(URL(string: source))
            let (data, response) = try await URLSession.shared.data(from: url)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            XCTAssertNotNil(UIImage(data: data), "iOS must decode the real image")
        }
        let missing = try await service.fetch(page: 1, search: "smartbill-no-match-934697", store: "")
        XCTAssertEqual(missing.total, 0)
        XCTAssertTrue(missing.products.isEmpty)
        let beyond = try await service.fetch(page: 2, search: "", store: "")
        XCTAssertTrue(beyond.products.isEmpty)
    }

    func testReceiptHistoryStillLoads() async throws {
        let url = try XCTUnwrap(URL(string: ServerConfig.baseURL + "/get_receipts.php"))
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let receipts = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertFalse(receipts.isEmpty)
        XCTAssertTrue(receipts.contains { ($0["items"] as? [[String: Any]])?.isEmpty == false })
    }

    @MainActor
    func testCatalogViewModelUsesRealRecords() async {
        let model = StoreProductsViewModel()
        await model.load(search: "", store: "")
        XCTAssertNil(model.error)
        XCTAssertFalse(model.loading)
        XCTAssertFalse(model.items.isEmpty)
        await model.load(search: "smartbill-no-match-934697", store: "")
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertEqual(model.total, 0)
    }

    func testNetworkFailurePropagates() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineProtocol.self]
        let service = StoreProductsService(session: URLSession(configuration: configuration))
        do {
            _ = try await service.fetch(page: 1, search: "", store: "")
            XCTFail("Expected network error")
        } catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
    }
}

private final class OfflineProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() { }
}
