# SafeMesh — Emergency Mesh Communication for iOS

## Project Overview

SafeMesh turns iPhones into nodes in a mesh network. Messages hop phone-to-phone via Bluetooth — no towers, no WiFi, no internet. Works on airplane mode with Bluetooth enabled.

## Demo Flow (90 seconds)

1. Show 3-4 iPhones on airplane mode (Bluetooth re-enabled)
2. Type message on Phone A → appears on Phone B
3. Phone B relays → appears on Phone C (not directly connected to A)
4. Trigger SOS on Phone A → ALL phones light up red with GPS coordinates
5. "These phones formed their own network. No towers. No internet."

## Project Structure

```
SafeMesh/
├── SafeMesh.xcodeproj
└── SafeMesh/
    ├── SafeMeshApp.swift          # App entry point, dark mode, starts mesh
    ├── Info.plist                  # All required permissions
    ├── Assets.xcassets/
    ├── Models/
    │   └── Message.swift           # MeshMessage, SOSAlert, MeshPacket, PeerInfo
    ├── Managers/
    │   ├── MeshManager.swift       # MultipeerConnectivity mesh networking
    │   └── LocationManager.swift   # GPS/CoreLocation
    └── Views/
        ├── ContentView.swift       # Main tab view + SOS overlay trigger
        ├── ChatView.swift          # Message list with hop path visualization
        ├── SOSView.swift           # Emergency type picker + giant SOS button
        ├── SOSAlertOverlay.swift   # Full-screen red pulsing alert
        ├── MapView.swift           # Map with peer pins + SOS markers
        └── NetworkStatusView.swift # Connected peers, relay stats
```

## Core Features Implemented

### 1. Mesh Networking (MeshManager.swift)
- Uses Apple's `MultipeerConnectivity` framework
- Service type: `safemesh`
- Auto-discovery and auto-connect (no manual pairing)
- Auto-accepts all peer invitations
- Broadcasts to all connected peers

### 2. Multi-hop Relay
- Every message has a UUID for deduplication
- `seenMessageIDs: Set<UUID>` prevents infinite loops
- TTL (time-to-live) decrements each hop
- Default TTL: 5 for messages, 10 for SOS
- Messages relay automatically when TTL > 0

### 3. Message Types (Message.swift)
- `MeshMessage`: text messages with hop path tracking
- `SOSAlert`: GPS coordinates, emergency type, medical info
- `MeshPacket`: wrapper enum for network transmission
- `PeerInfo`: peer location broadcasts

### 4. SOS System
- Emergency types: Medical, Trapped, Fire, Flood, Other
- Giant red SOS button with confirmation dialog
- Higher TTL (10) for priority relay
- Full-screen red pulsing overlay on receiving devices
- Haptic feedback + alert sound
- Shows distance to sender

### 5. Offline Map (MapView.swift)
- User location (blue)
- Connected peers as pins (green)
- SOS alerts as pulsing red markers
- Tap SOS marker for details + "Open in Maps" navigation

### 6. Network Status (NetworkStatusView.swift)
- Connected peer count
- Messages sent/received
- Relay count
- GPS status
- Start/stop mesh controls

## Required Info.plist Permissions

```xml
NSLocalNetworkUsageDescription - Local network for mesh
NSBonjourServices - _safemesh._tcp, _safemesh._udp
NSLocationWhenInUseUsageDescription - GPS for SOS
NSLocationAlwaysAndWhenInUseUsageDescription - Background GPS
NSBluetoothAlwaysUsageDescription - Bluetooth mesh
NSBluetoothPeripheralUsageDescription - Bluetooth mesh
UIBackgroundModes - bluetooth-central, bluetooth-peripheral
```

## Technical Notes

- **Simulator won't work** - MultipeerConnectivity requires real devices
- **Bluetooth range**: ~30-100 feet
- **For multi-hop demo**: Position Phone A and C out of range, with B in the middle
- **All delegate callbacks come on background threads** - dispatch UI to main
- **Dark mode enforced** via `.preferredColorScheme(.dark)`
- **iOS 17.0+ required**

## Build Instructions

1. Open `SafeMesh.xcodeproj` in Xcode
2. Select your Team in Signing & Capabilities
3. Connect real iPhone via USB
4. Select device from dropdown
5. Press `Cmd + R` to build and run
6. Trust developer on iPhone: Settings → General → VPN & Device Management

## Testing Checklist

- [ ] Two phones send messages on airplane mode
- [ ] Multi-hop relay across 3 phones (A → B → C)
- [ ] Hop path shows in message bubble
- [ ] SOS broadcasts with GPS
- [ ] Full-screen red alert appears on other devices
- [ ] Map shows SOS pins with distance
- [ ] Network status shows connected peers

## Key Code Patterns

### Deduplication (critical)
```swift
private var seenMessageIDs: Set<UUID> = []

private func hasSeen(_ id: UUID) -> Bool {
    seenIDsLock.lock()
    let seen = seenMessageIDs.contains(id)
    seenIDsLock.unlock()
    return seen
}
```

### Auto-accept invitations
```swift
func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                didReceiveInvitationFromPeer peerID: MCPeerID,
                withContext context: Data?,
                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
    invitationHandler(true, session) // Always accept
}
```

### Relay logic
```swift
if message.ttl > 0 {
    broadcast(.message(message))
    relayedCount += 1
}
```

## What NOT to Do

- No cloud services, APIs, servers
- No AI/LLM features
- No third-party dependencies
- Don't over-engineer

## Bundle Identifier

`com.safemesh.app`

## Status

✅ Core mesh networking implemented
✅ Multi-hop relay with deduplication
✅ SOS broadcast with GPS
✅ Full-screen SOS alert overlay
✅ Offline map with peer/SOS pins
✅ Network status view
✅ Dark mode UI
✅ All required permissions in Info.plist

## Next Steps

1. Test on real devices
2. Pre-cache map tiles for demo venue
3. Add app icon
4. Polish animations if time permits
