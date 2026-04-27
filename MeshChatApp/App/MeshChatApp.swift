import SwiftUI
import SwiftData

@main
struct MeshChatApp: App {
    
    @StateObject private var container = AppContainer()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(container)
                .modelContainer(container.persistence.container)
                .onAppear { container.start() }
        }
    }
}
