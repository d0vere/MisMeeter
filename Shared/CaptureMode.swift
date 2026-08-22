enum CaptureMode: Int, CaseIterable, Identifiable {
    case remoteIORaw = 0
    case voiceProcessingIO = 1

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .remoteIORaw:
            return "RemoteIO Raw"
        case .voiceProcessingIO:
            return "VoiceProcessingIO"
        }
    }

    var usesVoiceProcessing: Bool {
        self == .voiceProcessingIO
    }
}
