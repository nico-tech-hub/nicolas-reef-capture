import XCTest  // provides the XCTest framework for the tests
import SwiftData // provides the SwiftData framework for the tests
@testable import ReefCapture // provides the ReefCapture framework for the tests

/// tests for the Observation model, using SwiftData
@MainActor
final class ObservationTests: XCTestCase { 

    /// TEST 1 - test that the observation starts as pending
    func testObservationStartsAsPending() {

        let observation = ReefObservation() // create the observation

        XCTAssertEqual(observation.uploadStatus, .pending)          // check that the observation starts as pending
        XCTAssertEqual(observation.processingStatus, .none)         // check that the processing status is none
        XCTAssertEqual(observation.retryCount, 0)                   // check that the retry count is 0
        XCTAssertNil(observation.jobId)                             // check that the job id is nil
        XCTAssertNil(observation.serverId)                          // check that the server id is nil
        XCTAssertEqual(observation.version, 1)                      // check that the version is 1
        XCTAssertEqual(observation.displayStatus, "PENDING")        // check that the display status is PENDING
    }

    /// TEST 1b - displayStatus is derived from upload + processing
    func testDisplayStatusFollowsUploadAndProcessing() {
        let observation = ReefObservation()

        observation.uploadStatus = .uploading
        XCTAssertEqual(observation.displayStatus, "UPLOADING")

        observation.uploadStatus = .uploaded
        observation.processingStatus = .processing
        observation.jobId = "job-1"
        XCTAssertEqual(observation.displayStatus, "PROCESSING")

        observation.processingStatus = .completed
        XCTAssertEqual(observation.displayStatus, "COMPLETED")
    }

    /// TEST 2 - test that the observation persists in memory store
    func testObservationPersistsInMemoryStore() throws {

        let schema = Schema([ReefObservation.self])    // the base schema only contains the ReefObservation model
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true) // the configuration is stored in RAM memory only
        let container = try ModelContainer(for: schema, configurations: [configuration]) // create the container
        let context = ModelContext(container) // create the context, to read and write to the container

        let observation = ReefObservation() // create the observation
        context.insert(observation) // insert the observation into the context
        try context.save() // save the observation to the context

        let results = try context.fetch(FetchDescriptor<ReefObservation>()) // fetch the observation from the context

        XCTAssertEqual(results.count, 1) // check that the results count is 1
        XCTAssertEqual(results.first?.uploadStatus, .pending) // check that the upload status is pending
        XCTAssertEqual(results.first?.displayStatus, "PENDING") // check that the display status is PENDING
    }

    /// TEST 3 - deleting a local-only observation removes the SwiftData row
    func testDeletingLocalObservationRemovesSwiftDataRow() throws {
        let schema = Schema([ReefObservation.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let observation = ReefObservation(localFilePath: "/tmp/coral.jpg")
        context.insert(observation)
        try context.save()

        context.delete(observation)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<ReefObservation>()).count, 0)
    }
}
