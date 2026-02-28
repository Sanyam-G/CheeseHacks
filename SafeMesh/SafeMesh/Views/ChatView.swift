import SwiftUI

struct ChatView: View {
    @EnvironmentObject var meshManager: MeshManager
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool
    @State private var typingDebounce: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                connectionStatusBar

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(meshManager.messages) { message in
                                MessageBubble(
                                    message: message,
                                    isOwn: message.senderID == meshManager.deviceID,
                                    isDelivered: meshManager.deliveredMessageIDs.contains(message.id)
                                )
                                .id(message.id)
                            }

                            // Typing indicator
                            if !meshManager.typingPeers.isEmpty {
                                TypingIndicator(peers: meshManager.typingPeers)
                                    .id("typing")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: meshManager.messages.count) { _, _ in
                        if let last = meshManager.messages.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: meshManager.typingPeers.isEmpty) { _, isEmpty in
                        if !isEmpty {
                            withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                        }
                    }
                }

                inputBar
            }
            .navigationTitle("SafeMesh")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(meshManager.isRunning ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text("\(meshManager.connectedPeers.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var connectionStatusBar: some View {
        HStack {
            Image(systemName: "antenna.radiowaves.left.and.right")
            if meshManager.connectedPeers.isEmpty {
                Text("Searching for nearby devices...")
                    .font(.caption)
            } else {
                Text("\(meshManager.connectedPeers.count) device\(meshManager.connectedPeers.count == 1 ? "" : "s") connected · \(meshManager.relayedCount) relayed")
                    .font(.caption)
            }
            Spacer()
        }
        .foregroundStyle(meshManager.connectedPeers.isEmpty ? .orange : .green)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $messageText)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color(.systemGray5))
                .cornerRadius(20)
                .focused($isInputFocused)
                .onChange(of: messageText) { _, newValue in
                    // Send typing indicator with debounce
                    if !newValue.isEmpty {
                        typingDebounce?.cancel()
                        typingDebounce = Task {
                            meshManager.sendTypingIndicator()
                        }
                    }
                }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(messageText.isEmpty ? .gray : .blue)
            }
            .disabled(messageText.isEmpty)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        meshManager.sendMessage(messageText)
        messageText = ""
        typingDebounce?.cancel()
    }
}

struct MessageBubble: View {
    let message: MeshMessage
    let isOwn: Bool
    let isDelivered: Bool

    var body: some View {
        VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
            if !isOwn {
                Text(message.senderName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if isOwn { Spacer(minLength: 60) }

                VStack(alignment: .leading, spacing: 4) {
                    Text(message.content)
                        .foregroundStyle(.white)

                    if message.hopPath.count > 1 {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 10))
                            Text(message.hopPath.joined(separator: " → "))
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isOwn ? Color.blue : Color(.systemGray4))
                .cornerRadius(18)

                if !isOwn { Spacer(minLength: 60) }
            }

            // Timestamp + delivery receipt
            HStack(spacing: 4) {
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if isOwn {
                    Image(systemName: isDelivered ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(isDelivered ? .green : .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
    }
}

// Animated typing indicator
struct TypingIndicator: View {
    let peers: Set<String>
    @State private var dot1 = false
    @State private var dot2 = false
    @State private var dot3 = false

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(peers.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    ForEach([dot1, dot2, dot3].indices, id: \.self) { i in
                        Circle()
                            .fill(Color(.systemGray3))
                            .frame(width: 8, height: 8)
                            .scaleEffect([dot1, dot2, dot3][i] ? 1.3 : 0.8)
                            .animation(.easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15), value: [dot1, dot2, dot3][i])
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.systemGray5))
                .cornerRadius(18)
            }
            Spacer(minLength: 60)
        }
        .onAppear {
            dot1 = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { dot2 = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { dot3 = true }
        }
    }
}

#Preview {
    ChatView()
        .environmentObject(MeshManager())
        .preferredColorScheme(.dark)
}
