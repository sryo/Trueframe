/// What VoiceOver hears at the edges of a session, when the screen shows next to nothing.
enum SessionAnnouncements {
    static let capturing = "capturing"

    static func kept(_ count: Int) -> String {
        switch count {
        case 0: "nothing kept"
        case 1: "1 photo kept"
        default: "\(count) photos kept"
        }
    }
}
