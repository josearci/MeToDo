import SwiftUI

struct MainWindow: View {
    var body: some View {
        Text("MeToDo")
            .frame(minWidth: 640, minHeight: 420)
            .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate() }
            .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }
}
