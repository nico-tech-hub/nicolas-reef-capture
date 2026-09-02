import SwiftUI // for SwiftUI types like View, Text, Button, etc.

/// A row in the list of observations
struct ObservationRow: View {

    let observation: ReefObservation // the observation
    let image: UIImage? // the image
    var onRetry: (() -> Void)? // the action to perform when the retry button is pressed

    /// the body of the view is a horizontal stack with the thumbnail, the id, the status, and the retry button
    var body: some View {
        HStack(spacing: 12) {
            thumbnail // the thumbnail of the observation
            VStack(alignment: .leading, spacing: 4) { // the vertical stack with the id and the status
                Text(shortId(observation.id))
                    .font(.headline)
                Text(statusLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer() // the spacer to push the retry button to the right
            if observation.uploadStatus == .failed { // if the upload status is failed, show the retry button
                Button("Retry") {
                    onRetry?()
                }
            }
        }
        .accessibilityElement(children: .combine)
    } // end of body

    /// the status line is the display status and the retry count if the upload status is failed
    private var statusLine: String {
        if observation.retryCount > 0 {
            return "\(observation.displayStatus) · retry \(observation.retryCount)"
        }
        return observation.displayStatus
    }

    /// the thumbnail is the image of the observation if it exists, otherwise a placeholder
    @ViewBuilder
    private var thumbnail: some View {
        if let image { // if the image exists, show the image
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipped()
                .cornerRadius(8)
        } else { // if the image does not exist, show a placeholder
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 56, height: 56)
                .background(.fill.tertiary)
                .cornerRadius(8)
        }
    }

    /// the short id is the first 8 characters of the uuid string in uppercase
    private func shortId(_ id: UUID) -> String {
        String(id.uuidString.prefix(8)).uppercased()
    }
}
