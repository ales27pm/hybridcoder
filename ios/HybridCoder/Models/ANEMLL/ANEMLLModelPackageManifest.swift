import Foundation

struct ANEMLLModelPackageManifest: Codable, Sendable {
    let formatVersion: Int
    let modelName: String
    let modelId: String?
    let modelRootPath: String?
    let minAppVersion: String?
    let files: [ANEMLLModelPackageFileEntry]
}

struct ANEMLLModelPackageFileEntry: Codable, Sendable {
    let path: String
    let sha256: String
    let sizeBytes: Int64?
}
