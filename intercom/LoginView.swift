//
//  LoginView.swift
//  intercom
//
//  Created by James Conway on 29/11/2024.
//

import SwiftUI

struct LoginView: View {
    
    // TODO: consider migrating to environment object
    @StateObject var auth: Auth = Auth.shared
    
    @State var username: String = ""
    @State var password: String = ""
    @State var error: Bool = false
    
    func login() {
        error = false
        // TODO: need a loading state, ideally do with loading from auth, and disable button at least
        auth.login(username: username, password: password) { result in
            error = !result
        }
    }
    
    var body: some View {
        // TODO: constraint warnings on input: may be an us error may be a system error
        Form {
            Text("Login to Intercom")
                .font(.largeTitle)
            TextField("Username", text: $username)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
            Button(action: login) {
                Text("Login")
            }
            
            if error {
                Text("Login failed")
                    .foregroundStyle(.red)
            }
            
        }
        .padding()
    }
    
}

#Preview {
    LoginView()
}
