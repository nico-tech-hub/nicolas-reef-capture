import XCTest
@testable import ReefCapture

/// tests for the ReefCaptureAPI, using XCTest
@MainActor
final class ReefCaptureAPITests: XCTestCase {

    /// TEST 1 - test that the photo upload JSON maps to the upload response
    func testMapsPhotoUploadJSONToUploadResponse() throws {
        let json = """
        {"photoId":"photo-1","jobId":"job-1","status":"PROCESSING"}
        """.data(using: .utf8)!

        let response = try PhotoAPIMapper.uploadResponse(from: json)

        XCTAssertEqual(response.serverId, "photo-1")
        XCTAssertEqual(response.jobId, "job-1")
    }

    /// TEST 2 - test that the job JSON maps to the job status
    func testMapsJobJSONToJobStatus() throws {
        let json = """
        {"jobId":"job-1","photoId":"photo-1","status":"COMPLETED","classification":"healthy_coral","confidence":0.92}
        """.data(using: .utf8)!

        let job = try PhotoAPIMapper.jobStatus(from: json)

        XCTAssertEqual(job.jobId, "job-1")
        XCTAssertEqual(job.status, "COMPLETED")
        XCTAssertEqual(job.classification, "healthy_coral")
        XCTAssertEqual(job.confidence, 0.92)
    }
}
