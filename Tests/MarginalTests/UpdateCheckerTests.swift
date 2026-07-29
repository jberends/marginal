import XCTest
@testable import Marginal

final class UpdateCheckerTests: XCTestCase {

    func testNewerVersionsCompareAsNewer() {
        XCTAssertTrue(UpdateChecker.isVersion("0.2.0", newerThan: "0.1.0"))
        XCTAssertTrue(UpdateChecker.isVersion("1.0.0", newerThan: "0.9.9"))
        XCTAssertTrue(UpdateChecker.isVersion("0.10.0", newerThan: "0.9.1"), "Segments compare numerically, not lexically")
        XCTAssertTrue(UpdateChecker.isVersion("1.0.1", newerThan: "1.0"), "A missing segment counts as zero")
    }

    func testEqualAndOlderVersionsDoNotCompareAsNewer() {
        XCTAssertFalse(UpdateChecker.isVersion("0.1.0", newerThan: "0.1.0"))
        XCTAssertFalse(UpdateChecker.isVersion("1.0", newerThan: "1.0.0"), "Trailing zero segments are equal")
        XCTAssertFalse(UpdateChecker.isVersion("0.9.9", newerThan: "1.0.0"))
    }

    func testReleaseDecodingStripsTagPrefix() throws {
        let json = Data("""
        {"tag_name": "v0.1.0", "html_url": "https://github.com/jberends/marginal/releases/tag/v0.1.0"}
        """.utf8)
        let release = try JSONDecoder().decode(UpdateChecker.Release.self, from: json)
        XCTAssertEqual(release.version, "0.1.0")
        XCTAssertNil(release.appZipAsset)
    }

    func testReleaseDecodingFindsAppZipAsset() throws {
        let json = Data("""
        {"tag_name": "v0.2.0", "html_url": "x", "assets": [
            {"name": "notes.txt", "browser_download_url": "https://example.com/notes.txt"},
            {"name": "Marginal-0.2.0.zip", "browser_download_url": "https://example.com/Marginal-0.2.0.zip"}
        ]}
        """.utf8)
        let release = try JSONDecoder().decode(UpdateChecker.Release.self, from: json)
        XCTAssertEqual(release.appZipAsset?.name, "Marginal-0.2.0.zip")
    }
}

/// The self-update script runs in Terminal, outside the sandbox, so its behavior can't be
/// exercised from this sandboxed test host (spawning zsh here is denied). Behavior is
/// verified by running the script standalone against a dummy bundle; these tests pin the
/// structure and ordering that verification relied on.
final class UpdateInstallerScriptTests: XCTestCase {

    @MainActor
    func testUpdateScriptStructure() {
        let script = UpdateInstaller.scriptContents(
            appPath: "/Applications/Marginal.app",
            zipPath: "/tmp/Marginal-0.2.0.zip",
            pid: 12345
        )
        XCTAssertTrue(script.hasPrefix("#!/bin/zsh\nset -e"), "Fail fast on any step")
        XCTAssertTrue(script.contains("while kill -0 12345"), "Waits for the running app to exit first")
        XCTAssertTrue(script.contains(#"ditto -x -k "/tmp/Marginal-0.2.0.zip""#), "Extracts the downloaded zip")
        XCTAssertTrue(script.contains(#"rm -rf "/Applications/Marginal.app""#), "Removes the old bundle")
        XCTAssertTrue(script.contains("xattr -dr com.apple.quarantine"), "Clears quarantine so Gatekeeper allows the relaunch")
        XCTAssertTrue(script.contains(#"open "/Applications/Marginal.app""#), "Relaunches the updated app")
        XCTAssertTrue(script.contains(#"rm -- "$0""#), "The script deletes itself")

        // Ordering: wait -> extract -> swap -> relaunch.
        let wait = script.range(of: "while kill -0")!.lowerBound
        let extract = script.range(of: "ditto -x -k")!.lowerBound
        let swap = script.range(of: "rm -rf \"/Applications")!.lowerBound
        let relaunch = script.range(of: "open \"/Applications")!.lowerBound
        XCTAssertTrue(wait < extract && extract < swap && swap < relaunch)
    }
}

final class PDFExporterHTMLTests: XCTestCase {

    @MainActor
    func testPageHTMLContainsRenderedBodyAndEscapedTitle() {
        let html = PDFExporter.pageHTML(markdown: "# Hi\n\nSome **bold** text.", title: "a<b & c")
        XCTAssertTrue(html.contains("<h1>Hi</h1>"))
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
        XCTAssertTrue(html.contains("<title>a&lt;b &amp; c</title>"))
    }
}
