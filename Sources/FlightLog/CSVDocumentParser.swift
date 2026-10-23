import Foundation

struct CSVParsedRow: Equatable, Sendable {
    let lineNumber: Int
    let fields: [String]
}

enum CSVDocumentParser {
    static func parse(
        _ data: Data,
        limits: BackupLimits = .standard
    ) throws -> [CSVParsedRow] {
        guard !data.isEmpty else {
            throw BackupServiceError.emptyFile
        }
        guard data.count <= limits.maximumFileSize else {
            throw BackupServiceError.fileTooLarge(
                maximum: limits.maximumFileSize
            )
        }
        guard var text = String(data: data, encoding: .utf8) else {
            throw BackupServiceError.invalidUTF8
        }
        if text.first == "\u{FEFF}" {
            text.removeFirst()
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackupServiceError.emptyFile
        }

        text = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        enum State {
            case unquoted
            case quoted
            case afterClosingQuote
        }

        var state = State.unquoted
        var rows: [CSVParsedRow] = []
        var fields: [String] = []
        var field = ""
        var fieldLength = 0
        var lineNumber = 1
        var rowStartLine = 1
        var rowHasSyntax = false

        func appendToField(_ character: Character) throws {
            fieldLength += 1
            guard fieldLength <= limits.maximumFieldLength else {
                throw BackupServiceError.fieldTooLong(
                    line: rowStartLine,
                    maximum: limits.maximumFieldLength
                )
            }
            field.append(character)
        }

        func finishField() {
            fields.append(field)
            field = ""
            fieldLength = 0
        }

        func finishRow() throws {
            finishField()
            rows.append(
                CSVParsedRow(
                    lineNumber: rowStartLine,
                    fields: fields
                )
            )
            guard rows.count <= limits.maximumRowCount else {
                throw BackupServiceError.tooManyRows(
                    maximum: limits.maximumRowCount
                )
            }
            fields.removeAll(keepingCapacity: true)
            rowHasSyntax = false
        }

        for (offset, character) in text.enumerated() {
            if offset.isMultiple(of: 1_024) {
                try Task.checkCancellation()
            }
            switch state {
            case .unquoted:
                switch character {
                case "\"":
                    guard field.isEmpty else {
                        throw BackupServiceError.malformedCSV(
                            line: lineNumber,
                            reason: "未加引号的字段中出现了引号。"
                        )
                    }
                    state = .quoted
                    rowHasSyntax = true
                case ",":
                    finishField()
                    rowHasSyntax = true
                case "\n":
                    try finishRow()
                    lineNumber += 1
                    rowStartLine = lineNumber
                default:
                    try appendToField(character)
                    rowHasSyntax = true
                }

            case .quoted:
                if character == "\"" {
                    state = .afterClosingQuote
                } else {
                    try appendToField(character)
                    if character == "\n" {
                        lineNumber += 1
                    }
                }

            case .afterClosingQuote:
                switch character {
                case "\"":
                    try appendToField("\"")
                    state = .quoted
                case ",":
                    finishField()
                    state = .unquoted
                case "\n":
                    try finishRow()
                    state = .unquoted
                    lineNumber += 1
                    rowStartLine = lineNumber
                case " ", "\t":
                    // Horizontal whitespace between a closing quote and the
                    // delimiter is accepted for interoperability.
                    continue
                default:
                    throw BackupServiceError.malformedCSV(
                        line: lineNumber,
                        reason: "结束引号后出现了无效字符。"
                    )
                }
            }
        }

        guard state != .quoted else {
            throw BackupServiceError.malformedCSV(
                line: rowStartLine,
                reason: "字段引号未闭合。"
            )
        }

        if rowHasSyntax || !fields.isEmpty || !field.isEmpty {
            try finishRow()
        }
        return rows
    }
}
