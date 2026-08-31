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
    @Query(sort: \Observation.createdAt, order: .reverse) private var observations: [Observation] // observations sorted by creation date in reverse order

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
                    List(observations) { observation in
                        ObservationRow(
                            observation: observation,
                            image: photoStore.loadImage(at: observation.localFilePath),
                            onRetry: {
                                Task { await ensureQueue().retry(observation) }
                            }
                        )
                    }
                }
            }
            .navigationTitle("ReefCapture") // navigation title for the app
            .toolbar { // toolbar for the app
                ToolbarItem(placement: .primaryAction) { // primary action for the toolbar
                    PhotosPicker( // picker 
                        "Select Photo", 
                        selection: $selectedItem, /
                        matching: .images 
                    )
                }
            } 
            .onChange(of: selectedItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await importPhoto(newItem)
                    selectedItem = nil
                }
            }
            .task {
                await ensureQueue().start()
            }
            .alert("Could not import photo", isPresented: $importFailed) {
                Button("OK", role: .cancel) {}
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
            guard let rawData = try await item.loadTransferable(type: Data.self),   
                  let jpeg = photoStore.jpegData(from: rawData) else {
                importFailed = true
                return
            }

            let id = UUID() // create a new UUID for the observation
            let path = try photoStore.save(jpeg, id: id) // save the photo to the photo store
            let observation = Observation(id: id, localFilePath: path) // create the observation
            modelContext.insert(observation)   // insert the observation into the model context

            // Do not await the drain: the UI must stay responsive.
            Task { await ensureQueue().processPending() }
        } catch {
            importFailed = true
        }
    }
}

/// preview for the app
#Preview {
    ContentView(api: FakePhotoAPI(delayNanoseconds: 0))
        .modelContainer(for: Observation.self, inMemory: true)
}
