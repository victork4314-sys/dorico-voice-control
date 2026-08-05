#if os(macOS)
import Foundation
import Speech
import AVFoundation
import DoricoVoiceCore

@MainActor
enum PermissionDisplayState: String, Sendable {
    case notDetermined = "Not requested"
    case granted = "Granted"
    case denied = "Denied"
    case restricted = "Restricted"
    case unavailable = "Unavailable"
}

@MainActor
enum VoiceEnginePhase: String, Sendable {
    case idle = "Ready"
    case requestingPermissions = "Requesting permissions"
    case starting = "Starting microphone"
    case listening = "Listening"
    case finalizing = "Finalizing"
    case executing = "Sending commands to Dorico"
    case stopped = "Stopped"
    case failed = "Needs attention"
}

struct DiagnosticEntry: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var timestamp = Date()
    var category: String
    var message: String
}

struct AppPreferences: Codable, Hashable, Sendable {
    var autoExecuteHighConfidencePlans = false
    var localeIdentifier = "en-US"
    var calibration = DoricoVoiceCalibrationProfile()
    var aliases = DoricoVoiceAliasBook()
}

extension PermissionDisplayState {
    init(speech status: SFSpeechRecognizerAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized: self = .granted
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .unavailable
        }
    }

    init(microphone status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized: self = .granted
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .unavailable
        }
    }
}
#endif
