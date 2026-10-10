import Foundation
import Testing
@testable import ExitFinder

@MainActor
struct LocalizationTests {
    private func localizedBundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    private func strings(_ table: String, in bundle: Bundle) throws -> [String: String] {
        let url = try #require(bundle.url(forResource: table, withExtension: "strings"))
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(plist as? [String: String])
    }

    @Test func englishAndJapaneseContainTheSameNonemptyKeys() throws {
        let english = try strings("Localizable", in: localizedBundle("en"))
        let japanese = try strings("Localizable", in: localizedBundle("ja"))
        #expect(english.count == 47)
        #expect(Set(english.keys) == Set(japanese.keys))
        for (key, value) in english {
            #expect(!value.isEmpty)
            #expect(japanese[key]?.isEmpty == false)
        }
    }

    @Test func primaryUIResolvesInBothLanguages() throws {
        let english = try localizedBundle("en")
        let japanese = try localizedBundle("ja")
        #expect(L10n.text("search.here", bundle: english) == "Search here")
        #expect(L10n.text("search.here", bundle: japanese) == "この場所で検索")
        #expect(L10n.text("loading.exits", bundle: english) == "Looking for exits...")
        #expect(L10n.text("loading.exits", bundle: japanese) == "出口を探しています...")
        #expect(L10n.text("error.fetch", bundle: english) == "Could not load data. Please check your connection.")
        #expect(L10n.text("error.fetch", bundle: japanese) == "データの取得に失敗しました。通信状況を確認してください。")
    }

    @Test func numberedExitsRetainTheirExactIdentifiers() throws {
        let english = try localizedBundle("en")
        let japanese = try localizedBundle("ja")
        for reference in ["1", "A5b", "B12", "03"] {
            #expect(L10n.exitLabel(reference, bundle: english) == "Exit \(reference)")
            #expect(L10n.exitLabel(reference, bundle: japanese) == "\(reference)番出口")
        }
    }

    @Test func namedJapaneseExitsStayUnchangedForSignMatching() throws {
        for language in ["en", "ja"] {
            let bundle = try localizedBundle(language)
            for reference in ["八重洲北口", "電気街改札", "A1（東口）"] {
                #expect(L10n.exitLabel(reference, bundle: bundle) == reference)
            }
        }
    }

    @Test func formattedLabelsKeepJapaneseOutput() throws {
        let english = try localizedBundle("en")
        let japanese = try localizedBundle("ja")
        #expect(L10n.format("walk.minutes", [5], bundle: english) == "5 min")
        #expect(L10n.format("walk.minutes", [5], bundle: japanese) == "5分")
        #expect(L10n.format("walk.hours_minutes", [1, 5], bundle: english) == "1 hr 5 min")
        #expect(L10n.format("walk.hours_minutes", [1, 5], bundle: japanese) == "1時間5分")
        #expect(L10n.format("app.version", ["2.2"], bundle: japanese) == "駅出口マップ 2.2")
    }

    @Test func permissionAndDisplayNameResourcesAreLocalized() throws {
        let english = try strings("InfoPlist", in: localizedBundle("en"))
        let japanese = try strings("InfoPlist", in: localizedBundle("ja"))
        #expect(Set(english.keys) == Set(japanese.keys))
        #expect(english["CFBundleDisplayName"] == "Station Exit Map")
        #expect(japanese["CFBundleDisplayName"] == "駅出口マップ")
        #expect(english["NSLocationWhenInUseUsageDescription"] == "Your location is used to find nearby station exits.")
        #expect(japanese["NSLocationWhenInUseUsageDescription"] == "近くの駅出口を探すために現在地を使用します")
    }
}
