public enum NotificationRule {
    public static func shouldNotifyHuman(for event: Event) -> Bool {
        switch event.type {
        case .handoffAssignedToHuman, .handoffBlocked, .humanReplyRequested, .serviceFailure:
            return true
        default:
            return false
        }
    }
}
