enum CaptureMode: Int, CaseIterable, Identifiable {
    case voiceProcessingIO = 1

    var id: Int { rawValue }

    var title: String { "VoiceProcessingIO" }

    var usesVoiceProcessing: Bool { true }
}
