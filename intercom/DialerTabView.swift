//
//  DialerTabView.swift
//  intercom
//
//  Created by James Conway on 24/11/2024.
//
import SwiftUI

struct DialerTabView: View {
    
    @State
    var number: String = ""
    
    func call() {
        print("calling \(number)")
    }
    
    var body: some View {
        KeyPadView(number: $number, call: call)
    }
}

#Preview {
    DialerTabView()
}
