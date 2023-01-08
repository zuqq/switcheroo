import XCTest
import func switcheroo.decodeConfigurationFile
import struct switcheroo.Configuration
import struct switcheroo.ConfigurationEntry
import struct switcheroo.DeviceSelector
import struct switcheroo.Overrides
import struct switcheroo.Rules

final class switcherooTests: XCTestCase {
    func testConfiguration() throws {
        let configuration = """
{
    "entries": [
        {
            "selector": "HHKB-Classic",
            "rules": {
                "input_source": "com.apple.keylayout.US",
                "natural_scroll": false
            }
        }
    ]
}
"""
        let actual = try switcheroo.decodeConfigurationFile(configuration.data(using: .utf8)!)
        let expected = Configuration(
            entries: [
                ConfigurationEntry(
                    selector: DeviceSelector(value: "HHKB-Classic"),
                    rules: Rules(
                        inputSource: "com.apple.keylayout.US",
                        naturalScroll: false
                    )
                )
            ]
        )
        XCTAssertEqual(actual, expected)
    }

    func testConfigurationInputSourceOnly() throws {
        let configuration = """
{
    "entries": [
        {
            "selector": "HHKB-Classic",
            "rules": {
                "input_source": "com.apple.keylayout.US"
            }
        }
    ]
}
"""
        let actual = try switcheroo.decodeConfigurationFile(configuration.data(using: .utf8)!)
        let expected = Configuration(
            entries: [
                ConfigurationEntry(
                    selector: DeviceSelector(value: "HHKB-Classic"),
                    rules: Rules(
                        inputSource: "com.apple.keylayout.US",
                        naturalScroll: nil
                    )
                )
            ]
        )
        XCTAssertEqual(actual, expected)
    }

    func testConfigurationNaturalScrollOnly() throws {
        let configuration = """
{
    "entries": [
        {
            "selector": "HHKB-Classic",
            "rules": {
                "natural_scroll": false
            }
        }
    ]
}
"""
        let actual = try switcheroo.decodeConfigurationFile(configuration.data(using: .utf8)!)
        let expected = Configuration(
            entries: [
                ConfigurationEntry(
                    selector: DeviceSelector(value: "HHKB-Classic"),
                    rules: Rules(
                        inputSource: nil,
                        naturalScroll: false
                    )
                )
            ]
        )
        XCTAssertEqual(actual, expected)
    }

    func testConfigurationMultipleRules() throws {
        let configuration = """
{
    "entries": [
        {
            "selector": "HHKB-Classic",
            "rules": {
                "input_source": "com.apple.keylayout.US"
            }
        },
        {
            "selector": "SteelSeries Rival 3",
            "rules": {
                "natural_scroll": false
            }
        }
    ]
}
"""
        let actual = try switcheroo.decodeConfigurationFile(configuration.data(using: .utf8)!)
        let expected = Configuration(
            entries: [
                ConfigurationEntry(
                    selector: DeviceSelector(value: "HHKB-Classic"),
                    rules: Rules(
                        inputSource: "com.apple.keylayout.US",
                        naturalScroll: nil
                    )
                ),
                ConfigurationEntry(
                    selector: DeviceSelector(value: "SteelSeries Rival 3"),
                    rules: Rules(
                        inputSource: nil,
                        naturalScroll: false
                    )
                ),
            ]
        )
        XCTAssertEqual(actual, expected)
    }

    func testOverrides() throws {
        let configuration = Configuration(
            entries: [
                ConfigurationEntry(
                    selector: DeviceSelector(value: "HHKB-Classic"),
                    rules: Rules(
                        inputSource: "com.apple.keylayout.US",
                        naturalScroll: false
                    )
                )
            ]
        )
        var overrides = Overrides(configuration)
        XCTAssertEqual(overrides.getInputSource(), nil)
        XCTAssertEqual(overrides.getNaturalScroll(), nil)
        overrides.addDevice("HHKB-Classic")
        XCTAssertEqual(overrides.getInputSource(), "com.apple.keylayout.US")
        XCTAssertEqual(overrides.getNaturalScroll(), false)
        overrides.removeDevice("HHKB-Classic")
        XCTAssertEqual(overrides.getInputSource(), nil)
        XCTAssertEqual(overrides.getNaturalScroll(), nil)
    }
}
