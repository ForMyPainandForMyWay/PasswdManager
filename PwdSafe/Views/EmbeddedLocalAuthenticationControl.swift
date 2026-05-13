import SwiftUI
import LocalAuthentication
import LocalAuthenticationEmbeddedUI

struct EmbeddedLocalAuthenticationControl: NSViewRepresentable {
    let authenticationContext: LAContext
    var controlSize: NSControl.ControlSize = .large

    func makeNSView(context: Context) -> LAAuthenticationView {
        let view = LAAuthenticationView(
            context: authenticationContext,
            controlSize: controlSize
        )
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: LAAuthenticationView, context: Context) {}
}
