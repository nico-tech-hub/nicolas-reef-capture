import Foundation // for Foundation types like String, Int, etc.
import SwiftData // for SwiftData types like ModelContext, FetchDescriptor, etc.

/// Drains PENDING observations one at a time.
/// The UI never waits on this type — callers use `Task { await queue.processPending() }`.
@MainActor
final class UploadQueue {
    private let modelContext: ModelContext
    private let api: any PhotoUploading
    private var isProcessing = false
    private var shouldRunAgain = false

    /// initializes the upload queue with the model context and the API
    init(modelContext: ModelContext, api: any PhotoUploading) {
        self.modelContext = modelContext
        self.api = api
    }

    /// Call once when the app becomes visible: recover crashed uploads, then drain the queue.
    func start() async {
        resetInterruptedUploads()
        await processPending()
    }

    /// processes the pending observations
    func processPending() async {
        if isProcessing {
            shouldRunAgain = true
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        repeat {
            shouldRunAgain = false
            while let observation = fetchPending() {
                await upload(observation)
            }
        } while shouldRunAgain
    }

    /// retries the upload of an observation
    func retry(_ observation: Observation) async {
        guard observation.uploadStatus == .failed else { return }
        observation.uploadStatus = .pending
        try? modelContext.save()
        await processPending()
    }

    /// resets the interrupted uploads
    private func resetInterruptedUploads() {
        let all = (try? modelContext.fetch(FetchDescriptor<Observation>())) ?? []
        for observation in all where observation.uploadStatus == .uploading {
            observation.uploadStatus = .pending
        }
        try? modelContext.save()
    }

    /// fetches the pending observations
    private func fetchPending() -> Observation? {
        let all = (try? modelContext.fetch(FetchDescriptor<Observation>())) ?? []
        return all
            .filter { $0.uploadStatus == .pending }
            .sorted { $0.createdAt < $1.createdAt }
            .first
    }

    /// uploads the observation to the API
    private func upload(_ observation: Observation) async {
        observation.uploadStatus = .uploading
        try? modelContext.save()

        do {
            let response = try await api.uploadPhoto(
                filePath: observation.localFilePath,
                idempotencyKey: observation.idempotencyKey
            )
            observation.uploadStatus = .uploaded
            observation.serverId = response.serverId
            observation.jobId = response.jobId
        } catch {
            observation.uploadStatus = .failed
            observation.retryCount += 1
        }

        try? modelContext.save()
    }
}
