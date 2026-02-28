import Foundation
import CoreLocation

/// Represents a message in the mesh network
struct MeshMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let senderID: String
    let senderName: String
    let content: String
    let timestamp: Date
    var ttl: Int // Time-to-live, decrements each hop
    var hopPath: [String] // Track the relay path for visualization

    static let defaultTTL = 5

    init(senderID: String, senderName: String, content: String, ttl: Int = defaultTTL) {
        self.id = UUID()
        self.senderID = senderID
        self.senderName = senderName
        self.content = content
        self.timestamp = Date()
        self.ttl = ttl
        self.hopPath = [senderName]
    }

    static func == (lhs: MeshMessage, rhs: MeshMessage) -> Bool {
        lhs.id == rhs.id
    }
}

/// SOS Emergency Alert
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

    static let sosTTL = 10 // Higher TTL for SOS messages

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(senderID: String, senderName: String, coordinate: CLLocationCoordinate2D, emergencyType: EmergencyType, medicalInfo: String? = nil) {
        self.id = UUID()
        self.senderID = senderID
        self.senderName = senderName
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.emergencyType = emergencyType
        self.medicalInfo = medicalInfo
        self.timestamp = Date()
        self.ttl = Self.sosTTL
        self.hopPath = [senderName]
    }

    static func == (lhs: SOSAlert, rhs: SOSAlert) -> Bool {
        lhs.id == rhs.id
    }
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

/// Wrapper for network packets
enum MeshPacket: Codable {
    case message(MeshMessage)
    case sos(SOSAlert)
    case ping(PeerInfo)

    var id: UUID {
        switch self {
        case .message(let msg): return msg.id
        case .sos(let alert): return alert.id
        case .ping(let info): return info.id
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
