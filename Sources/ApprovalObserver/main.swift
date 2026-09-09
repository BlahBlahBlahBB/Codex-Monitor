import CodexMonitorContracts
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let paths: AppOwnedApprovalObserverPaths
if arguments.count == 2, arguments[0] == "--approval-observer-root" {
    paths = AppOwnedApprovalObserverPaths(rootURL: URL(fileURLWithPath: arguments[1], isDirectory: true))
} else {
    paths = .default
}
ApprovalObserverHookRunner.run(paths: paths)
