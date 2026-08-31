import XCTest
import SwiftData
@testable import ReefCapture

final class ScriptedPhotoAPI: PhotoUploading {
    private var stubs: [Result<UploadResponse, Error>]

    init(_ stubs: Result<UploadResponse, Error>...) {
        self.stubs = Array(stubs)
    }

    func uploadPhoto(filePath: String, idempotencyKey: UUID) async throws -> UploadResponse {
        guard !stubs.isEmpty else {
            throw UploadError.network
        }
        return try stubs.removeFirst().get()
    }
}

@MainActor
final class UploadQueueTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Observation.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
    }

    func testQueueProcessesPendingObservation() async throws {
        let observation = Observation(localFilePath: "/tmp/coral.jpg")
        context.insert(observation)

        let api = FakePhotoAPI(delayNanoseconds: 0)
        let queue = UploadQueue(modelContext: context, api: api)

        await queue.processPending()

        XCTAssertEqual(observation.uploadStatus, .uploaded)
        XCTAssertEqual(observation.displayStatus, "UPLOADED")
        XCTAssertNotNil(observation.serverId)
        XCTAssertEqual(observation.retryCount, 0)
    }

    func testFailedUploadCanBeRetriedWithoutDuplicating() async throws {
        let observation = Observation(localFilePath: "/tmp/coral.jpg")
        let originalKey = observation.idempotencyKey
        context.insert(observation)

        let api = ScriptedPhotoAPI(
            .failure(UploadError.network),
            .success(UploadResponse(serverId: "srv-ok", jobId: nil))
        )
        let queue = UploadQueue(modelContext: context, api: api)

        await queue.processPending()

        XCTAssertEqual(observation.uploadStatus, .failed)
        XCTAssertEqual(observation.retryCount, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Observation>()).count, 1)

        await queue.retry(observation)

        XCTAssertEqual(observation.uploadStatus, .uploaded)
        XCTAssertEqual(observation.serverId, "srv-ok")
        XCTAssertEqual(observation.idempotencyKey, originalKey)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Observation>()).count, 1)
    }

    func testInterruptedUploadingIsRecoveredThenUploaded() async throws {
        let observation = Observation(localFilePath: "/tmp/coral.jpg")
        observation.uploadStatus = .uploading
        context.insert(observation)

        let api = FakePhotoAPI(delayNanoseconds: 0)
        let queue = UploadQueue(modelContext: context, api: api)

        await queue.start()

        XCTAssertEqual(observation.uploadStatus, .uploaded)
        XCTAssertNotNil(observation.serverId)
    }
}
