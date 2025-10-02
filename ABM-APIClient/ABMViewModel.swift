//
//  ABMViewModel.swift
//  ABM-APIClient
//
//  © Created by Somesh Pathak on 23/06/2025.
//

import Foundation
import SwiftUI

@MainActor
class ABMViewModel: ObservableObject {
    @Published var devices: [OrgDevice] = []
    @Published var mdmServers: [MDMServer] = []
    @Published var activityStatus: ActivityStatusResponse?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var lastActivityId: String?
    
    // Credentials
    @Published var clientId = ""
    @Published var keyId = ""
    @Published var privateKey = ""
    @Published var environment: AppleAPIEnvironment = .business {
        didSet {
            apiService = APIService(environment: environment)
        }
    }
    
    internal var apiService: APIService
    internal var clientAssertion: String?
    
    init() {
        self.apiService = APIService(environment: .business)
    }
    
    // Generate JWT
    func generateJWT() {
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        
        Task {
            do {
                let credentials = APICredentials(
                    clientId: clientId,
                    keyId: keyId,
                    privateKey: privateKey
                )
                
                clientAssertion = try JWTGenerator.createClientAssertion(credentials: credentials)
                statusMessage = "JWT generated successfully"
                saveCredentials()
            } catch {
                errorMessage = "JWT Error: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
    
    // Fetch devices
    func fetchDevices() {
        print("Running fetchDevices() in ABMViewModel")
        guard let assertion = clientAssertion else {
            errorMessage = "Generate JWT first"
            return
        }
//        DEBUG
//        print("Assertion is: \(assertion)")
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        Task {
            do {
                let token = try await apiService.getAccessToken(
                    clientAssertion: assertion,
                    clientId: clientId
                )
                let fetchedDevices = try await apiService.fetchDevices(accessToken: token)
                devices = fetchedDevices
                statusMessage = "Fetched \(devices.count) devices"
                if devices.isEmpty {
                    // Print and show raw response for debugging
                    print("No devices returned from API. Check device assignment and permissions.")
                    errorMessage = "No devices returned. Please check device assignment, permissions, and API response."
                }
            } catch {
                errorMessage = "API Error: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
    
    // Save credentials to UserDefaults
    private func saveCredentials() {
        UserDefaults.standard.set(clientId, forKey: "clientId")
        UserDefaults.standard.set(keyId, forKey: "keyId")
    }
    
    // Load saved credentials
    func loadCredentials() {
        clientId = UserDefaults.standard.string(forKey: "clientId") ?? ""
        keyId = UserDefaults.standard.string(forKey: "keyId") ?? ""
    }
    
    var currentBaseURL: String {
        apiService.baseURL
    }
    
    var connectButtonLabel: String {
        environment == .business ? "Connect to ABM" : "Connect to ASM"
    }
}
