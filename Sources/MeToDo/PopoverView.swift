import SwiftUI

struct PopoverView: View {
    var body: some View {
        VStack {
            Text("MeToDo")
            Button("Quit MeToDo") { NSApp.terminate(nil) }
        }
        .frame(width: 340, height: 440)
    }
}
