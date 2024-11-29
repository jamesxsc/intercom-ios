//
//  Key.swift
//  intercom
//
//  Created by James Conway on 29/11/2024.
//

struct Key : Identifiable {
    var id: Int
    
    var number: String
    var subtitle: String
    
    init(_ id: Int,_ number: String, _ subtitle: String) {
        self.id = id
        self.number = number
        self.subtitle = subtitle
    }
}
