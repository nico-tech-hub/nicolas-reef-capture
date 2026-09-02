import XCTest
import UIKit
@testable import ReefCapture

/// tests for the PhotoStore, using FileManager
@MainActor
final class PhotoStoreTests: XCTestCase {
    private var directory: URL!
    private var store: PhotoStore!

    /// create a variable to store the directory
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = PhotoStore(directory: directory)
    }

    /// create a function to tear down the test
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// TEST 1 - test that the photo store writes a file and returns the path
    func testSaveWritesFileAndReturnsPath() throws {
        let id = UUID()
        let data = makeJPEGData()
        let path = try store.save(data, id: id)

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), data)
        XCTAssertTrue(path.hasSuffix("\(id.uuidString).jpg"))
    }

    /// TEST 2 - test that the saved observation stays pending with the local path
    func testSavedObservationStaysPendingWithLocalPath() throws {
        let id = UUID()
        let path = try store.save(makeJPEGData(), id: id)
        let observation = ReefObservation(id: id, localFilePath: path)

        XCTAssertEqual(observation.localFilePath, path)
        XCTAssertEqual(observation.uploadStatus, .pending)
        XCTAssertEqual(observation.displayStatus, "PENDING")
        XCTAssertNotNil(store.loadImage(at: path))
    }

    /// TEST 3 - test that the delete removes the local file
    func testDeleteRemovesLocalFile() throws {
        let path = try store.save(makeJPEGData(), id: UUID())
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))

        store.delete(at: path)

        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    /// TEST 4 - test that the jpeg data converts to a renderable image
    func testJpegDataConvertsRenderableImage() {
        let raw = makeJPEGData()
        let converted = store.jpegData(from: raw)

        XCTAssertNotNil(converted)
        XCTAssertNotNil(UIImage(data: converted!))
    }

    /// create a function to make jpeg data
    private func makeJPEGData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return image.jpegData(compressionQuality: 1)!
    }
}
