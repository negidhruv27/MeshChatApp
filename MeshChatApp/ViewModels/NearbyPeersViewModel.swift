import Foundation
import MultipeerConnectivity
import Combine

@MainActor
final class NearbyPeersViewModel: ObservableObject {
    
    @Published var nearbyPeers: [MCPeerID] = []
    @Published var connectedPeers: [MCPeerID] = []
    @Published var connectionState: MeshService.ConnectionState = .idle
    
    private let mesh: MeshService
    private var cancellables = Set<AnyCancellable>()
    
    init(mesh: MeshService) {
        self.mesh = mesh
        
        mesh.$nearbyPeers
            .receive(on: DispatchQueue.main)
            .assign(to: &$nearbyPeers)
        
        mesh.$connectedPeers
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectedPeers)
        
        mesh.$connectionState
            .receive(on: DispatchQueue.main)
            .assign(to: &$connectionState)
    }
    
    func connectTo(_ peer: MCPeerID) {
        mesh.invitePeer(peer)
    }
}
