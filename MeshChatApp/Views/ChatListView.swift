import SwiftUI
import SwiftData

struct ChatListView: View {
    @EnvironmentObject var container: AppContainer
    @Query(sort: \Chat.lastMessageAt, order: .reverse) var chats: [Chat]
    
    var body: some View {
        NavigationStack {
            Group {
                if chats.isEmpty {
                    ContentUnavailableView(
                        "No Chats Yet",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Connect to a nearby device to start chatting.")
                    )
                } else {
                    List(chats) { chat in
                        NavigationLink(destination: ChatView(chat: chat)) {
                            ChatRow(chat: chat)
                        }
                    }
                }
            }
            .navigationTitle("Chats")
        }
    }
}

struct ChatRow: View {
    let chat: Chat
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.blue.gradient)
                .frame(width: 48, height: 48)
                .overlay {
                    Text(chat.peer?.displayName.prefix(1).uppercased() ?? "?")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(chat.peer?.displayName ?? "Unknown")
                        .font(.headline)
                    Spacer()
                    Text(chat.lastMessageAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(chat.lastMessagePreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
