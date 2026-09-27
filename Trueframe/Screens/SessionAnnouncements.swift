/// What VoiceOver hears at the edges of a session, when the screen shows next to nothing.
enum SessionAnnouncements {
    static let capturing = "capturing"

    static func kept(_ count: Int) -> String {
        count == 1 ? "1 photo kept" : "\(count) photos kept"
    }
}
