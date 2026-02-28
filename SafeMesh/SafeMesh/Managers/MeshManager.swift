import Foundation
import MultipeerConnectivity
import CoreLocation
import Combine
import UIKit

/// Core mesh networking manager using MultipeerConnectivity
class MeshManager: NSObject, ObservableObject {
    // Service type must be 1-15 chars, lowercase letters, numbers, hyphens
    private let serviceType = "safemesh"

    private var peerID: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    // Published properties for UI
    @Published var messages: [MeshMessage] = []
    @Published var sosAlerts: [SOSAlert] = []
    @Published var connectedPeers: [MCPeerID] = []
    @Published var peerLocations: [String: PeerInfo] = [:]
    @Published var relayedCount: Int = 0
    @Published var isRunning: Bool = false

    // Deduplication cache - critical for mesh to work
    private var seenMessageIDs: Set<UUID> = []
    private let seenIDsLock = NSLock()

    // Device info
    var deviceName: String {
        peerID?.displayName ?? UIDevice.current.name
    }

    var deviceID: String {
        peerID?.displayName ?? UUID().uuidString
    }

    override init() {
        super.init()
        setupMesh()
    }

    private func setupMesh() {
        // Create peer ID with device name
        peerID = MCPeerID(displayName: UIDevice.current.name)

        // Create session
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self

        // Create advertiser - makes this device discoverable
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self

        // Create browser - discovers other devices
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser.delegate = self
    }

    /// Start advertising and browsing for peers
    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        isRunning = true
        print("🟢 Mesh started - advertising and browsing")
    }

    /// Stop the mesh
    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        isRunning = false
        print("🔴 Mesh stopped")
    }

    // MARK: - Sending Messages

    /// Send a text message to the mesh
    func sendMessage(_ content: String) {
        let message = MeshMessage(
            senderID: deviceID,
            senderName: deviceName,
            content: content
        )

        // Add to our own messages
        DispatchQueue.main.async {
            self.messages.append(message)
        }

        // Mark as seen so we don't process our own message
        markSeen(message.id)

        // Broadcast to all peers
        broadcast(.message(message))
    }

    /// Send an SOS alert
    func sendSOS(coordinate: CLLocationCoordinate2D, type: EmergencyType, medicalInfo: String? = nil) {
        let alert = SOSAlert(
            senderID: deviceID,
            senderName: deviceName,
            coordinate: coordinate,
            emergencyType: type,
            medicalInfo: medicalInfo
        )

        // Add to our own alerts
        DispatchQueue.main.async {
            self.sosAlerts.append(alert)
        }

        // Mark as seen
        markSeen(alert.id)

        // Broadcast with priority
        broadcast(.sos(alert))

        print("🆘 SOS SENT: \(type.rawValue) at \(coordinate.latitude), \(coordinate.longitude)")
    }

    /// Broadcast peer location info
    func broadcastLocation(_ coordinate: CLLocationCoordinate2D) {
        let info = PeerInfo(
            id: UUID(),
            peerID: deviceID,
            displayName: deviceName,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timestamp: Date()
        )
        broadcast(.ping(info))
    }

    // MARK: - Private Methods

    private func broadcast(_ packet: MeshPacket) {
        guard !session.connectedPeers.isEmpty else {
            print("⚠️ No connected peers to broadcast to")
            return
        }

        do {
            let data = try JSONEncoder().encode(packet)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            print("📤 Broadcast to \(session.connectedPeers.count) peers")
        } catch {
            print("❌ Broadcast failed: \(error)")
        }
    }

    private func markSeen(_ id: UUID) {
        seenIDsLock.lock()
        seenMessageIDs.insert(id)
        seenIDsLock.unlock()
    }

    private func hasSeen(_ id: UUID) -> Bool {
        seenIDsLock.lock()
        let seen = seenMessageIDs.contains(id)
        seenIDsLock.unlock()
        return seen
    }

    /// Handle received packet - relay if needed
    private func handlePacket(_ packet: MeshPacket, from peerName: String) {
        // Check deduplication
        if hasSeen(packet.id) {
            print("🔄 Skipping duplicate packet: \(packet.id)")
            return
        }

        markSeen(packet.id)

        switch packet {
        case .message(var message):
            // Add this hop to the path
            message.hopPath.append(deviceName)

            // Decrement TTL
            message.ttl -= 1

            DispatchQueue.main.async {
                self.messages.append(message)
            }

            // Relay if TTL > 0
            if message.ttl > 0 {
                broadcast(.message(message))
                DispatchQueue.main.async {
                    self.relayedCount += 1
                }
                print("🔀 Relayed message, TTL: \(message.ttl), Path: \(message.hopPath.joined(separator: " → "))")
            }

        case .sos(var alert):
            // Add this hop to the path
            alert.hopPath.append(deviceName)

            // Decrement TTL
            alert.ttl -= 1

            DispatchQueue.main.async {
                self.sosAlerts.append(alert)
            }

            // Always relay SOS with remaining TTL
            if alert.ttl > 0 {
                broadcast(.sos(alert))
                DispatchQueue.main.async {
                    self.relayedCount += 1
                }
                print("🆘🔀 Relayed SOS, TTL: \(alert.ttl)")
            }

        case .ping(let info):
            DispatchQueue.main.async {
                self.peerLocations[info.peerID] = info
            }
        }
    }
}

// MARK: - MCSessionDelegate
extension MeshManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
        }

        switch state {
        case .connected:
            print("✅ Connected to: \(peerID.displayName)")
        case .connecting:
            print("🔄 Connecting to: \(peerID.displayName)")
        case .notConnected:
            print("❌ Disconnected from: \(peerID.displayName)")
        @unknown default:
            break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            let packet = try JSONDecoder().decode(MeshPacket.self, from: data)
            handlePacket(packet, from: peerID.displayName)
        } catch {
            print("❌ Failed to decode packet: \(error)")
        }
    }

    // Required delegate methods (unused)
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MeshManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept all invitations - this is a mesh, everyone connects
        print("📨 Received invitation from: \(peerID.displayName) - auto-accepting")
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("❌ Failed to start advertising: \(error)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MeshManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        print("🔍 Found peer: \(peerID.displayName) - inviting")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("👋 Lost peer: \(peerID.displayName)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("❌ Failed to start browsing: \(error)")
    }
}
