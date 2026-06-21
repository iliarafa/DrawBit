import Foundation

/// The read-only palettes that ship with the app. Single source of truth for their colors —
/// the picker no longer hardcodes DB32. Ids are stable hardcoded UUIDs so a user's selected
/// palette survives relaunch.
enum BuiltInPalettes {
    static let all: [ColorPalette] = [db32, pico8, sweetie16, gameBoy]

    static let db32 = ColorPalette(
        id: UUID(uuidString: "0B17A1D0-0000-4000-A000-000000000001")!,
        name: "DB32",
        colors: [
            "000000", "222034", "45283C", "663931", "8F563B", "DF7126", "D9A066", "EEC39A",
            "FBF236", "99E550", "6ABE30", "37946E", "4B692F", "524B24", "323C39", "3F3F74",
            "306082", "5B6EE1", "639BFF", "5FCDE4", "CBDBFC", "FFFFFF", "9BADB7", "847E87",
            "696A6A", "595652", "76428A", "AC3232", "D95763", "D77BBA", "8F974A", "8A6F30",
        ]
    )

    static let pico8 = ColorPalette(
        id: UUID(uuidString: "0B17A1D0-0000-4000-A000-000000000002")!,
        name: "PICO-8",
        colors: [
            "000000", "1D2B53", "7E2553", "008751", "AB5236", "5F574F", "C2C3C7", "FFF1E8",
            "FF004D", "FFA300", "FFEC27", "00E436", "29ADFF", "83769C", "FF77A8", "FFCCAA",
        ]
    )

    static let sweetie16 = ColorPalette(
        id: UUID(uuidString: "0B17A1D0-0000-4000-A000-000000000003")!,
        name: "SWEETIE 16",
        colors: [
            "1A1C2C", "5D275D", "B13E53", "EF7D57", "FFCD75", "A7F070", "38B764", "257179",
            "29366F", "3B5DC9", "41A6F6", "73EFF7", "F4F4F4", "94B0C2", "566C86", "333C57",
        ]
    )

    static let gameBoy = ColorPalette(
        id: UUID(uuidString: "0B17A1D0-0000-4000-A000-000000000004")!,
        name: "GAME BOY",
        colors: ["0F380F", "306230", "8BAC0F", "9BBC0F"]
    )
}
