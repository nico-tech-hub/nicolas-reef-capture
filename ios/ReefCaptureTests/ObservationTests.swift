import XCTest  // provides the XCTest framework for the tests
import SwiftData // provides the SwiftData framework for the tests
@testable import ReefCapture // provides the ReefCapture framework for the tests

/// tests for the Observation model, using SwiftData
final class ObservationTests: XCTestCase { 

    /// TEST 1 - test that the observation starts as pending
    func testObservationStartsAsPending() {

        let observation = Observation() // create the observation

        XCTAssertEqual(observation.uploadStatus, .pending)          // check that the observation starts as pending
        XCTAssertEqual(observation.processingStatus, .none)         // check that the processing status is none
        XCTAssertEqual(observation.retryCount, 0)                   // check that the retry count is 0
        XCTAssertNil(observation.jobId)                             // check that the job id is nil
        XCTAssertNil(observation.serverId)                          // check that the server id is nil
        XCTAssertEqual(observation.version, 1)                      // check that the version is 1
        XCTAssertEqual(observation.displayStatus, "PENDING")        // check that the display status is PENDING
    }

    /// TEST 2 - test that the observation persists in memory store
    func testObservationPersistsInMemoryStore() throws {

        let schema = Schema([Observation.self])    // the base schema only contains the Observation model
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true) // the configuration is stored in RAM memory only
        let container = try ModelContainer(for: schema, configurations: [configuration]) // create the container
        let context = ModelContext(container) // create the context, to read and write to the container

        let observation = Observation() // create the observation
        context.insert(observation) // insert the observation into the context
        try context.save() // save the observation to the context

        let results = try context.fetch(FetchDescriptor<Observation>()) // fetch the observation from the context

        XCTAssertEqual(results.count, 1) // check that the results count is 1
        XCTAssertEqual(results.first?.uploadStatus, .pending) // check that the upload status is pending
        XCTAssertEqual(results.first?.displayStatus, "PENDING") // check that the display status is PENDING
    }
}
