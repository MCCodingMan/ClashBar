import Foundation
import XCTest
@testable import ClashBar

final class ConfigImportServiceTests: XCTestCase {
    func testImportAcceptsJSONAndYAMLAndPreservesExistingConfigOnRejection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let targetURL = directory.appendingPathComponent("subscription.yaml")
        let service = ConfigImportService()
        let validConfigs = [
            """
            {
              "mode": "rule",
              "proxies": [{"name": "示例节点", "type": "hysteria2", "server": "example.com",
                           "port": 443, "password": "example"}]
            }
            """,
            #"{"proxies":[]}"#,
            #"{"proxy-groups":[{"name":"Proxy","type":"select","proxies":["DIRECT"]}]}"#,
            #"{"proxy-providers":{"example":{"type":"file","path":"./proxies.yaml"}}}"#,
            """
            {
              "mode": "rule",
              "proxies": [{"name": "Example #1", "type": "hysteria2", "server": "example.com",
                           "port": 443, "password": "#example"}]
            }
            # synthetic-subscription-marker
            """,
            "# header\r\n{\"proxies\":[]}\r\n  # footer\r\n",
            "# header\r{\"proxies\":[]}\r# footer\r",
            "{\"proxies\":[],\"description\":\"first\u{2028}#second\u{2029}#third\u{0085}#last\"}\n# footer",
            #"{"proxies":[],"description":"first line\n#still inside the string"}"#,
            "mode: rule\nproxies: []\n",
            "proxy-groups: []\n",
            "proxy-providers: {}\n",
            "proxy-providers:\n  example:\n    type: http\n    url: https://example.com/proxies.yaml\n",
            "proxy-groups:\n  - {name: Proxy, type: select, proxies: [DIRECT]}\n",
            "base: &base\n  type: select\n  proxies: [DIRECT]\nproxy-groups:\n  - <<: *base\n    name: Proxy\n",
        ]

        for config in validConfigs {
            let data = Data(config.utf8)
            XCTAssertTrue(try service.writeConfigData(data, to: targetURL))
            XCTAssertEqual(try Data(contentsOf: targetURL), data)
            XCTAssertFalse(try service.writeConfigData(data, to: targetURL))
        }

        let original = try Data(contentsOf: targetURL)
        let invalidConfigs = [
            "",
            "<html>Subscription unavailable</html>",
            #"{"message":"Subscription unavailable"}"#,
            #"{"data":{"proxies":[]}}"#,
            #"[{"proxies":[]}]"#,
            #"{"proxies":null,"proxy-groups":{},"proxy-providers":[]}"#,
            "# comment only\n",
            "{\"proxies\":[]}\n# comment\nunexpected trailing content",
            "{\"proxies\":[]\n# missing closing brace",
        ]

        for config in invalidConfigs {
            XCTAssertThrowsError(try service.writeConfigData(Data(config.utf8), to: targetURL))
            XCTAssertEqual(try Data(contentsOf: targetURL), original)
        }
    }

    func testImportPreservesLegacyMarkerValidation() throws {
        let targetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).yaml")
        defer { try? FileManager.default.removeItem(at: targetURL) }

        // The original validator accepted markers anywhere in UTF-8 content, including JSON strings.
        let data = Data(#"{"description":"proxies: legacy marker","proxies":null}"#.utf8)
        XCTAssertTrue(try ConfigImportService().writeConfigData(data, to: targetURL))
        XCTAssertEqual(try Data(contentsOf: targetURL), data)
    }
}
