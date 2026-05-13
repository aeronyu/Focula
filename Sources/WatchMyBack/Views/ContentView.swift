import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            GoalListView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            DashboardView()
        }
    }
}
