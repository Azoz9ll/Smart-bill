//
//  Invoice.swift
//  Smart Bill
//
//  Purpose:
//  نموذج مبسط للفاتورة يربط التاريخ بقائمة منتجات.
//
//  Responsibilities:
//  - حفظ معرف الفاتورة وتاريخها
//  - تجميع عناصر Product دون تنفيذ طلبات شبكة
//

import Foundation
//
//  Invoice.swift
//  Smart bill
//
//  Created by abdulaziz on 07/04/2026.
//

/// نموذج مبسط للفاتورة يربط التاريخ بقائمة منتجات.
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

