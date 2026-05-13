import AppKit
import Foundation
@preconcurrency import Dispatch
import os

final class ClipboardCleaner: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: CleanerState())

    private struct CleanerState: @unchecked Sendable {
        var workItem: DispatchWorkItem?
    }

    func copyToClipboard(_ text: String, clearAfter seconds: TimeInterval = 30) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let workItem = DispatchWorkItem {
            let current = pasteboard.string(forType: .string)
            if current == text {
                pasteboard.clearContents()
            }
        }

        state.withLock {
            $0.workItem?.cancel()
            $0.workItem = workItem
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: workItem)
    }
}