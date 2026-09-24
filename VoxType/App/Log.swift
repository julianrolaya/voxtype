import os

enum Log {
    private static let subsystem = "com.voxtype.app"

    static let app           = Logger(subsystem: subsystem, category: "app")
    static let audio         = Logger(subsystem: subsystem, category: "audio")
    static let transcription = Logger(subsystem: subsystem, category: "transcription")
    static let insertion     = Logger(subsystem: subsystem, category: "insertion")
    static let hotkey        = Logger(subsystem: subsystem, category: "hotkey")
    static let storage       = Logger(subsystem: subsystem, category: "storage")
    static let ui            = Logger(subsystem: subsystem, category: "ui")
}
