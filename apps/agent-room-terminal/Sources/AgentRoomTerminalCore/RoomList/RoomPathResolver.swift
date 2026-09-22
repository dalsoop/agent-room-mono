import Foundation

public enum RoomPathResolver {
    public static func resolveRoomURL(
        roomID: String,
        tenant: String,
        environment: [String: String],
        homeDirectory: String
    ) -> URL {
        if let existing = RoomPaths.findRoomDirectory(
            roomID: roomID,
            tenant: tenant,
            environment: environment,
            homeDirectory: homeDirectory
        ) {
            return existing
        }
        return RoomPaths.roomDirectory(
            tenant: tenant,
            roomID: roomID,
            environment: environment,
            homeDirectory: homeDirectory
        )
    }
}
