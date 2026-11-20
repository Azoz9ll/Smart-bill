//
//  Product.swift
//  Smart Bill
//
//  Purpose:
//  نموذج المنتج المستخدم في تحليل الفاتورة وعرض عناصرها.
//
//  Responsibilities:
//  - حمل الاسم والسعر والتصنيف والباركود الاختياري
//  - دعم Codable وهوية العنصر في الواجهة
//

//
//  Product.swift
//  Smart bill
//
//  Created by abdulaziz on 07/04/2026.
//

import Foundation

/// نموذج المنتج المستخدم في تحليل الفاتورة وعرض عناصرها.
struct Product: Identifiable, Codable {
    var id: Int
    var name: String
    var price: Double
    var barcode: String?
    var category: String
    /// False means price is unknown; the numeric placeholder must never be displayed or saved.
    var priceAvailable: Bool

    /// Parses API prices while preserving JSON null and invalid values as unavailable.
    static func receiptPrice(from rawValue: Any?) -> Double? {
        guard let rawValue, !(rawValue is NSNull) else { return nil }
        let value: Double?
        if let number = rawValue as? NSNumber {
            value = number.doubleValue
        } else if let string = rawValue as? String {
            value = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            value = nil
        }
        guard let value, value.isFinite, (0...100_000).contains(value) else { return nil }
        return value
    }

    static func receiptProduct(id: Int, name: String, rawPrice: Any?, category: String) -> Product {
        let parsedPrice = receiptPrice(from: rawPrice)
        return Product(
            id: id,
            name: name,
            price: parsedPrice ?? 0,
            category: category,
            priceAvailable: parsedPrice != nil
        )
    }

    static func knownReceiptTotal(_ products: [Product]) -> Double {
        products.filter(\.priceAvailable).reduce(0) { $0 + $1.price }
    }

    static func receiptPricesAreComplete(_ products: [Product]) -> Bool {
        !products.isEmpty && products.allSatisfy(\.priceAvailable)
    }

    init(id: Int, name: String, price: Double, barcode: String? = nil, category: String, priceAvailable: Bool = true) {
        self.id = id
        self.name = name
        self.price = price
        self.barcode = barcode
        self.category = category
        self.priceAvailable = priceAvailable
    }

    private enum CodingKeys: String, CodingKey { case id, name, price, barcode, category, priceAvailable }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        price = try values.decode(Double.self, forKey: .price)
        barcode = try values.decodeIfPresent(String.self, forKey: .barcode)
        category = try values.decode(String.self, forKey: .category)
        priceAvailable = try values.decodeIfPresent(Bool.self, forKey: .priceAvailable) ?? true
    }
}
