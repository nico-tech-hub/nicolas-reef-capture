import XCTest
import SwiftData
@testable import ReefCapture

final class ScriptedPhotoAPI: PhotoUploading {
    private var stubs: [Result<UploadResponse, Error>]
    private let jobStatus: String

    init(_ stubs: Result<UploadResponse, Error>..., jobStatus: String = "COMPLETED") {
        self.stubs = Array(stubs)
        self.jobStatus = jobStatus
    }

    func uploadPhoto(filePath: String, idempotencyKey: UUID) async throws -> UploadResponse {
        guard !stubs.isEmpty else {
            throw UploadError.network
        }
        return try stubs.removeFirst().get()
    }

    func fetchJobStatus(jobId: String) async throws -> JobStatus {
        JobStatus(jobId: jobId, status: jobStatus, classification: "healthy_coral", confidence: 0.92)
    }

    func deletePhoto(serverId: String) async throws {}
}

@MainActor
final class UploadQueueTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([ReefObservation.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
    }

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
