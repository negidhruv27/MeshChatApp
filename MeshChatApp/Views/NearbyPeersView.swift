import SwiftUI
import MultipeerConnectivity

// MARK: - NearbyPeersView

struct NearbyPeersView: View {
    @EnvironmentObject var container: AppContainer

    var body: some View {
        NavigationStack {
            NearbyPeersContent(mesh: container.meshService)
        }
    }
}

// MARK: - NearbyPeersContent (owns the ViewModel)

private struct NearbyPeersContent: View {
    @StateObject private var viewModel: NearbyPeersViewModel

    init(mesh: MeshService) {
        _viewModel = StateObject(wrappedValue: NearbyPeersViewModel(mesh: mesh))
    }

    var body: some View {
        List {
            // CONNECTED SECTION
            if !viewModel.connectedPeers.isEmpty {
                Section("Connected") {
                    ForEach(viewModel.connectedPeers, id: \.displayName) { peer in
                        PeerRow(peer: peer, isConnected: true) { }
                    }
                }
            }

            // NEARBY (not yet connected)
            Section("Nearby Devices") {
                if viewModel.nearbyPeers.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            Text("Scanning for nearby devices…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 24)
                } else {
                    ForEach(viewModel.nearbyPeers, id: \.displayName) { peer in
                        PeerRow(peer: peer, isConnected: false) {
                            viewModel.connectTo(peer)
                        }
                    }
                }
            }
        }
        .navigationTitle("Nearby")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ConnectionStatusBadge(state: viewModel.connectionState)
            }
        }
    }
}

// MARK: - PeerRow

struct PeerRow: View {
    let peer: MCPeerID
    let isConnected: Bool
    let onConnect: () -> Void

    var body: some View {
        HStack {
            Image(systemName: isConnected ? "checkmark.circle.fill" : "iphone")
                .foregroundStyle(isConnected ? .green : .blue)
                .font(.title2)

            VStack(alignment: .leading) {
                Text(peer.displayName)
                    .font(.headline)
                Text(isConnected ? "Connected" : "Tap to connect")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isConnected {
                Button("Connect", action: onConnect)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ConnectionStatusBadge

struct ConnectionStatusBadge: View {
    let state: MeshService.ConnectionState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        switch state {
        case .connected:              return .green
        case .connecting:             return .orange
        case .advertising, .browsing: return .blue
        case .idle:                   return .gray
        }
    }

    private var label: String {
        switch state {
        case .connected:              return "Online"
        case .connecting:             return "Connecting…"
        case .advertising, .browsing: return "Scanning"
        case .idle:                   return "Offline"
        }
    }
}
