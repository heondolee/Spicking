import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var appViewModel = AppViewModel()

    var body: some View {
        RootView(appViewModel: appViewModel)
            .environment(\.modelContext, modelContext)
            .fullScreenCover(item: $appViewModel.activeConversation) { conversationViewModel in
                ConversationFlowView(
                    viewModel: conversationViewModel,
                    onClose: {
                        appViewModel.finishConversationFlow()
                    }
                )
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { appViewModel.alertMessage != nil },
                set: { newValue in
                    if !newValue {
                        appViewModel.alertMessage = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {
                    appViewModel.alertMessage = nil
                }
            } message: {
                Text(appViewModel.alertMessage ?? "Unknown error")
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.makeContainer())
}
