import AppKit
import SwiftUI
import OddFrogCore

struct HotkeyRecorderView: NSViewRepresentable {
    let title: String
    let onRecord: (Hotkey) -> Void
    let onRecordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> HotkeyRecorder {
        HotkeyRecorder()
    }

    func updateNSView(_ recorder: HotkeyRecorder, context: Context) {
        recorder.onRecord = onRecord
        recorder.onRecordingChanged = onRecordingChanged
        if recorder.title != title { recorder.title = title }
    }
}
