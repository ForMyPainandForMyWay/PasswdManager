import LocalAuthentication
import Foundation
import os

enum AuthError: Error {
    case unavailable
    case cancelled
    case failed
    case notAuthenticated
}

enum AuthScope: Sendable {
    case viewSecret
    case destructive

    var sessionDuration: TimeInterval {
        switch self {
        case .viewSecret: return 300
        case .destructive: return 0
        }
    }
}

protocol AuthService: Sendable {
    func authenticate(reason: String, scope: AuthScope) async throws
    func canAuthenticate() -> Bool
    func invalidateSession(scope: AuthScope)
    func invalidateAllSessions()
    var isSessionValid: Bool { get }
}

final class LAAuthService: AuthService, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: SessionState())

    private struct SessionState {
        var viewSecretExpiry: Date?
        var destructiveExpiry: Date?
    }

    var isSessionValid: Bool {
        state.withLock { $0.viewSecretExpiry.map { Date() < $0 } ?? false }
    }

    func registerSuccessfulAuthentication(scope: AuthScope) {
        let newExpiry = scope.sessionDuration > 0
            ? Date().addingTimeInterval(scope.sessionDuration)
            : nil
        state.withLock {
            switch scope {
            case .viewSecret: $0.viewSecretExpiry = newExpiry
            case .destructive: $0.destructiveExpiry = newExpiry
            }
        }
    }

    func canAuthenticate() -> Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func authenticate(reason: String, scope: AuthScope = .viewSecret) async throws {
        let expiry: Date? = state.withLock {
            switch scope {
            case .viewSecret: return $0.viewSecretExpiry
            case .destructive: return $0.destructiveExpiry
            }
        }

        if let exp = expiry, Date() < exp { return }

        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            throw AuthError.unavailable
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            if success {
                registerSuccessfulAuthentication(scope: scope)
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

    func invalidateSession(scope: AuthScope) {
        state.withLock {
            switch scope {
            case .viewSecret: $0.viewSecretExpiry = nil
            case .destructive: $0.destructiveExpiry = nil
            }
        }
    }

    func invalidateAllSessions() {
        state.withLock {
            $0.viewSecretExpiry = nil
            $0.destructiveExpiry = nil
        }
    }
}
