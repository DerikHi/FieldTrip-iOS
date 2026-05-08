import SwiftUI
import FirebaseCore

@main
struct FieldTripApp: App {
    init() {
        // TODO: Add GoogleService-Info.plist to your Xcode project
        FirebaseApp.configure()

        // TODO: Configure Firebase App Check for production
        // #if DEBUG
        // let providerFactory = AppCheckDebugProviderFactory()
        // AppCheck.setAppCheckProviderFactory(providerFactory)
        // #else
        // let providerFactory = DeviceCheckProviderFactory()
        // AppCheck.setAppCheckProviderFactory(providerFactory)
        // #endif
    }

    var body: some Scene {
        WindowGroup {
            SplashRouterView()
        }
    }
}
