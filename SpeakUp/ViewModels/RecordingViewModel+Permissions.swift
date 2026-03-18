import Foundation

extension RecordingViewModel {
    // MARK: - Permissions

    func checkPermissions() async {
        hasAudioPermission = await audioService.requestPermission()

        if !hasAudioPermission {
            permissionAlertMessage = "Microphone access is required to record audio."
            showingPermissionAlert = true
        }
    }
}
