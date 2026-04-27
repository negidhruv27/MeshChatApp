import SwiftUI
import SwiftData

// MARK: - ChatView (thin shell — passes real dependencies into content)

struct ChatView: View {
    let chat: Chat
    @EnvironmentObject var container: AppContainer

    var body: some View {
        ChatContent(
            chat: chat,
            mesh: container.meshService,
            persistence: container.persistence,
            myUUID: container.myUUID
        )
        .navigationTitle(chat.peer?.displayName ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - ChatContent (owns the ViewModel with real dependencies)

private struct ChatContent: View {
    @StateObject private var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool

    init(chat: Chat, mesh: MeshService, persistence: PersistenceManager, myUUID: String) {
        // ✅ real mesh + real myUUID — peerMetadata will actually contain the peer
        _viewModel = StateObject(wrappedValue: ChatViewModel(
            chat: chat,
            mesh: mesh,
            persistence: persistence,
            myUUID: myUUID
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            EncryptionStatusBar()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let last = viewModel.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            // Input bar
            HStack(spacing: 12) {
                TextField("Message", text: $viewModel.draftText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .onSubmit { viewModel.sendMessage() }

                Button {
                    viewModel.sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(viewModel.draftText.isEmpty ? .gray : .blue)
                }
                .disabled(viewModel.draftText.isEmpty || viewModel.isSending)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

// MARK: - EncryptionStatusBar

struct EncryptionStatusBar: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption2)
            Text("End-to-end encrypted · Offline")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
}

// MARK: - MessageBubble

struct MessageBubble: View {
    let message: Message

    var isOutgoing: Bool { message.direction == .outgoing }

    var body: some View {
        HStack {
            if isOutgoing { Spacer(minLength: 60) }

            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isOutgoing ? Color.blue : Color(.secondarySystemBackground))
                    .foregroundStyle(isOutgoing ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 4) {
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if isOutgoing {
                        statusIcon
                    }
                }
            }

            if !isOutgoing { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch message.status {
        case .sending:
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .sent:
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .delivered:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.blue)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }
}
