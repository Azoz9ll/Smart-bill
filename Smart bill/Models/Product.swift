//
//  Product.swift
//  Smart bill
//
//  Created by abdulaziz on 07/04/2026.
//

class Product: Identifiable {
    var id: Int
    var name: String
    var price: Double
    var barcode: String?

    init(id: Int, name: String, price: Double, barcode: String? = nil) {
        self.id = id
        self.name = name
        self.price = price
        self.barcode = barcode
    }
}
