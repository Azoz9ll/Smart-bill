//
//  User.swift
//  Smart Bill
//
//  Purpose:
//  نموذج بيانات المستخدم الأساسي.
//
//  Responsibilities:
//  - حمل معرف المستخدم واسمه وموقعه
//  - فصل البيانات عن واجهات تسجيل الدخول
//

//
//  User.swift
//  Smart bill
//
//  Created by abdulaziz on 07/04/2026.
//

/// نموذج بيانات المستخدم الأساسي.
class User {
    var userID: Int
    var name: String
    var location: String

    init(userID: Int, name: String, location: String) {
        self.userID = userID
        self.name = name
        self.location = location
    }
}
