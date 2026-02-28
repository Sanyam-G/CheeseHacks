import Foundation
import CoreLocation

struct MeshMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let senderID: String
    let senderName: String
    let content: String
    let timestamp: Date
    var ttl: Int
    var hopPath: [String]
    static let defaultTTL = 5

    init(senderID: String, senderName: String, content: String, ttl: Int = defaultTTL) {
        self.id = UUID(); self.senderID = senderID; self.senderName = senderName
        self.content = content; self.timestamp = Date(); self.ttl = ttl; self.hopPath = [senderName]
    }
    static func == (lhs: MeshMessage, rhs: MeshMessage) -> Bool { lhs.id == rhs.id }
}

struct SOSAlert: Codable, Identifiable, Equatable {
    let id: UUID
    let senderID: String
    let senderName: String
    let latitude: Double
    let longitude: Double
    let emergencyType: EmergencyType
    let medicalInfo: String?
    let timestamp: Date
    var ttl: Int
    var hopPath: [String]
    static let sosTTL = 10

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    init(senderID: String, senderName: String, coordinate: CLLocationCoordinate2D, emergencyType: EmergencyType, medicalInfo: String? = nil) {
        self.id = UUID(); self.senderID = senderID; self.senderName = senderName
        self.latitude = coordinate.latitude; self.longitude = coordinate.longitude
        self.emergencyType = emergencyType; self.medicalInfo = medicalInfo
        self.timestamp = Date(); self.ttl = Self.sosTTL; self.hopPath = [senderName]
    }
    static func == (lhs: SOSAlert, rhs: SOSAlert) -> Bool { lhs.id == rhs.id }
}

enum EmergencyType: String, Codable, CaseIterable {
    case medical = "Medical"
    case trapped = "Trapped"
    case fire = "Fire"
    case flood = "Flood"
    case other = "Other"

    var icon: String {
        switch self {
        case .medical: return "cross.circle.fill"
        case .trapped: return "figure.wave"
        case .fire: return "flame.fill"
        case .flood: return "water.waves"
        case .other: return "exclamationmark.triangle.fill"
        }
    }
}

// NEW: Resource broadcasts (shelters, water, evacuation routes)
enum ResourceType: String, Codable, CaseIterable {
    case shelter = "Shelter"
    case water = "Water Station"
    case medical = "Medical Aid"
    case evacuation = "Evacuation Route"
    case danger = "Danger Zone"

    var icon: String {
        switch self {
        case .shelter: return "house.fill"
        case .water: return "drop.fill"
        case .medical: return "cross.fill"
        case .evacuation: return "arrow.up.right.circle.fill"
        case .danger: return "exclamationmark.octagon.fill"
        }
    }

    var color: String {
        switch self {
        case .shelter: return "blue"
        case .water: return "cyan"
        case .medical: return "red"
        case .evacuation: return "green"
        case .danger: return "orange"
        }
    }
}

struct ResourceBroadcast: Codable, Identifiable {
    let id: UUID
    let senderID: String
    let senderName: String
    let type: ResourceType
    let title: String
    let description: String
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    var ttl: Int
    var hopPath: [String]
    static let resourceTTL = 8

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    init(senderID: String, senderName: String, type: ResourceType, title: String, description: String, coordinate: CLLocationCoordinate2D) {
        self.id = UUID(); self.senderID = senderID; self.senderName = senderName
        self.type = type; self.title = title; self.description = description
        self.latitude = coordinate.latitude; self.longitude = coordinate.longitude
        self.timestamp = Date(); self.ttl = Self.resourceTTL; self.hopPath = [senderName]
    }
}

// Expanded packet type with new cases
enum MeshPacket: Codable {
    case message(MeshMessage)
    case sos(SOSAlert)
    case ping(PeerInfo)
    case typing(String)        // NEW: sender name
    case ack(UUID)             // NEW: delivery acknowledgement
    case resource(ResourceBroadcast) // NEW: shelter/water/evacuation broadcasts

    var id: UUID {
        switch self {
        case .message(let m): return m.id
        case .sos(let a): return a.id
        case .ping(let p): return p.id
        case .typing: return UUID() // typing is not deduplicated
        case .ack(let id): return id
        case .resource(let r): return r.id
        }
    }
}

struct PeerInfo: Codable, Identifiable {
    let id: UUID
    let peerID: String
    let displayName: String
    let latitude: Double?
    let longitude: Double?
    let timestamp: Date

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
