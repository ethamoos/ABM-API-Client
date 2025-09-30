//
//  ABMViewModel+Extensions.swift
//  ABM-APIClient
//
//  © Created by Somesh Pathak on 23/06/2025.
//

import Foundation

extension ABMViewModel {
    // Fetch MDM servers
    func fetchMDMServers() {
        print("Running fetchMDMServers extension")
        guard let assertion = clientAssertion else {
            errorMessage = "Generate JWT first"
            return
        }
        
        isLoading = true
        Task {
            do {
                let token = try await apiService.getAccessToken(
                    clientAssertion: assertion,
                    clientId: clientId
                )
                mdmServers = try await apiService.fetchMDMServers(accessToken: token)
                statusMessage = "Fetched \(mdmServers.count) MDM servers"
            } catch {
                // Enhanced error handling for debugging
                print("fetchMDMServers error: \(error)")
                if let urlError = error as? URLError {
                    errorMessage = "Network error: \(urlError.localizedDescription)"
                } else if let decodingError = error as? DecodingError {
                    errorMessage = "Decoding error: \(decodingError.localizedDescription)"
                } else if let nsError = error as? NSError {
                    // Try to extract status code and response from NSError
                    let statusCode = nsError.code
                    let response = nsError.userInfo[NSLocalizedDescriptionKey] as? String ?? "No response body"
                    errorMessage = "API error (status \(statusCode)): \(response)"
                } else {
                    errorMessage = "Error: \(error.localizedDescription)"
                }
            }
            isLoading = false
        }
    }
    
    // Get device assigned server
    func getDeviceAssignedServer(deviceId: String) async {
        guard let assertion = clientAssertion else { return }
        
        do {
            let token = try await apiService.getAccessToken(
                clientAssertion: assertion,
                clientId: clientId
            )
            
            statusMessage = "Server info fetched"
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
    }
    
    // Get devices for MDM
    func getDevicesForMDM(mdmId: String) async {
        guard let assertion = clientAssertion else { return }
        
        do {
            let token = try await apiService.getAccessToken(
                clientAssertion: assertion,
                clientId: clientId
            )
            let deviceIds = try await apiService.getDevicesForMDM(mdmId: mdmId, accessToken: token)
            statusMessage = "MDM has \(deviceIds.count) devices"
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
    }
    
    // Assign devices
    func assignDevices(deviceIds: [String], mdmId: String?) async {
        guard let assertion = clientAssertion else { return }
        
        do {
            let token = try await apiService.getAccessToken(
                clientAssertion: assertion,
                clientId: clientId
            )
            let activityId = try await apiService.assignDevices(
                deviceIds: deviceIds,
                mdmId: mdmId,
                accessToken: token
            )
            statusMessage = "Activity started: \(activityId)"
            lastActivityId = activityId
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
    }
    
    // Check activity status
    func checkActivityStatus(activityId: String) async {
        guard let assertion = clientAssertion else { return }
        
        do {
            let token = try await apiService.getAccessToken(
                clientAssertion: assertion,
                clientId: clientId
            )
            activityStatus = try await apiService.checkActivityStatus(
                activityId: activityId,
                accessToken: token
            )
            statusMessage = "Status: \(activityStatus?.data.attributes.status ?? "Unknown")"
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
    }
}
