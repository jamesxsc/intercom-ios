//
//  User.swift
//  intercom
//
//  Created by James Conway on 02/12/2024.
//

// See UserDetailDto.java
struct UserDetailDto: Codable {
    let email: String
    var phoneNumbers: [PhoneNumber]
}

struct PhoneNumber: Codable, Identifiable {
    let number: String
    let sid: String
    
    var id: String {
        number
    }
}
