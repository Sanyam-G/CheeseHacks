import Foundation
import MultipeerConnectivity
import CoreLocation
import Combine
import UIKit

/// Core mesh networking manager using MultipeerConnectivity
class MeshManager: NSObject, ObservableObject {
    // Service type must be 1-15 chars, lowercase letters, numbers, hyphens
    private let serviceType = "safemesh"

    private var peerID: MCPeerID?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    // Published properties for UI
    @Published var messages: [MeshMessage] = []
    @Published var sosAlerts: [SOSAlert] = []
    @Published var connectedPeers: [MCPeerID] = []
    @Published var peerLocations: [String: PeerInfo] = [:]
    @Published var relayedCount: Int = 0
    @Published var isRunning: Bool = false

    // Deduplication cache - critical for mesh to work
    private var seenMessageIDs: Set<UUID> = []
    private var seenMessageTimestamps: [UUID: Date] = [:]
    private let seenIDsLock = NSLock()
    private static let maxSeenIDs = 500

    // Reconnection tracking
    private var disconnectedPeers: [String: Date] = [:] // displayName -> disconnect time
    private var reconnectTimer: Timer?
    private var refreshTimer: Timer?

    // Device info — displayName includes random suffix for uniqueness,
    // but we show the clean device name in the UI
    var deviceName: String {
        UIDevice.current.name
    }

    var deviceID: String {
        peerID?.displayName ?? UUID().uuidString
    }

    override init() {
        super.init()
        setupMesh()
    }

    private static let peerIDKey = "safemesh_peerID"

    /// Load or create a persistent MCPeerID. MPC caches peer identity at the OS level,
    /// so creating a new MCPeerID each launch causes "Not in connected state" failures.
    /// The peer ID must be archived and reused across launches.
    private static func loadOrCreatePeerID() -> MCPeerID {
        // Try to load a previously archived peer ID
        if let data = UserDefaults.standard.data(forKey: peerIDKey),
           let peerID = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: data) {
            print("📱 Loaded persisted peer ID: \(peerID.displayName)")
            return peerID
        }

        // First launch — create a new one with a unique suffix
        let baseName = UIDevice.current.name
        let suffix = String(UUID().uuidString.prefix(4))
        let peerID = MCPeerID(displayName: "\(baseName)-\(suffix)")

        // Persist it for future launches
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: peerID, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: peerIDKey)
            print("📱 Created and persisted new peer ID: \(peerID.displayName)")
        }

        return peerID
    }

    private func setupMesh() {
        let id = Self.loadOrCreatePeerID()
        peerID = id

        // Create session
        let s = MCSession(peer: id, securityIdentity: nil, encryptionPreference: .none)
        s.delegate = self
        session = s

        // Create advertiser - makes this device discoverable
        let a = MCNearbyServiceAdvertiser(peer: id, discoveryInfo: nil, serviceType: serviceType)
        a.delegate = self
        advertiser = a

        // Create browser - discovers other devices
        let b = MCNearbyServiceBrowser(peer: id, serviceType: serviceType)
        b.delegate = self
        browser = b
    }

    /// Start advertising and browsing for peers
    func start() {
        advertiser?.startAdvertisingPeer()
        browser?.startBrowsingForPeers()
        isRunning = true
        startTimers()
        print("🟢 Mesh started - advertising and browsing")
    }

    /// Stop the mesh
    func stop() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        disconnectedPeers.removeAll()
        isRunning = false
        print("🔴 Mesh stopped")
    }

    /// Tear down and recreate the MPC session + advertiser + browser to recover from stale state
    private func resetMeshSession() {
        guard let id = peerID else { return }
        print("♻️ Resetting mesh session")

        // Stop current components
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()

        // Recreate session (reuse same peerID so others recognize us)
        let s = MCSession(peer: id, securityIdentity: nil, encryptionPreference: .none)
        s.delegate = self
        session = s

        // Recreate advertiser & browser
        let a = MCNearbyServiceAdvertiser(peer: id, discoveryInfo: nil, serviceType: serviceType)
        a.delegate = self
        advertiser = a

        let b = MCNearbyServiceBrowser(peer: id, serviceType: serviceType)
        b.delegate = self
        browser = b

        // Restart
        a.startAdvertisingPeer()
        b.startBrowsingForPeers()

        connectedPeers = []

        print("♻️ Mesh session reset complete")
    }

    /// Periodically refresh advertising/browsing and attempt reconnection
    private func startTimers() {
        // Refresh advertiser+browser every 30s to prevent stale discovery
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, self.isRunning else { return }
            print("🔄 Refreshing discovery...")
            self.browser?.stopBrowsingForPeers()
            self.advertiser?.stopAdvertisingPeer()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard self.isRunning else { return }
                self.advertiser?.startAdvertisingPeer()
                self.browser?.startBrowsingForPeers()
            }
        }

        // Full session reset if no peers and previously had disconnections
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self, self.isRunning else { return }

            let connectedCount = self.session?.connectedPeers.count ?? 0
            let hasRecentDisconnects = !self.disconnectedPeers.isEmpty

            if connectedCount == 0 && hasRecentDisconnects {
                print("⚠️ No peers connected but had recent disconnections — resetting session")
                self.resetMeshSession()
                self.disconnectedPeers.removeAll()
            }
        }
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
        guard let currentSession = session else { return }
        let peers = currentSession.connectedPeers
        guard !peers.isEmpty else { return }

        guard let data = try? JSONEncoder().encode(packet) else { return }

        // Send to each peer individually, wrapped in ObjC exception catcher.
        // MCSession.send() can throw NSInternalInconsistencyException (ObjC)
        // which bypasses Swift do/catch and kills the app.
        for peer in peers {
            guard currentSession.connectedPeers.contains(peer) else { continue }
            var error: NSError?
            let success = ObjCExceptionCatcher.tryBlock({
                do {
                    try currentSession.send(data, toPeers: [peer], with: .reliable)
                } catch {
                    // Swift-level error — peer disconnected between check and send
                    print("❌ Send to \(peer.displayName) failed: \(error)")
                }
            }, error: &error)
            if !success {
                print("❌ ObjC exception sending to \(peer.displayName): \(error?.localizedDescription ?? "unknown")")
            }
        }
    }

    private func markSeen(_ id: UUID) {
        seenIDsLock.lock()
        seenMessageIDs.insert(id)
        seenMessageTimestamps[id] = Date()
        // Prune if over limit — drop oldest entries
        if seenMessageIDs.count > Self.maxSeenIDs {
            let sorted = seenMessageTimestamps.sorted { $0.value < $1.value }
            let toDrop = sorted.prefix(seenMessageIDs.count - Self.maxSeenIDs)
            for (key, _) in toDrop {
                seenMessageIDs.remove(key)
                seenMessageTimestamps.removeValue(forKey: key)
            }
        }
        seenIDsLock.unlock()
    }

    private func hasSeen(_ id: UUID) -> Bool {
        seenIDsLock.lock()
        let seen = seenMessageIDs.contains(id)
        seenIDsLock.unlock()
        return seen
    }

    /// Handle received packet - relay if needed. Must be called on main thread.
    private func handlePacket(_ packet: MeshPacket, from peerName: String) {
        if hasSeen(packet.id) {
            return
        }
        markSeen(packet.id)

        switch packet {
        case .message(var message):
            message.hopPath.append(deviceName)
            message.ttl -= 1
            messages.append(message)

            if message.ttl > 0 {
                broadcast(.message(message))
                relayedCount += 1
                print("🔀 Relayed message, TTL: \(message.ttl), Path: \(message.hopPath.joined(separator: " → "))")
            }

        case .sos(var alert):
            alert.hopPath.append(deviceName)
            alert.ttl -= 1
            sosAlerts.append(alert)

            if alert.ttl > 0 {
                broadcast(.sos(alert))
                relayedCount += 1
                print("🆘🔀 Relayed SOS, TTL: \(alert.ttl)")
            }

        case .ping(let info):
            peerLocations[info.peerID] = info
        }
    }
}

