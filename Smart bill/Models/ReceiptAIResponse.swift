import Foundation

/// Lossily decodes item rows so one malformed row cannot discard its neighbors.
nonisolated struct LossyReceiptItem: Decodable {
    let value: ReceiptAIItem?

    init(from decoder: Decoder) throws {
        value = try? ReceiptAIItem(from: decoder)
    }
}

/// The extraction contract returned directly by analyze_receipt.php.
nonisolated struct ReceiptAIResponse: Decodable {
    let store: String
    let currency: String
    let vatAmount: Double?
    let invoiceTotal: Double?
    let items: [ReceiptAIItem]

    enum CodingKeys: String, CodingKey {
        case store, currency, items
        case vatAmount = "vat_amount"
        case invoiceTotal = "invoice_total"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        store = ((try? container.decode(String.self, forKey: .store)) ?? "").receiptWhitespaceCleaned
        currency = ((try? container.decode(String.self, forKey: .currency)) ?? "").receiptWhitespaceCleaned
        vatAmount = try? container.decodeIfPresent(Double.self, forKey: .vatAmount)
        invoiceTotal = try? container.decodeIfPresent(Double.self, forKey: .invoiceTotal)
        let decodedRows = try container.decode([LossyReceiptItem].self, forKey: .items)
        items = decodedRows.compactMap(\.value)
        #if DEBUG
        if decodedRows.count != items.count {
            print("Receipt analysis discarded \(decodedRows.count - items.count) rows without a usable product name")
        }
        #endif
    }

    static func parse(_ text: String) -> ReceiptAIResponse? {
        guard let data = text.data(using: .utf8),
              let response = try? JSONDecoder().decode(Self.self, from: data) else {
            #if DEBUG
            print("Receipt analysis JSON decode failed")
            #endif
            return nil
        }
        return response
    }
}

/// A receipt line keeps readable data even when optional values are unknown.
nonisolated struct ReceiptAIItem: Decodable {
    let name: String
    let quantity: Int?
    let size: String
    let price: Double?
    let lineTotal: Double?
    let category: String

    enum CodingKeys: String, CodingKey {
        case name, quantity, size, price, category
        case unitPrice = "unit_price"
        case lineTotal = "line_total"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawName = try container.decode(String.self, forKey: .name)
        size = ((try? container.decode(String.self, forKey: .size)) ?? "").receiptWhitespaceCleaned
        name = Self.cleanName(rawName, size: size)
        guard !name.isEmpty else { throw ValidationError.invalidName }

        let rawQuantity = try? container.decodeIfPresent(Int.self, forKey: .quantity)
        quantity = rawQuantity.flatMap { (1...1000).contains($0) ? $0 : nil }

        let rawPrice = try? container.decodeIfPresent(Double.self, forKey: .price)
        let rawUnitPrice = try? container.decodeIfPresent(Double.self, forKey: .unitPrice)
        let rawLineTotal = try? container.decodeIfPresent(Double.self, forKey: .lineTotal)
        lineTotal = rawLineTotal.flatMap { Self.isValidLineTotal($0) ? $0 : nil }
        price = Self.validatedUnitPrice(
            price: rawPrice,
            quantity: quantity,
            explicitUnitPrice: rawUnitPrice,
            lineTotal: lineTotal
        )

        let proposedCategory = ((try? container.decode(String.self, forKey: .category)) ?? "").receiptWhitespaceCleaned
        let allowed: Set<String> = ["مشروبات", "أطعمة", "مخبوزات", "حلويات", "منظفات", "أخرى"]
        category = allowed.contains(proposedCategory) ? proposedCategory : "أخرى"
    }

    enum ValidationError: Error { case invalidName }

    static func isValidPrice(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= 100_000
    }

    private static func isValidLineTotal(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value <= 1_000_000
    }

    /// Uses only a unit-price field; never derives a unit price from a line total.
    static func validatedUnitPrice(
        price: Double?,
        quantity: Int?,
        explicitUnitPrice: Double?,
        lineTotal: Double?
    ) -> Double? {
        let selected = [price, explicitUnitPrice].compactMap { $0 }.first(where: isValidPrice)
        guard let selected,
              let quantity, quantity > 1,
              let lineTotal, lineTotal > 0 else { return selected }

        let q = Double(quantity)
        let tolerance = max(0.02, q * 0.005)
        if abs(q * selected - lineTotal) <= tolerance { return selected }
        if let explicitUnitPrice, isValidPrice(explicitUnitPrice),
           abs(q * explicitUnitPrice - lineTotal) <= tolerance,
           abs(selected - lineTotal) <= 0.02 {
            return explicitUnitPrice
        }
        return selected
    }

    static func cleanName(_ raw: String, size: String) -> String {
        let name = raw.receiptWhitespaceCleaned
        guard !size.isEmpty,
              size.range(of: #"\d\s*(?:جم|غ|كجم|مل|لتر|kg|g|ml|l)\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil else { return name }
        let escaped = NSRegularExpression.escapedPattern(for: size)
            .replacingOccurrences(of: " ", with: #"\s*"#)
        let pattern = #"\s+(?:"# + escaped + #")$"#
        let cleaned = name.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
            .receiptWhitespaceCleaned
        return cleaned.isEmpty ? name : cleaned
    }
}

private extension String {
    nonisolated var receiptWhitespaceCleaned: String {
        replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
