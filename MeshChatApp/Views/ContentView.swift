import SwiftUI

struct ContentView: View {
    @EnvironmentObject var container: AppContainer
    
    var body: some View {
        TabView {
            NearbyPeersView()
                .tabItem {
                    Label("Nearby", systemImage: "antenna.radiowaves.left.and.right")
                }
            ChatListView()
                .tabItem {
                    Label("Chats", systemImage: "bubble.left.and.bubble.right.fill")
                }
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
        .tint(.blue)
    }
}