// MARK: - MCSessionDelegate
extension MeshManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        // MPC callbacks come on background threads — route everything to main
        // to avoid data races on disconnectedPeers, isRunning, browser, etc.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Ignore callbacks from a stale session after resetMeshSession()
            guard session === self.session else { return }
            self.connectedPeers = session.connectedPeers

            switch state {
            case .connected:
                print("✅ Connected to: \(peerID.displayName)")
                self.disconnectedPeers.removeValue(forKey: peerID.displayName)

            case .connecting:
                print("🔄 Connecting to: \(peerID.displayName)")

            case .notConnected:
                print("❌ Disconnected from: \(peerID.displayName)")
                self.disconnectedPeers[peerID.displayName] = Date()

                if self.isRunning {
                    print("🔄 Restarting browser to find \(peerID.displayName) again...")
                    self.browser?.stopBrowsingForPeers()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        guard let self, self.isRunning else { return }
                        self.browser?.startBrowsingForPeers()
                    }
                }

            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Decode on background thread (cheap), then handle on main
        do {
            let packet = try JSONDecoder().decode(MeshPacket.self, from: data)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // Ignore data from a stale session (checked on main to avoid data race)
                guard session === self.session else { return }
                self.handlePacket(packet, from: peerID.displayName)
            }
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
        DispatchQueue.main.async { [weak self] in
            guard let self, let currentSession = self.session else {
                invitationHandler(false, nil)
                return
            }
            // Ignore invitations from a stale advertiser
            guard advertiser === self.advertiser else {
                invitationHandler(false, nil)
                return
            }
            print("📨 Received invitation from: \(peerID.displayName) - auto-accepting")
            invitationHandler(true, currentSession)
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("❌ Failed to start advertising: \(error)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MeshManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let currentSession = self.session, let myPeerID = self.peerID else { return }

            // Don't invite peers we're already connected to
            if currentSession.connectedPeers.contains(where: { $0.displayName == peerID.displayName }) {
                print("🔍 Found peer: \(peerID.displayName) - already connected, skipping")
                return
            }

            // Prevent dual-invitation race: only the peer with the lexicographically
            // "larger" name sends the invite. The other side waits for an invitation.
            guard myPeerID.displayName > peerID.displayName else {
                print("🔍 Found peer: \(peerID.displayName) - waiting for their invite (they have priority)")
                return
            }

            print("🔍 Found peer: \(peerID.displayName) - inviting")
            var error: NSError?
            let success = ObjCExceptionCatcher.tryBlock({
                browser.invitePeer(peerID, to: currentSession, withContext: nil, timeout: 15)
            }, error: &error)
            if !success {
                print("❌ ObjC exception inviting \(peerID.displayName): \(error?.localizedDescription ?? "unknown")")
            }
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("👋 Lost peer: \(peerID.displayName)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("❌ Failed to start browsing: \(error)")
    }
}
