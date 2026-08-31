import XCTest
import UIKit
@testable import ReefCapture

final class PhotoStoreTests: XCTestCase {
    private var directory: URL!
    private var store: PhotoStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        store = PhotoStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSaveWritesFileAndReturnsPath() throws {
        let id = UUID()
        let data = makeJPEGData()
        let path = try store.save(data, id: id)

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), data)
        XCTAssertTrue(path.hasSuffix("\(id.uuidString).jpg"))
    }

    func testSavedObservationStaysPendingWithLocalPath() throws {
        let id = UUID()
        let path = try store.save(makeJPEGData(), id: id)
        let observation = Observation(id: id, localFilePath: path)

        XCTAssertEqual(observation.localFilePath, path)
        XCTAssertEqual(observation.uploadStatus, .pending)
        XCTAssertEqual(observation.displayStatus, "PENDING")
        XCTAssertNotNil(store.loadImage(at: path))
    }

    func testJpegDataConvertsRenderableImage() {
        let raw = makeJPEGData()
        let converted = store.jpegData(from: raw)

        XCTAssertNotNil(converted)
        XCTAssertNotNil(UIImage(data: converted!))
    }

    private func makeJPEGData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return image.jpegData(compressionQuality: 1)!
    }
}
