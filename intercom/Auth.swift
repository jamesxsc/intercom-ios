//
//  Auth.swift
//  intercom
//
//  Created by James Conway on 29/11/2024.
//

import Security
import SwiftUI

class Auth: ObservableObject {
    
    // TODO: implement refresh and expiry (ie fetch a new one or failing that log out and clear state)
    
    struct Credentials: Codable {
        var accessToken: String?
    }
    
    static let shared: Auth = Auth()
    // TODO: move to exposing a isloaded variable at least alongside this
    @Published var isAuthenticated: Bool = false
    @Published var user: UserDetailDto?
    @Published var loading: Bool = true

    private init() {
        isAuthenticated = getCredentials().accessToken != nil
        if (isAuthenticated) {
            fetchUser()
        }
    }
    
    // MARK: User object fetch
    
    // This function is called 1) when the app opens or if we are not yet logged in, 2) when we log in
    // (always, so it is responsible for fetching an up-to-date user object)
    func fetchUser() {
        let url = URL(string: "https://intercom.xsc.co.uk/user/detail")
        
        guard let url else {
            NSLog("Error: invalid URL") // TODO: consider a published error var to tell the user (we might not recover from something like this)
            return
        }
        
        guard let accessToken = getCredentials().accessToken else {
            NSLog("Error: unexpected call to fetchUser with no access token")
            return
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if let error {
                NSLog("Error: \(error)")
                return
            }
            
            if let repsonse = response as? HTTPURLResponse, repsonse.statusCode != 200 {
                NSLog("Error: \(repsonse.statusCode)")
                return
            }
            
            guard let data else {
                NSLog("Error: no data")
                return
            }
            
            let user = try? JSONDecoder().decode(UserDetailDto.self, from: data)
            
            guard let user else {
                NSLog("Failed to decode user object from API")
                return
            }
            
            DispatchQueue.main.async {
                self.user = user
                self.loading = false
                NSLog("\(self.user!)")
            }
        }
        task.resume()
    }
    
    // MARK: JWT Authentication
    
    func logout() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "intercom",
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // TODO: this is pretty ugly, let's tidy it up a bit
    func login(username: String, password: String, completionHandler: @escaping (Bool) -> Void) {
        let url = URL(string: "https://intercom.xsc.co.uk/auth/login")
        
        guard let url = url else {
            NSLog("Invalid URL")
            DispatchQueue.main.async {
                completionHandler(false)
            }
            return
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let creds = try? JSONEncoder().encode(["username": username, "password": password])

        guard let creds = creds else {
            NSLog("Failed to encode credentials as JSON body")
            DispatchQueue.main.async {
                completionHandler(false)
            }
            return
        }
        
        urlRequest.httpBody = creds
        
        let dataTask = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if error != nil {
                NSLog("Error fetching data")
                DispatchQueue.main.async {
                    completionHandler(false)
                }
                return
            }
            
            // Currently there is a singular failure state
            // If we wish to distinguish a network or server error from invalid credentials
            // it is possible to filter by response code 403 (FORBIDDEN)
            if let repsonse = response as? HTTPURLResponse, repsonse.statusCode != 200 {
                NSLog("Invalid status code: \(repsonse.statusCode)")
                DispatchQueue.main.async {
                    completionHandler(false)
                }
                return
            }
            
            guard let data else {
                NSLog("No data returned")
                DispatchQueue.main.async {
                    completionHandler(false)
                }
                return
            }
            
            let returned = try? JSONDecoder().decode(JWTTokenDto.self, from: data)
            
            guard let accessToken = returned?.accessToken else {
                    NSLog("Failed to decode JWT access token")
                    DispatchQueue.main.async {
                        completionHandler(false)
                    }
                    return
            }
            
            let credentials = Credentials(accessToken: accessToken)
            
            NSLog("Setting credentials")
            DispatchQueue.main.async {
                completionHandler(self.setCredentials(credentials))
            }
        }
        dataTask.resume()
    }
    
    func getCredentials() -> Credentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "intercom",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess else {
            NSLog("Could not retrieve credentials")
            return Credentials()
        }
        
        do {
            let decoder = JSONDecoder()
            let result = try decoder.decode(Credentials.self, from: item as! Data)
                                    
            return result
        } catch {
            NSLog("Could not decode credentials")
            return Credentials()
        }
        
    }

    func setCredentials(_ credentials: Credentials) -> Bool {
        do {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: "intercom",
            ]
            
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: try JSONEncoder().encode(credentials)
            ]
            
            let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
            
            guard status == errSecSuccess else {
                if status == errSecItemNotFound {
                    return setFirstCredentials(credentials)
                } else {
                    return false
                }
            }
            
            isAuthenticated = true
            fetchUser()
            return true
        } catch {
            return false
        }
    }
    
    fileprivate func setFirstCredentials(_ credentials: Credentials) -> Bool {
        do {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: "intercom",
                kSecValueData as String: try JSONEncoder().encode(credentials),
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
            ]
            
            let status = SecItemAdd(query as CFDictionary, nil)
                        
            let success = status == errSecSuccess
            if success {
                isAuthenticated = true
                fetchUser()
            }
            return status == errSecSuccess
        } catch {
            return false
        }
    }
    
    // MARK: Phone Client Endpoints
    func getPhoneClientAccessToken(_ identity: String, _ handler: @escaping (String?) -> Void) {
        guard let accessToken = getCredentials().accessToken else {
            NSLog("API method called without authentication")
            DispatchQueue.main.async {
                handler(nil)
            }
            return
        }
        
        var components = URLComponents(string: "https://intercom.xsc.co.uk/client/accessToken?")!
        components.queryItems = [
            URLQueryItem(name: "identity", value: identity),
        ]
        guard let url = components.url else {
            NSLog("Invalid URL")
            DispatchQueue.main.async {
                handler(nil)
            }
            return
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let dataTask = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if error != nil {
                NSLog("Error fetching data")
                DispatchQueue.main.async {
                    handler(nil)
                }
                return
            }
            
            if let repsonse = response as? HTTPURLResponse, repsonse.statusCode != 200 {
                NSLog("Invalid status code: \(repsonse.statusCode)")
                DispatchQueue.main.async {
                    handler(nil)
                }
                return
            }
            
            guard let data else {
                NSLog("No data returned")
                DispatchQueue.main.async {
                    handler(nil)
                }
                return
            }
            
            let dto = try? JSONDecoder().decode(PhoneClientAccessTokenDto.self, from: data)
            
            guard let token = dto?.phoneClientAccessToken else {
                    NSLog("Error decoding JSON")
                    DispatchQueue.main.async {
                        handler(nil)
                    }
                    return
            }
            
            DispatchQueue.main.async {
                handler(token)
            }
        }
        dataTask.resume()
    }
    
}
