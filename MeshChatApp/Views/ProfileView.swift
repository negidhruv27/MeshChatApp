import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var container: AppContainer
    @State private var displayName = UIDevice.current.name
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    HStack {
                        Text("Display Name")
                        Spacer()
                        Text(displayName)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Device UUID")
                        Spacer()
                        Text(container.myUUID.prefix(8) + "…")
                            .foregroundStyle(.secondary)
                            .font(.caption.monospaced())
                    }
                }
                
                Section("Security") {
                    Label("Curve25519 End-to-End Encryption", systemImage: "lock.shield.fill")
                        .foregroundStyle(.green)
                    Label("AES-GCM Message Authentication", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.blue)
                    Label("Keys stored in Keychain", systemImage: "key.fill")
                        .foregroundStyle(.secondary)
                }
                
                Section("Network") {
                    Label("MultipeerConnectivity (BT + WiFi)", systemImage: "antenna.radiowaves.left.and.right")
                    Label("Zero internet dependency", systemImage: "wifi.slash")
                    Label("Automatic peer discovery", systemImage: "magnifyingglass")
                }
            }
            .navigationTitle("Profile")
        }
    }
}
