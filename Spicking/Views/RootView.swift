import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var appViewModel: AppViewModel

    var body: some View {
        TabView {
            HomeView(appViewModel: appViewModel)
                .tabItem {
                    Label("홈", systemImage: "house")
                }

            PhrasebookView()
                .tabItem {
                    Label("표현장", systemImage: "text.book.closed")
                }
        }
        .environment(\.modelContext, modelContext)
    }
}
