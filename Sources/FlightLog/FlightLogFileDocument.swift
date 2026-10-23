import SwiftUI
import UniformTypeIdentifiers

struct FlightLogFileDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.commaSeparatedText, .json]
    }

    static var writableContentTypes: [UTType] {
        [.commaSeparatedText, .json]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard
            let data = configuration.file.regularFileContents,
            !data.isEmpty
        else {
            throw BackupServiceError.emptyFile
        }
        self.data = data
    }

    func fileWrapper(
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        guard !data.isEmpty else {
            throw BackupServiceError.fileWriteFailed("没有可写入的内容。")
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
