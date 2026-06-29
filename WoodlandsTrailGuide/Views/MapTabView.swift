import SwiftUI
import MapKit

struct MapTabView: View {
    @Environment(TrailStore.self) private var store
    @Environment(LocationManager.self) private var locationManager
    @State private var selectedWay: TrailGraph.Way?

    var body: some View {
        ZStack(alignment: .bottom) {
            if let graph = store.graph {
                TrailMapView(graph: graph, selectedWay: $selectedWay)
                    .ignoresSafeArea(edges: .top)
            } else {
                ProgressView("Loading trails...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            locationManager.requestPermission()
        }
        .sheet(item: $selectedWay) { way in
            TrailDetailSheet(way: way)
                .presentationDetents([.height(220), .medium])
        }
    }
}

extension TrailGraph.Way: Identifiable {
    /// Synthetic id for sheet presentation. Uses pathwayID when present (stable
    /// across data refreshes) and falls back to a hash of the node list.
    var id: String {
        if let p = pathwayID { return "p:" + p }
        return "n:" + nodeIndices.prefix(4).map(String.init).joined(separator: "-")
    }
}
