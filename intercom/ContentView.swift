//
//  ContentView.swift
//  intercom
//
//  Created by James Conway on 23/11/2024.
//

import SwiftUI

struct ContentView: View {
    
    @State
    var number: String = ""
    
    var body: some View {
        TabView() {
            Tab("Dialer", systemImage: "phone.arrow.up.right.fill") {
                TextField("Number:", text: $number)
                    
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
