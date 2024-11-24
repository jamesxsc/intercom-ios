//
//  ContentView.swift
//  intercom
//
//  Created by James Conway on 23/11/2024.
//

import SwiftUI

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


struct ContentView: View {
    
    var body: some View {
        TabView() {
            Tab("Dialer", systemImage: "phone.arrow.up.right.fill") {
                DialerTabView()
            }
            Tab("Contacts", systemImage: "person.crop.circle.fill") {
                
            }
            Tab("Settings", systemImage: "gear") {
                
            }
        }
    }
}

#Preview {
    ContentView()
}
