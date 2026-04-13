//
//  User.swift
//  Smart bill
//
//  Created by abdulaziz on 07/04/2026.
//

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
