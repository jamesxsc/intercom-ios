//
//  ContentView.swift
//  intercom
//
//  Created by James Conway on 23/11/2024.
//

import SwiftUI


struct ContentView: View {
    
    @StateObject var auth: Auth = .shared
    
    var body: some View {
        ZStack {
            if !auth.isAuthenticated {
                LoginView()
            } else {
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
    }
}

#Preview {
    ContentView()
}
