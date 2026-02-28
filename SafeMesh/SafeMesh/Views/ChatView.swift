import SwiftUI

struct ChatView: View {
    @EnvironmentObject var meshManager: MeshManager
    @State private var messageText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Connection status bar
                connectionStatusBar

                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(meshManager.messages) { message in
                                MessageBubble(message: message, isOwn: message.senderID == meshManager.deviceID)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: meshManager.messages.count) { _, _ in
                        if let lastMessage = meshManager.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Input bar
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
                Text("\(meshManager.connectedPeers.count) device\(meshManager.connectedPeers.count == 1 ? "" : "s") connected")
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
    }
}

struct MessageBubble: View {
    let message: MeshMessage
    let isOwn: Bool

    var body: some View {
        VStack(alignment: isOwn ? .trailing : .leading, spacing: 4) {
            // Sender name (for received messages)
            if !isOwn {
                Text(message.senderName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Message content
            HStack {
                if isOwn { Spacer(minLength: 60) }

                VStack(alignment: .leading, spacing: 4) {
                    Text(message.content)
                        .foregroundStyle(.white)

                    // Hop path visualization
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

            // Timestamp
            Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: isOwn ? .trailing : .leading)
    }
}

#Preview {
    ChatView()
        .environmentObject(MeshManager())
        .preferredColorScheme(.dark)
}
