//
//  APIService.swift
//  ABM-APIClient
//
//  © Created by Somesh Pathak on 23/06/2025.
//


import Foundation

// Error type for partial fetch
struct PartialFetchError: Error {
    let partialDevices: [OrgDevice]
    let underlyingError: Error
}

enum AppleAPIEnvironment: String, CaseIterable, Identifiable {
    case business = "https://api-business.apple.com"
    case school = "https://api-school.apple.com"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .business: return "Business"
        case .school: return "School"
        }
    }
}

class APIService {
    private var accessToken: String?
    private var tokenExpiry: Date?
    let baseURL: String
    let environment: AppleAPIEnvironment
    
    init(environment: AppleAPIEnvironment) {
        self.baseURL = environment.rawValue
        self.environment = environment
    }
    
    // Get access token
    func getAccessToken(clientAssertion: String, clientId: String) async throws -> String {
        // Check if we have valid token
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date() {
            return token
        }
    
        // Create request
        var request = URLRequest(url: URL(string: "https://account.apple.com/auth/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Set scope based on environment
        let scope = environment == .business ? "business.api" : "school.api"
        // Create body
        let bodyParams = [
            "grant_type": "client_credentials",
            "client_id": clientId,
            "client_assertion_type": "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
            "client_assertion": clientAssertion,
            "scope": scope
        ]
        
        let bodyString = bodyParams
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        
        request.httpBody = bodyString.data(using: .utf8)
        
        // Make request
        let (data, _) = try await URLSession.shared.data(for: request)
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        
        // Store token and expiry
        self.accessToken = tokenResponse.accessToken
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        
        return tokenResponse.accessToken
    }
    
    // Check activity status
    func checkActivityStatus(activityId: String, accessToken: String) async throws -> ActivityStatusResponse {
        let url = URL(string: "\(baseURL)/v1/orgDeviceActivities/\(activityId)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(ActivityStatusResponse.self, from: data)
    }
    
    // Fetch devices
    func fetchDevices(accessToken: String, pageDelay: UInt64 = 1_000_000_000, maxRetries: Int = 3) async throws -> [OrgDevice] {
        var allDevices: [OrgDevice] = []
        var nextURL: String? = "\(baseURL)/v1/orgDevices"
        
        while let urlString = nextURL {
            guard let url = URL(string: urlString) else { break }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            var lastError: Error?
            for attempt in 0...maxRetries {
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    if let httpResponse = response as? HTTPURLResponse {
                        print("Status Code: \(httpResponse.statusCode)")
                        if httpResponse.statusCode != 200 {
                            print("Response: \(String(data: data, encoding: .utf8) ?? "No data")")
                            throw NSError(domain: "API", code: httpResponse.statusCode,
                                        userInfo: [NSLocalizedDescriptionKey: "API returned status \(httpResponse.statusCode)"])
                        }
                    }
                    let deviceResponse = try JSONDecoder().decode(DevicesResponse.self, from: data)
                    allDevices.append(contentsOf: deviceResponse.data)
                    if let next = deviceResponse.links?.next, next.hasPrefix("http") {
                        nextURL = next
                    } else if let next = deviceResponse.links?.next {
                        nextURL = "\(baseURL)\(next)"
                    } else {
                        nextURL = nil
                    }
                    break // Success, break retry loop
                } catch {
                    lastError = error
                    if attempt < maxRetries {
                        let backoff = UInt64(pow(2.0, Double(attempt))) * 500_000_000 // 0.5s, 1s, 2s, ...
                        print("fetchDevices: attempt \(attempt+1) failed, retrying in \(Double(backoff)/1_000_000_000)s: \(error.localizedDescription)")
                        try await Task.sleep(nanoseconds: backoff)
                        continue
                    } else {
                        print("fetchDevices: failed after \(maxRetries+1) attempts: \(error.localizedDescription)")
                        // If we have partial data, throw PartialFetchError
                        if !allDevices.isEmpty {
                            throw PartialFetchError(partialDevices: allDevices, underlyingError: error)
                        } else {
                            throw error
                        }
                    }
                }
            }
            // Add delay between paginated requests to avoid server saturation
            if nextURL != nil {
                try await Task.sleep(nanoseconds: pageDelay)
            }
        }
        return allDevices
    }
    
    // Get device by ID
    func getDevice(id: String, accessToken: String) async throws -> OrgDevice {
        let url = URL(string: "\(baseURL)/v1/orgDevices/\(id)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(DeviceDetailResponse.self, from: data)
        return response.data
    }
    
    // Fetch MDM servers
    func fetchMDMServers(accessToken: String) async throws -> [MDMServer] {
        let url = URL(string: "\(baseURL)/v1/mdmServers")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("MDM Status Code: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                print("MDM Response: \(String(data: data, encoding: .utf8) ?? "No data")")
            }
        }
        
        let mdmResponse = try JSONDecoder().decode(MDMServersResponse.self, from: data)
        return mdmResponse.data
    }
    
    // Get devices for MDM server
    func getDevicesForMDM(mdmId: String, accessToken: String) async throws -> [String] {
        let url = URL(string: "\(baseURL)/v1/mdmServers/\(mdmId)/relationships/devices")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(RelationshipResponse.self, from: data)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("Get Devices Status Code: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 {
                print("Get Devices Response: \(String(data: data, encoding: .utf8) ?? "No data")")
            }
        }

        return response.data.map { $0.id }
    }
    
    // Assign/unassign devices
    func assignDevices(deviceIds: [String], mdmId: String?, accessToken: String) async throws -> String {
        let url = URL(string: "\(baseURL)/v1/orgDeviceActivities")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let activity = DeviceActivity(
            data: DeviceActivity.ActivityData(
                type: "orgDeviceActivities",
                attributes: DeviceActivity.ActivityAttributes(
                    activityType: mdmId != nil ? "ASSIGN_DEVICES" : "UNASSIGN_DEVICES"
                ),
                relationships: DeviceActivity.ActivityRelationships(
                    mdmServer: DeviceActivity.MDMServerRelation(
                        data: DeviceActivity.RelationData(
                            type: "mdmServers",
                            id: mdmId ?? ""
                        )
                    ),
                    devices: DeviceActivity.DevicesRelation(
                        data: deviceIds.map {
                            DeviceActivity.RelationData(type: "orgDevices", id: $0)
                        }
                    )
                )
            )
        )
        
        request.httpBody = try JSONEncoder().encode(activity)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("Assign Status: \(httpResponse.statusCode)")
            if httpResponse.statusCode != 200 && httpResponse.statusCode != 201 {
                print("Assign Error: \(String(data: data, encoding: .utf8) ?? "")")
                throw NSError(domain: "API", code: httpResponse.statusCode)
            }
        }
        
        let activityResponse = try JSONDecoder().decode(ActivityStatusResponse.self, from: data)
        return activityResponse.data.id
    }
}


struct DeviceDetailResponse: Codable {
    let data: OrgDevice
}

struct RelationshipResponse: Codable {
    let data: [RelationData]
    
    struct RelationData: Codable {
        let type: String
        let id: String
    }
}
