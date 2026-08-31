import SwiftUI // provides the SwiftUI framework for the app
import SwiftData // provides the SwiftData framework for the app

@main // entry point for the app
struct ReefCaptureApp: App { // main app struct
    var body: some Scene { // defines the body of the app
        WindowGroup { // defines the window group for the app
            ContentView(api: ReefCaptureAPI()) // provides the content view for the app, build the HTTP client
        }
        .modelContainer(for: Observation.self) // provides the model container for the app
    }
} // end of ReefCaptureApp struct
