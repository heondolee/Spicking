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
            .alert("문제가 발생했어요", isPresented: Binding(
                get: { appViewModel.alertMessage != nil },
                set: { newValue in
                    if !newValue {
                        appViewModel.alertMessage = nil
                    }
                }
            )) {
                Button("확인", role: .cancel) {
                    appViewModel.alertMessage = nil
                }
            } message: {
                Text(appViewModel.alertMessage ?? "알 수 없는 오류가 발생했어요.")
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.makeContainer())
}
