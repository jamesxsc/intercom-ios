//
//  Auth.swift
//  intercom
//
//  Created by James Conway on 29/11/2024.
//

import Security
import SwiftUI

class Auth: ObservableObject {
    
    // TODO: implement refresh and expiry
    
    struct Credentials: Codable {
        var accessToken: String?
    }
    
    static let shared: Auth = Auth()
    @Published var isAuthenticated: Bool = false

    private init() {
        isAuthenticated = getCredentials().accessToken != nil
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
        
        var components = URLComponents(string: "https://intercom.xsc.co.uk/auth/login?")!
        components.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password)
        ]
        guard let url = components.url else {
            NSLog("Invalid URL")
            DispatchQueue.main.async {
                completionHandler(false)
            }
            return
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        
        let dataTask = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if error != nil {
                NSLog("Error fetching data")
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
            
            // TODO: consider JSON bodies instead
            let credentials = Credentials(accessToken: String(data: data, encoding: .utf8))
            
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
            decoder.dataDecodingStrategy = .base64
            let result = try decoder.decode(Credentials.self, from: item as! Data)
            
            NSLog(String(describing: result))
            
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
                kSecValueData as String: try JSONEncoder().encode(credentials).base64EncodedData()
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
                kSecValueData as String: try JSONEncoder().encode(credentials).base64EncodedData(),
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
            ]
            
            let status = SecItemAdd(query as CFDictionary, nil)
                        
            let success = status == errSecSuccess
            isAuthenticated = success
            return status == errSecSuccess
        } catch {
            return false
        }
    }
    
    // MARK: Phone Client Endpoints
    // TODO: nevermind needs loading state
    func getPhoneClientAccessToken() {
        
    }
    
}
