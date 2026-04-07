import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var appViewModel: AppViewModel

    var body: some View {
        TabView {
            HomeView(appViewModel: appViewModel)
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            PhrasebookView()
                .tabItem {
                    Label("Phrasebook", systemImage: "text.book.closed")
                }
        }
        .environment(\.modelContext, modelContext)
    }
}
