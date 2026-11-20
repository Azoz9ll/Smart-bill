//
//  PriceComparison .swift
//  Smart bill
//
//  Created by abdulaziz on 07/04/2026.
//

class PriceComparison {
    var product: String
    var store: String
    var price: Double

    init(product: String, store: String, price: Double) {
        self.product = product
        self.store = store
        self.price = price
    }

    func findCheapest(_ items: [PriceComparison]) -> PriceComparison? {
        return items.min { $0.price < $1.price }
    }

    func calculateSavings(maxPrice: Double, minPrice: Double) -> Double {
        return maxPrice - minPrice
    }
}
