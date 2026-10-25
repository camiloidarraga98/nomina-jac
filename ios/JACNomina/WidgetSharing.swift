import Foundation

/// The main app alone reads JAC's authenticated API. The widget receives only
/// the small, protected snapshot prepared after these responses are authorised.
struct WidgetRecentPhoto: Decodable, Sendable {
    let id: String
    let name: String
    let mimeType: String
    let kind: String
    let size: Int64
    let modifiedAt: String
    let thumbnailAvailable: Bool
    let createdAt: String?
    let parentId: String

    var mediaItem: MediaItem {
        MediaItem(id: id, name: name, mimeType: mimeType, kind: kind, size: size,
                  modifiedAt: modifiedAt, thumbnailAvailable: thumbnailAvailable,
                  createdAt: createdAt)
    }
}
struct WidgetRecentPhotos: Decodable, Sendable {
    let items: [WidgetRecentPhoto]
    let collectionID: String
}
