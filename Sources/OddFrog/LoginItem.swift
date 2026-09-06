import Foundation
import ServiceManagement

enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static func toggle() throws {
        switch status {
        case .enabled:
            try SMAppService.mainApp.unregister()
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        default:
            try SMAppService.mainApp.register()
        }
    }
}
