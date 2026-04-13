import Foundation
//
//  Invoice.swift
//  Smart bill
//
//  Created by abdulaziz on 07/04/2026.
//

class Invoice {
    var invoiceID: Int
    var date: Date
    var products: [Product]

    init(invoiceID: Int, date: Date, products: [Product]) {
        self.invoiceID = invoiceID
        self.date = date
        self.products = products
    }
}
