import XCTest
import SwiftData
@testable import ReefCapture

/// Scripted API for tests. Value type so `PhotoUploading: Sendable` does not see a mutable class field.
struct ScriptedPhotoAPI: PhotoUploading {
    private final class Storage: @unchecked Sendable {
        var stubs: [Result<UploadResponse, Error>]
        init(_ stubs: [Result<UploadResponse, Error>]) {
            self.stubs = stubs
        }
    }

    private let storage: Storage
    private let jobStatus: String

    /// create a function to initialize the scripted photo API
    init(_ stubs: Result<UploadResponse, Error>..., jobStatus: String = "COMPLETED") {
        self.storage = Storage(Array(stubs))
        self.jobStatus = jobStatus
    }

    /// create a function to upload the photo
    func uploadPhoto(filePath: String, idempotencyKey: UUID) async throws -> UploadResponse {
        guard !storage.stubs.isEmpty else {
            throw UploadError.network
        }
        return try storage.stubs.removeFirst().get()
    }

    func fetchJobStatus(jobId: String) async throws -> JobStatus {
        JobStatus(jobId: jobId, status: jobStatus, classification: "healthy_coral", confidence: 0.92)
    }

    func deletePhoto(serverId: String) async throws {}
}

/// tests for the UploadQueue, using XCTest
@MainActor
final class UploadQueueTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

/// create a function to set up the test
    override func setUpWithError() throws {
        let schema = Schema([ReefObservation.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
    }

    /// TEST 1 - test that the queue processes a pending observation
    func testQueueProcessesPendingObservation() async throws {
        let observation = ReefObservation(localFilePath: "/tmp/coral.jpg")
        context.insert(observation)

        let api = FakePhotoAPI(delayNanoseconds: 0)
        let queue = UploadQueue(modelContext: context, api: api, pollIntervalNanoseconds: 1_000)

        await queue.processPending()
        await queue.waitForPolling()

        XCTAssertEqual(observation.uploadStatus, .uploaded)
        XCTAssertEqual(observation.processingStatus, .completed)
        XCTAssertEqual(observation.displayStatus, "COMPLETED")
        XCTAssertNotNil(observation.serverId)
        XCTAssertNotNil(observation.jobId)
        XCTAssertEqual(observation.retryCount, 0)
    }

    /// TEST 2 - test that the queue marks processing before job completes
    func testQueueMarksProcessingBeforeJobCompletes() async throws {
        let observation = ReefObservation(localFilePath: "/tmp/coral.jpg")
        context.insert(observation)

        let api = ScriptedPhotoAPI(
            .success(UploadResponse(serverId: "srv-ok", jobId: "job-ok")),
            jobStatus: "PROCESSING"
        )
        let queue = UploadQueue(modelContext: context, api: api, pollIntervalNanoseconds: 1_000)

        await queue.processPending()
        await queue.waitForPolling()

        XCTAssertEqual(observation.uploadStatus, .uploaded)
        XCTAssertEqual(observation.processingStatus, .processing)
        XCTAssertEqual(observation.displayStatus, "PROCESSING")
        XCTAssertEqual(observation.jobId, "job-ok")
    }

    /// TEST 3 - test that a failed upload can be retried without duplicating
    func testFailedUploadCanBeRetriedWithoutDuplicating() async throws {
        let observation = ReefObservation(localFilePath: "/tmp/coral.jpg")
        let originalKey = observation.idempotencyKey
        context.insert(observation)

        let api = ScriptedPhotoAPI(
            .failure(UploadError.network),
            .success(UploadResponse(serverId: "srv-ok", jobId: "job-ok"))
        )
        let queue = UploadQueue(modelContext: context, api: api, pollIntervalNanoseconds: 1_000)

        await queue.processPending()

        XCTAssertEqual(observation.uploadStatus, .failed)
        XCTAssertEqual(observation.retryCount, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReefObservation>()).count, 1)

        await queue.retry(observation)
        await queue.waitForPolling()

        XCTAssertEqual(observation.uploadStatus, .uploaded)
        XCTAssertEqual(observation.serverId, "srv-ok")
        XCTAssertEqual(observation.jobId, "job-ok")
        XCTAssertEqual(observation.processingStatus, .completed)
        XCTAssertEqual(observation.idempotencyKey, originalKey)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ReefObservation>()).count, 1)
    }

    /// TEST 4 - test that an interrupted upload is recovered and then uploaded
    func testInterruptedUploadingIsRecoveredThenUploaded() async throws {
        let observation = ReefObservation(localFilePath: "/tmp/coral.jpg")
        observation.uploadStatus = .uploading
        context.insert(observation)

        let api = FakePhotoAPI(delayNanoseconds: 0)
        let queue = UploadQueue(modelContext: context, api: api, pollIntervalNanoseconds: 1_000)

        await queue.start()
        await queue.waitForPolling()

        XCTAssertEqual(observation.uploadStatus, .uploaded)
        XCTAssertEqual(observation.processingStatus, .completed)
        XCTAssertNotNil(observation.serverId)
        XCTAssertNotNil(observation.jobId)
    }
}
