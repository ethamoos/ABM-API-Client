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
    
    // State for partial fetch retry
    var partialDevices: [OrgDevice] = []
    var partialNextURL: String? = nil
    var canRetryPartialFetch: Bool { partialNextURL != nil && !partialDevices.isEmpty }
    
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
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        partialDevices = []
        partialNextURL = nil
        Task {
            do {
                let token = try await apiService.getAccessToken(
                    clientAssertion: assertion,
                    clientId: clientId
                )
                do {
                    let fetchedDevices = try await apiService.fetchDevices(accessToken: token)
                    devices = fetchedDevices
                    statusMessage = "Fetched \(devices.count) devices"
                    if devices.isEmpty {
                        errorMessage = "No devices returned. Please check device assignment, permissions, and API response."
                    }
                } catch let partialError as PartialFetchError {
                    devices = partialError.partialDevices
                    partialDevices = partialError.partialDevices
                    partialNextURL = partialError.nextURL
                    errorMessage = "Connection lost or error occurred. Displaying \(devices.count) devices fetched before the error. You can retry from the failure point. Error: \(partialError.underlyingError.localizedDescription)"
                } catch {
                    errorMessage = "API Error: \(error.localizedDescription)"
                }
            } catch {
                errorMessage = "API Error: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    // Retry from failure point, deduplicating devices
    func retryFetchDevices() {
        guard let assertion = clientAssertion, let nextURL = partialNextURL else { return }
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        Task {
            do {
                let token = try await apiService.getAccessToken(
                    clientAssertion: assertion,
                    clientId: clientId
                )
                let newDevices = try await apiService.fetchDevices(accessToken: token, resumeURL: nextURL, existingDevices: partialDevices)
                // Deduplicate by device ID
                let deduped = Dictionary(grouping: newDevices, by: { $0.id }).compactMap { $0.value.first }
                devices = deduped
                statusMessage = "Fetched \(devices.count) devices (after retry)"
                partialDevices = []
                partialNextURL = nil
            } catch let partialError as PartialFetchError {
                // Merge and deduplicate again
                let merged = partialError.partialDevices + partialDevices
                let deduped = Dictionary(grouping: merged, by: { $0.id }).compactMap { $0.value.first }
                devices = deduped
                partialDevices = deduped
                partialNextURL = partialError.nextURL
                errorMessage = "Connection lost again. Displaying \(devices.count) devices fetched so far. You can retry again. Error: \(partialError.underlyingError.localizedDescription)"
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
