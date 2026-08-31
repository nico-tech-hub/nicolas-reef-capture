import XCTest
@testable import ReefCapture

final class ReefCaptureAPITests: XCTestCase {
    func testMapsPhotoUploadJSONToUploadResponse() throws {
        let json = """
        {"photoId":"photo-1","jobId":null,"status":"UPLOADED"}
        """.data(using: .utf8)!

        let response = try PhotoAPIMapper.uploadResponse(from: json)

        XCTAssertEqual(response.serverId, "photo-1")
        XCTAssertNil(response.jobId)
    }
}
