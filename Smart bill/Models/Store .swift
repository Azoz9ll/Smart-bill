//
//  Store .swift
//  Smart Bill
//
//  Purpose:
//  نموذج بيانات المتجر الأساسي.
//
//  Responsibilities:
//  - حمل معرف المتجر واسمه وموقعه
//  - تمثيل البيانات دون الاتصال بالخادم
//

//
//  Store .swift
//  Smart bill
//
//  Created by abdulaziz on 07/04/2026.
//

/// نموذج بيانات المتجر الأساسي.
class Store {
    var storeID: Int
    var name: String
    var location: String

    init(storeID: Int, name: String, location: String) {
        self.storeID = storeID
        self.name = name
        self.location = location
    }
}
