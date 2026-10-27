import Foundation

/// User-editable settings persisted as JSON. Keys are PascalCase so a file from the Windows launcher reads as-is.
public struct LauncherSettings: Codable, Equatable, Sendable {
    /// Hotkey text in the form understood by `HotkeySpec.tryParse`.
    public var hotkey: String = HotkeySpec.default.description

    /// Extra chords that open the launcher alongside `hotkey`, in the same form. Defaults to right Option + Return
    /// so a file that still names an older hotkey (e.g. "Cmd+Shift+Space") gets both. Set to `[]` to register only `hotkey`.
    public var additionalHotkeys: [String] = Self.defaultAdditionalHotkeys

    public static let defaultAdditionalHotkeys: [String] = [HotkeySpec.default.description]

    /// Register the app as a login item (SMAppService) on start. Only works when running from an .app bundle.
    public var startAtLogin: Bool = false

    /// Index Desktop, Documents, Downloads, Pictures, Movies, Music and the home folder.
    public var includeKnownFolders: Bool = true

    /// Auto-detect and index iCloud Drive, Google Drive, Dropbox, OneDrive and other CloudStorage providers.
    public var includeCloudDrives: Bool = true

    /// Extra folders to index on top of the detected ones. "~" and $VARIABLES are expanded.
    public var folderRoots: [String] = []

    /// How many levels below each root to index. 0 indexes only the roots themselves.
    public var folderScanDepth: Int = FolderScanner.defaultMaxDepth

    /// Switch the keyboard to an English layout when the launcher opens, and back when it hides.
    public var forceEnglishInput: Bool = true

    public init(
        hotkey: String = HotkeySpec.default.description,
        additionalHotkeys: [String] = LauncherSettings.defaultAdditionalHotkeys,
        startAtLogin: Bool = false,
        includeKnownFolders: Bool = true,
        includeCloudDrives: Bool = true,
        folderRoots: [String] = [],
        folderScanDepth: Int = FolderScanner.defaultMaxDepth,
        forceEnglishInput: Bool = true
    ) {
        self.hotkey = hotkey
        self.additionalHotkeys = additionalHotkeys
        self.startAtLogin = startAtLogin
        self.includeKnownFolders = includeKnownFolders
        self.includeCloudDrives = includeCloudDrives
        self.folderRoots = folderRoots
        self.folderScanDepth = folderScanDepth
        self.forceEnglishInput = forceEnglishInput
    }

    public var hotkeyOrDefault: HotkeySpec {
        HotkeySpec.tryParse(hotkey) ?? HotkeySpec.default
    }

    /// Every chord to register: `hotkeyOrDefault` first, then each parseable entry of `additionalHotkeys`,
    /// in order and without duplicates. Unparseable entries are skipped.
    public var hotkeySpecs: [HotkeySpec] {
        var specs = [hotkeyOrDefault]
        for text in additionalHotkeys {
            if let spec = HotkeySpec.tryParse(text), !specs.contains(spec) {
                specs.append(spec)
            }
        }
        return specs
    }

    private enum CodingKeys: String, CodingKey {
        case hotkey = "Hotkey"
        case additionalHotkeys = "AdditionalHotkeys"
        case startAtLogin = "StartAtLogin"
        case startWithWindows = "StartWithWindows"
        case includeKnownFolders = "IncludeKnownFolders"
        case includeCloudDrives = "IncludeCloudDrives"
        case folderRoots = "FolderRoots"
        case folderScanDepth = "FolderScanDepth"
        case forceEnglishInput = "ForceEnglishInput"
    }

    /// Every key is optional so an older or hand-edited file keeps its defaults for what it omits.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = try container.decodeIfPresent(String.self, forKey: .hotkey) ?? HotkeySpec.default.description
        additionalHotkeys = try container.decodeIfPresent([String].self, forKey: .additionalHotkeys) ?? Self.defaultAdditionalHotkeys
        startAtLogin = try container.decodeIfPresent(Bool.self, forKey: .startAtLogin)
            ?? container.decodeIfPresent(Bool.self, forKey: .startWithWindows)
            ?? false
        includeKnownFolders = try container.decodeIfPresent(Bool.self, forKey: .includeKnownFolders) ?? true
        includeCloudDrives = try container.decodeIfPresent(Bool.self, forKey: .includeCloudDrives) ?? true
        folderRoots = try container.decodeIfPresent([String].self, forKey: .folderRoots) ?? []
        folderScanDepth = try container.decodeIfPresent(Int.self, forKey: .folderScanDepth) ?? FolderScanner.defaultMaxDepth
        forceEnglishInput = try container.decodeIfPresent(Bool.self, forKey: .forceEnglishInput) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hotkey, forKey: .hotkey)
        try container.encode(additionalHotkeys, forKey: .additionalHotkeys)
        try container.encode(startAtLogin, forKey: .startAtLogin)
        try container.encode(includeKnownFolders, forKey: .includeKnownFolders)
        try container.encode(includeCloudDrives, forKey: .includeCloudDrives)
        try container.encode(folderRoots, forKey: .folderRoots)
        try container.encode(folderScanDepth, forKey: .folderScanDepth)
        try container.encode(forceEnglishInput, forKey: .forceEnglishInput)
    }
}
