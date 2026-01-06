import SwiftUI

// MARK: - Environment Key for Refresh Issue Details

struct RefreshIssueDetailsKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var refreshIssueDetails: () -> Void {
        get { self[RefreshIssueDetailsKey.self] }
        set { self[RefreshIssueDetailsKey.self] = newValue }
    }
}
