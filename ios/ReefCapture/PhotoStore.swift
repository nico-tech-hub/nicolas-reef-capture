import Foundation // for Foundation types like String, Int, etc.
import UIKit // for UIKit types like UIView, UIViewController, etc.

/// Copies picked photos into the app sandbox.
/// The Photos library identifier is NOT the source of truth — our file is.
struct PhotoStore {
    let directory: URL

    /// initializes the photo store with a directory
    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// the live photo store is the photo store for the app, using the documents directory
    static var live: PhotoStore {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return PhotoStore(directory: documents.appendingPathComponent("observations", isDirectory: true))
    }

    /// saves the data to the directory
    func save(_ data: Data, id: UUID) throws -> String {
        let url = directory.appendingPathComponent("\(id.uuidString).jpg")
        try data.write(to: url, options: .atomic)
        return url.path
    }

    /// loads the image from the path from the directory
    func loadImage(at path: String) -> UIImage? {
        UIImage(contentsOfFile: path)
    }

    /// converts the raw image data to jpeg data
    func jpegData(from rawImageData: Data, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: rawImageData) else { return nil }
        return image.jpegData(compressionQuality: quality)
    }
}
