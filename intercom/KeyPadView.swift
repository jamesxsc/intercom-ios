//
//  KeyPadView.swift
//  intercom
//
//  Created by James Conway on 24/11/2024.
//

import SwiftUI

let keys = [
    Key(1, "1", " "),
    Key(2, "2", "ABC"),
    Key(3, "3", "DEF"),
    Key(4, "4", "GHI"),
    Key(5, "5", "JKL"),
    Key(6, "6", "MNO"),
    Key(7, "7", "PQRS"),
    Key(8, "8", "TUV"),
    Key(9, "9", "WXYZ"),
    Key(10, "*", " "),
    Key(0, "0", "+"),
    Key(11, "#", " ")
]

struct KeyPadView: View {
    
    @StateObject var auth: Auth = Auth.shared

    @Binding
    var number: String
    
    @Binding
    var identity: String
    
    var call: () -> Void
    
    @State var isInLongPress: [Bool] = Array(repeating: false, count: keys.count)
    
    var body: some View {
        VStack() {
            Picker(selection: $identity) {
                if identity == "" {
                   Text("Select Identity").tag("")
                 }
                
                ForEach(auth.user!.phoneNumbers) { number in
                    Text(number.number).tag(number.number)
                }
                
                Text("JC").tag("jc")
            } label: {
                Text("Identity")
            }
            .pickerStyle(.menu)
            Spacer()

            Text(number.isEmpty ? " " : number)
                .font(.largeTitle)
                .fontWeight(.black)
                .padding(.bottom, 30)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(90), spacing: 20), count: 3), spacing: 15) {
                ForEach(keys) { k in
                    Button(action: {
                        if (isInLongPress[k.id]) {
                            isInLongPress[k.id] = false
                        } else {
                            number.append(k.number)
                        }
                    }) {
                        VStack() {
                            Text(k.number)
                                .font(.largeTitle)
                                .fontWeight(.black)
                                .padding(.bottom, -10)
                            Text(k.subtitle)
                                .font(.caption)
                                .fontWeight(.black)
                        }
                        .frame(width:90, height:90)
                    }
                    .foregroundStyle(.white)
                    .background(Color.gray.opacity(0.3))
                    .cornerRadius(.infinity)
                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.5, maximumDistance: 50.0)
                        .onEnded { _ in
                            // Prevent executing other handler as well
                            isInLongPress[k.id] = true
                            
                            if k.id == 0 && number.isEmpty { // Only allow placing a + at the start
                                number.append("+")
                            }
                    })
                }
                
                
                Spacer()
                
                Button(action: {call()}) {
                    Image(systemName: "phone.arrow.up.right.fill")
                        .font(.largeTitle)
                        .frame(width:90, height:90)
                }
                .foregroundStyle(.white)
                .background(Color.green)
                .cornerRadius(.infinity)
                
                
                if (!number.isEmpty) {
                    Button(action: {number.removeLast()}) {
                        Image(systemName: "delete.left.fill")
                            .font(.largeTitle)
                    }
                    .foregroundStyle(Color.gray.opacity(0.3))
                }
            }
        }
        .padding(.bottom, 30)
    }
}

#Preview {
    KeyPadView(number: .constant("+44 1234567890"), identity: .constant("+44 1234567890"), call: { })
}
