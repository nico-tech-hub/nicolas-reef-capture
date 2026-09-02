import PhotosUI // provides the PhotosUI framework for the app
import SwiftData // provides the SwiftData framework for the app
import SwiftUI // provides the SwiftUI framework for the app

/// Main view for the app
/// Shows the list of observations and the picker for the photo
/// Allows the user to select a photo from the library and save it locally
/// Allows the user to retry the upload of a photo
/// Shows the status of the upload and the processing of the photo
struct ContentView: View { 

    var api: any PhotoUploading = FakePhotoAPI() // API to use for the app, using the FakePhotoAPI or real API ReefCaptureAPI
    @Environment(\.modelContext) private var modelContext // environment context for the app
    @Query(sort: \ReefObservation.createdAt, order: .reverse) private var observations: [ReefObservation] // observations sorted by creation date in reverse order

    /// This view owns the picker selection. `$selectedItem` is a Binding passed to PhotosPicker.
    @State private var selectedItem: PhotosPickerItem? // selected item for the picker
    @State private var importFailed = false // import failed flag
    @State private var queue: UploadQueue? // queue for the app

    private let photoStore = PhotoStore.live // photo store for the app, using the live photo store if the app is running in the simulator, otherwise the fake photo store

    /// body for the app
    var body: some View { 
        NavigationStack { 
            Group {
                if observations.isEmpty { // if there are no observations, show the content unavailable view
                    ContentUnavailableView(
                        "No observations yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Tap Select Photo to save a reef observation locally.")
                    )
                } else { // if there are observations, show the list of observations
                    List {
                        ForEach(observations) { observation in
                            ObservationRow(
                                observation: observation,
                                image: photoStore.loadImage(at: observation.localFilePath),
                                onRetry: {
                                    Task { await ensureQueue().retry(observation) }
                                }
                            )
                        }
                        .onDelete(perform: deleteObservations)
                    }
                }
            }
            .navigationTitle("ReefCapture") // navigation title for the app
            .toolbar { // toolbar for the app
                ToolbarItem(placement: .primaryAction) { // primary action for the toolbar
                    PhotosPicker(
                        "Select Photo",
                        selection: $selectedItem,
                        matching: .images
                    )
                }
            } 
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return } // return if the new item is nil
                Task {
                    await importPhoto(newItem) // import the photo
                    selectedItem = nil // set the selected item to nil
                }
            }
            .task {
                await ensureQueue().start() // start the queue
            }
            .alert("Could not import photo", isPresented: $importFailed) {
                Button("OK", role: .cancel) {} // button to close the alert
            }
        }
    } // end of body


    /// ensure the queue is created and started
    @MainActor
    private func ensureQueue() -> UploadQueue {
        if let queue { // if the queue exists, return it
            return queue
        }
        let created = UploadQueue(modelContext: modelContext, api: api) // create the queue
        queue = created
        return created // return the created queue
    }

    /// import the photo from the picker
    @MainActor
    private func importPhoto(_ item: PhotosPickerItem) async {
        do { // try to import the photo
            guard let rawData = try await item.loadTransferable(type: Data.self),    // load the transferable data from the item
                let jpeg = photoStore.jpegData(from: rawData) else { // convert the data to a JPEG, returns the JPEG data
                    importFailed = true // set the import failed flag to true
                    return // return if the data is not valid
            }

            let id = UUID() // create a new UUID for the observation
            let path = try photoStore.save(jpeg, id: id) // save the photo to the photo store, returns the path to the photo
            let observation = ReefObservation(id: id, localFilePath: path) // create the observation, with the id and the path to the photo
            modelContext.insert(observation)   // insert the observation into the model context, this is a SwiftData operation

            // Do not await the drain: the UI must stay responsive.
            Task { await ensureQueue().processPending() }
        } catch {
            importFailed = true
        }
    }

    /// Swipe-to-delete: always drop the local row + JPEG first (user intent).
    /// Then best-effort DELETE /photos/:id. A network failure must not resurrect the row.
    @MainActor
    private func deleteObservations(at offsets: IndexSet) {
        let items = offsets.map { observations[$0] }
        for observation in items {
            Task { await deleteObservation(observation) }
        }
    }

    @MainActor
    private func deleteObservation(_ observation: ReefObservation) async {
        let serverId = observation.serverId
        let path = observation.localFilePath
        let shortId = String(observation.id.uuidString.prefix(8)).uppercased()
        modelContext.delete(observation)
        try? modelContext.save()
        photoStore.delete(at: path)

        if let serverId {
            // #region agent log
            debugAgentLog(hypothesisId: "F", location: "ContentView.swift:deleteObservation", message: "iOS local delete then DELETE /photos", data: ["shortId": shortId, "hasServerId": true, "serverId": serverId])
            // #endregion
            try? await api.deletePhoto(serverId: serverId)
        } else {
            // #region agent log
            debugAgentLog(hypothesisId: "G", location: "ContentView.swift:deleteObservation", message: "iOS local delete skipped server (no serverId)", data: ["shortId": shortId, "hasServerId": false])
            // #endregion
        }
    }
}

// #region agent log
func debugAgentLog(hypothesisId: String, location: String, message: String, data: [String: Any]) {
    let payload: [String: Any] = [
        "sessionId": "fcb216",
        "hypothesisId": hypothesisId,
        "location": location,
        "message": message,
        "data": data,
        "timestamp": Int(Date().timeIntervalSince1970 * 1000),
    ]
    guard let json = try? JSONSerialization.data(withJSONObject: payload),
          var line = String(data: json, encoding: .utf8) else { return }
    line += "\n"
    let url = URL(fileURLWithPath: "/Users/nicolasfarolfi/Documents/ReefCapture/.cursor/debug-fcb216.log")
    if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    guard let handle = try? FileHandle(forWritingTo: url) else { return }
    defer { try? handle.close() }
    try? handle.seekToEnd()
    try? handle.write(contentsOf: Data(line.utf8))
}
// #endregion

/// preview for the app
#Preview {
    ContentView(api: FakePhotoAPI(delayNanoseconds: 0))
        .modelContainer(for: ReefObservation.self, inMemory: true)
}
