import Foundation
import MultipeerConnectivity
import CoreLocation
import Combine
import UIKit

/// Core mesh networking manager using MultipeerConnectivity
class MeshManager: NSObject, ObservableObject {
    private let serviceType = "safemesh"

    private var peerID: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    @Published var messages: [MeshMessage] = []
    @Published var sosAlerts: [SOSAlert] = []
    @Published var connectedPeers: [MCPeerID] = []
    @Published var peerLocations: [String: PeerInfo] = [:]
    @Published var relayedCount: Int = 0
    @Published var isRunning: Bool = false
    @Published var deliveredMessageIDs: Set<UUID> = []
    @Published var typingPeers: Set<String> = []
    @Published var resourceBroadcasts: [ResourceBroadcast] = []

    private var seenMessageIDs: Set<UUID> = []
    private let seenIDsLock = NSLock()
    private var reconnectTimer: Timer?
    private var appLifecycleObservers: [NSObjectProtocol] = []

    var deviceName: String { peerID?.displayName ?? UIDevice.current.name }
    var deviceID: String { peerID?.displayName ?? UUID().uuidString }

    override init() {
        super.init()
        setupMesh()
        setupAppLifecycleObservers()
    }

    deinit {
        appLifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        reconnectTimer?.invalidate()
    }

    private func setupMesh() {
        peerID = MCPeerID(displayName: UIDevice.current.name)
        // Always create a FRESH session - reusing a dead session is the reconnection bug
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .none)
        session.delegate = self
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser.delegate = self
    }

    // Restart mesh when app comes back to foreground
    private func setupAppLifecycleObservers() {
        let fg = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            print("📱 Foregrounded - restarting mesh")
            self?.restart()
        }
        appLifecycleObservers = [fg]
    }

    func start() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        isRunning = true
        // Cycle discovery every 15s if no peers found
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isRunning, self.connectedPeers.isEmpty else { return }
            print("🔄 No peers, cycling discovery")
            self.cycleDiscovery()
        }
        print("🟢 Mesh started")
    }

    func stop() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        isRunning = false
    }

    // Full restart: creates fresh session - fixes the won't-reconnect bug
    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.setupMesh()
            self?.start()
        }
    }

    private func cycleDiscovery() {
        browser.stopBrowsingForPeers()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.browser.startBrowsingForPeers()
        }
    }

    // MARK: - Public API

    func sendMessage(_ content: String) {
        let message = MeshMessage(senderID: deviceID, senderName: deviceName, content: content)
        DispatchQueue.main.async { self.messages.append(message) }
        markSeen(message.id)
        broadcast(.message(message))
    }

    func sendSOS(coordinate: CLLocationCoordinate2D, type: EmergencyType, medicalInfo: String? = nil) {
        let alert = SOSAlert(senderID: deviceID, senderName: deviceName, coordinate: coordinate, emergencyType: type, medicalInfo: medicalInfo)
        DispatchQueue.main.async { self.sosAlerts.append(alert) }
        markSeen(alert.id)
        broadcast(.sos(alert))
    }

    func broadcastLocation(_ coordinate: CLLocationCoordinate2D) {
        let info = PeerInfo(id: UUID(), peerID: deviceID, displayName: deviceName, latitude: coordinate.latitude, longitude: coordinate.longitude, timestamp: Date())
        broadcast(.ping(info))
    }

    func sendTypingIndicator() {
        broadcast(.typing(deviceName))
    }

    func sendResourceBroadcast(_ resource: ResourceBroadcast) {
        DispatchQueue.main.async { self.resourceBroadcasts.append(resource) }
        markSeen(resource.id)
        broadcast(.resource(resource))
    }

    // MARK: - Private

    private func broadcast(_ packet: MeshPacket) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(packet)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("❌ Broadcast failed: \(error)")
        }
    }

    private func markSeen(_ id: UUID) {
        seenIDsLock.lock(); seenMessageIDs.insert(id); seenIDsLock.unlock()
    }

    private func hasSeen(_ id: UUID) -> Bool {
        seenIDsLock.lock(); let s = seenMessageIDs.contains(id); seenIDsLock.unlock(); return s
    }

    private func handlePacket(_ packet: MeshPacket, from peerName: String) {
        if hasSeen(packet.id) { return }
        markSeen(packet.id)

        switch packet {
        case .message(var msg):
            msg.hopPath.append(deviceName)
            msg.ttl -= 1
            DispatchQueue.main.async { self.messages.append(msg) }
            if msg.ttl > 0 { broadcast(.message(msg)); DispatchQueue.main.async { self.relayedCount += 1 } }
            sendAck(messageID: msg.id, to: peerName)

        case .sos(var alert):
            alert.hopPath.append(deviceName)
            alert.ttl -= 1
            DispatchQueue.main.async { self.sosAlerts.append(alert) }
            if alert.ttl > 0 { broadcast(.sos(alert)); DispatchQueue.main.async { self.relayedCount += 1 } }

        case .ping(let info):
            DispatchQueue.main.async { self.peerLocations[info.peerID] = info }

        case .typing(let name):
            DispatchQueue.main.async {
                self.typingPeers.insert(name)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.typingPeers.remove(name) }
            }

        case .ack(let id):
            DispatchQueue.main.async { self.deliveredMessageIDs.insert(id) }

        case .resource(var r):
            r.hopPath.append(deviceName)
            r.ttl -= 1
            DispatchQueue.main.async { self.resourceBroadcasts.append(r) }
            if r.ttl > 0 { broadcast(.resource(r)) }
        }
    }

    private func sendAck(messageID: UUID, to peerName: String) {
        guard let peer = session.connectedPeers.first(where: { $0.displayName == peerName }) else { return }
        do {
            let data = try JSONEncoder().encode(MeshPacket.ack(messageID))
            try session.send(data, toPeers: [peer], with: .reliable)
        } catch {}
    }
}

// MARK: - MCSessionDelegate
extension MeshManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { self.connectedPeers = session.connectedPeers }
        switch state {
        case .connected: print("✅ Connected: \(peerID.displayName)")
        case .connecting: print("🔄 Connecting: \(peerID.displayName)")
        case .notConnected:
            print("❌ Disconnected: \(peerID.displayName)")
            // Cycle discovery to find them again
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.cycleDiscovery() }
        @unknown default: break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        do {
            let packet = try JSONDecoder().decode(MeshPacket.self, from: data)
            handlePacket(packet, from: peerID.displayName)
        } catch { print("❌ Decode failed: \(error)") }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MeshManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("❌ Advertising failed: \(error)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.advertiser.startAdvertisingPeer() }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MeshManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("👋 Lost: \(peerID.displayName)")
    }
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("❌ Browsing failed: \(error)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.browser.startBrowsingForPeers() }
    }
}
