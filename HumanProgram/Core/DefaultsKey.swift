import Foundation

/// Single source of truth for every `UserDefaults` / `@AppStorage` key in the app.
///
/// Before this existed, the same key strings ("settings.fontChoice", "hp.lock.timeout",
/// "selectedCalendarIds", …) were typed by hand in ~10 files — and the .hprgm export,
/// the .hprgm import, and Factory Reset each re-listed them independently. A typo or a
/// forgotten key in one of those lists silently broke backup, restore, or reset with no
/// compile error. Keeping the raw strings here makes that impossible to get wrong.
///
/// IMPORTANT: never change a raw string value — it is the on-disk key for a user's saved
/// preference. Changing it would orphan that preference (the app would read the default
/// instead of the user's choice). Only ADD new keys.
enum DefaultsKey {

    // MARK: User preferences (these ARE carried in .hprgm backups)

    static let fontChoice          = "settings.fontChoice"
    static let fontSizeStep        = "settings.fontSizeStep"
    static let appearanceMode      = "settings.appearanceMode"
    static let appIcon             = "settings.appIcon"
    static let bgLight             = "settings.bgLight"
    static let bgDark              = "settings.bgDark"
    static let dateFormat          = "settings.dateFormat"
    static let timeFormat          = "settings.timeFormat"
    static let a11yButtonBorders   = "settings.a11yButtonBorders"
    static let selectedCalendarIds = "selectedCalendarIds"

    // MARK: App state (NOT carried in .hprgm backups)

    static let onboarded           = "hp.onboarded"
    static let permissionsAsked    = "hp.permissionsAsked"
    static let lockEnabled         = "hp.lock.enabled"
    static let lockBiometric       = "hp.lock.biometric"
    static let lockTimeout         = "hp.lock.timeout"
    static let backlogViewMode     = "hp.backlog.viewMode"   // persisted Task/Project view
    static let backlogTaskSort     = "hp.backlog.taskSort"   // persisted backlog sort

    // MARK: Shared color-preset library

    static let blockColorPresets   = "blockColorPresets"

    // MARK: Key groups

    /// The user-preference keys carried in .hprgm backups (font, sizes, appearance,
    /// icon, backgrounds, date/time format, accessibility borders, selected calendars).
    static let userPreferenceKeys: [String] = [
        fontChoice, fontSizeStep, appearanceMode, appIcon, bgLight, bgDark,
        dateFormat, timeFormat, a11yButtonBorders, selectedCalendarIds
    ]

    /// Every app-managed key. Factory Reset clears this whole list so a reset returns the
    /// app to a clean factory state — not just the lock/onboarding keys. [#11]
    static let allKeys: [String] = userPreferenceKeys + [
        onboarded, permissionsAsked, lockEnabled, lockBiometric, lockTimeout,
        blockColorPresets, backlogViewMode, backlogTaskSort
    ]
}
