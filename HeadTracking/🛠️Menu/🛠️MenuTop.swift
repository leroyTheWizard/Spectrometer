import SwiftUI

struct 🛠️MenuTop: View {
    @Environment var model: AppModel
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 28) {
                Button {
                    Task { await self.dismissImmersiveSpace() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "escape")
                            .imageScale(.small)
                        Text("Exit")
                    }
                    .font(.title.weight(.regular))
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                }
                .buttonStyle(.plain)
                .glassBackgroundEffect()
                Button {
                    self.model.presentPanel = .about
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "questionmark")
                            .imageScale(.small)
                        Text("About")
                    }
                    .font(.title.weight(.regular))
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                }
                .buttonStyle(.plain)
                .disabled(self.model.presentPanel == .about)
                .glassBackgroundEffect()
            }
            ZStack(alignment: .top) {
                🛠️AboutPanel()
                    .environment(self.model)
                    .glassBackgroundEffect()
                    .opacity(self.model.presentPanel == .about ? 1 : 0)
            }
        }
        .animation(.default, value: self.model.presentPanel)
        .offset(y: -1750)
        .offset(z: -700)
    }
}


enum 🛠️Panel {
    case setting,
         about
}
