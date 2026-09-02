import Foundation // for Foundation types like String, Int, etc.
import SwiftData // for SwiftData types like ModelContext, FetchDescriptor, etc.

/// Drains PENDING observations one at a time.
/// The UI never waits on this type — callers use `Task { await queue.processPending() }`.
@MainActor
final class UploadQueue {
    private let modelContext: ModelContext
    private let api: any PhotoUploading
    private let pollIntervalNanoseconds: UInt64
    private var isProcessing = false
    private var shouldRunAgain = false
    private var pollingTasks: [Task<Void, Never>] = []
    private var pollingIds: Set<UUID> = []

    /// initializes the upload queue with the model context and the API
    init(
        modelContext: ModelContext,
        api: any PhotoUploading,
        pollIntervalNanoseconds: UInt64 = 500_000_000
    ) {
        self.modelContext = modelContext
        self.api = api
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
    }

    /// Call once when the app becomes visible: recover crashed uploads, resume job polls, then drain the queue.
    func start() async {
        resetInterruptedUploads()
        resumeProcessingPolls()
        await processPending()
    }

    /// processes the pending observations
    /// objective: process the pending observations one at a time
    func processPending() async {
        if isProcessing { // if the queue is already processing, set the should run again flag to true
            shouldRunAgain = true
            return
        }

        isProcessing = true // set the processing flag to true
        defer { isProcessing = false } // set the processing flag to false when the function exits

        repeat { // repeat the process until the should run again flag is false
            shouldRunAgain = false
            while let observation = fetchPending() { // fetch the pending observations
                await upload(observation) // upload the observation
            }
        } while shouldRunAgain
    }

    /// Used by tests to wait until background job polling finishes.
    func waitForPolling() async {
        let tasks = pollingTasks
        for task in tasks {
            await task.value
        }
    }

    /// retries the upload of an observation
    func retry(_ observation: ReefObservation) async {
        guard observation.uploadStatus == .failed else { return }
        observation.uploadStatus = .pending
        try? modelContext.save()
        await processPending()
    }

    /// resets the interrupted uploads
    ///  crash during UPLOADING → updates to PENDING
    private func resetInterruptedUploads() {
        let all = (try? modelContext.fetch(FetchDescriptor<ReefObservation>())) ?? []
        for observation in all where observation.uploadStatus == .uploading {
            observation.uploadStatus = .pending
        }
        try? modelContext.save()
    }

    /// fetches the pending observations
    /// objective: fetch the pending observations
    /// return the pending observations sorted by created at
    private func fetchPending() -> ReefObservation? {
        let all = (try? modelContext.fetch(FetchDescriptor<ReefObservation>())) ?? [] // fetch the observations
        return all // return the pending observations sorted by created at
            .filter { $0.uploadStatus == .pending }    // filter the observations to only include the pending observations
            .sorted { $0.createdAt < $1.createdAt }    // sort the observations by created at
            .first    // return the first observation
    }

    /// uploads the observation to the API
    private func upload(_ observation: ReefObservation) async {
        let id = observation.id // get the id of the observation
        observation.uploadStatus = .uploading // set the upload status to uploading
        try? modelContext.save() // save the mutated observation to the model context

        do { // try to upload the observation to the API
            let response = try await api.uploadPhoto(
                filePath: observation.localFilePath, // get the local file path of the observation
                idempotencyKey: observation.idempotencyKey // get the idempotency key of the observation
            )
            guard let current = self.observation(id: id) else {
                try? await api.deletePhoto(serverId: response.serverId)
                return
            }
            current.uploadStatus = .uploaded
            current.serverId = response.serverId
            current.jobId = response.jobId
            let jobId = response.jobId
            if jobId != nil {
                current.processingStatus = .processing
            }
            try? modelContext.save()
            if let jobId {
                startPolling(id: id, jobId: jobId)
            }
        } catch {
            guard let current = self.observation(id: id) else { return }
            current.uploadStatus = .failed
            current.retryCount += 1
            try? modelContext.save()
        }
    }

    /// Resume GET /jobs/:id for rows already PROCESSING (app relaunch mid-job).
    private func resumeProcessingPolls() {
        let all = (try? modelContext.fetch(FetchDescriptor<ReefObservation>())) ?? []
        for observation in all where observation.processingStatus == .processing {
            guard let jobId = observation.jobId else { continue }
            startPolling(id: observation.id, jobId: jobId)
        }
    }

    /// START POLLING - start polling the job
    /// return the job id
    private func startPolling(id: UUID, jobId: String) {
        guard pollingIds.insert(id).inserted else { return }
        let task = Task {
            await self.pollJob(id: id, jobId: jobId)
            pollingIds.remove(id)
        }
        pollingTasks.append(task)
    }

    /// Polls GET /jobs/:id without blocking the upload queue or the UI.
    private func pollJob(id: UUID, jobId: String) async {
        for attempt in 0..<20 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
            }
            guard observation(id: id) != nil else { return }
            guard let job = try? await api.fetchJobStatus(jobId: jobId) else {
                continue
            }
            guard let current = observation(id: id) else { return }
            if job.status == "COMPLETED" {
                current.processingStatus = .completed
                try? modelContext.save()
                return
            }
            if job.status == "FAILED" {
                current.processingStatus = .failed
                try? modelContext.save()
                return
            }
        }
    }

    private func observation(id: UUID) -> ReefObservation? {
        let all = (try? modelContext.fetch(FetchDescriptor<ReefObservation>())) ?? []
        return all.first { $0.id == id }
    }
}
