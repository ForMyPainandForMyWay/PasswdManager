import LocalAuthentication
import Foundation
import os

enum AuthError: Error {
    case unavailable
    case cancelled
    case failed
    case notAuthenticated
}

protocol AuthService: Sendable {
    func authenticate(reason: String) async throws
    func canAuthenticate() -> Bool
    func invalidateSession()
    var isSessionValid: Bool { get }
}

final class LAAuthService: AuthService, @unchecked Sendable {
    private let context: LAContext
    private let sessionDuration: TimeInterval
    private let state = OSAllocatedUnfairLock(initialState: SessionState())

    private struct SessionState {
        var expiry: Date?
    }

    init(sessionDuration: TimeInterval = 300) {
        self.context = LAContext()
        self.sessionDuration = sessionDuration
    }

    var isSessionValid: Bool {
        state.withLock { $0.expiry.map { Date() < $0 } ?? false }
    }

    func canAuthenticate() -> Bool {
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func authenticate(reason: String) async throws {
        if isSessionValid { return }

        guard canAuthenticate() else {
            throw AuthError.unavailable
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            if success {
                state.withLock { $0.expiry = Date().addingTimeInterval(sessionDuration) }
            } else {
                throw AuthError.failed
            }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .systemCancel, .appCancel:
                throw AuthError.cancelled
            default:
                throw AuthError.failed
            }
        } catch {
            throw AuthError.failed
        }
    }

    func invalidateSession() {
        state.withLock { $0.expiry = nil }
        context.invalidate()
    }
}