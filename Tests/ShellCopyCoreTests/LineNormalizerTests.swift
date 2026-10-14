import XCTest
@testable import ShellCopyCore

final class LineNormalizerTests: XCTestCase {
    func testListWrapsPreserveHeadingsItemsAndBlankLines() {
        let first = "  • **KR1：**完善资产生产进度披露，优先覆盖数据集、指标创建及回溯链路，试点范围内关键生产节点可视覆盖率达"
        let second = "  • **KR2：**完善 Agent 长任务执行与恢复能力，核心故障回归用例全部通过，验证任务状态可追踪、重复请"
        let third = "  • **KR3：**建立创编与 Oncall 场景的效果评测和发布回归机制，沉淀不少于 50 条真实需求，核心 Skill 与"
        let input = "O1：目标\r\n" + first + "\r\n    到 100%。\r\n" + second + "\r\n    求不重复创建。\r\n\r\nO2：目标\r\n\r\n" + third + "\r\n\t\t    模型配置变更均完成回归验收。"
        let expected = "O1：目标\r\n" + first + "到 100%。\r\n" + second + "求不重复创建。\r\n\r\nO2：目标\r\n\r\n" + third + "模型配置变更均完成回归验收。"
        XCTAssertEqual(LineNormalizer.normalize(input), expected)
        XCTAssertEqual(LineNormalizer.normalize(expected), expected)
    }

    func testAlignedEnglishAndNumberedListWraps() {
        for marker in ["• ", "- ", "* ", "+ ", "1. ", "12) ", "a) "] {
            let first = "  " + marker + "This detailed deployment report explains the remaining work for the next"
            let input = first + "\n" + String(repeating: " ", count: 2 + marker.count) + "release."
            XCTAssertEqual(LineNormalizer.normalize(input), first + " release.")
        }
    }

    func testListChildrenCodeAndIntentionalBreaksStaySeparate() {
        let first = "  • This detailed deployment report explains the remaining work for the next"
        for next in ["    - nested item", "      nested paragraph", "    echo do not join", "    const value = 1", "    # Heading", "    column\tvalue", "\t    English tab indentation", "  Another paragraph."] {
            let input = first + "\n" + next
            XCTAssertEqual(LineNormalizer.normalize(input), input)
        }
        let ended = first + ".\n    Separate sentence."
        XCTAssertEqual(LineNormalizer.normalize(ended), ended)
    }

    func testReportedChineseProseWithTwoSpaceWrapBecomesOneLine() {
        let first = "直接执行：已修复并重新打包。请退出旧版，再打开新版 Shell Copy (build/Shell Copy.app)，即可使用"
        let next = "Command-V 粘贴、Command-A 全选。"
        XCTAssertEqual(LineNormalizer.normalize(first + "\n  " + next), first + next)
    }

    func testShallowIndentContinuationAndSentenceBoundaries() {
        let first = "This detailed deployment report explains the remaining work for the next"
        for indent in [2, 4, 8, 32] {
            let padding = String(repeating: " ", count: indent)
            XCTAssertEqual(LineNormalizer.normalize(first + "\n" + padding + "release."), first + " release.")
            let separate = first + ".\n" + padding + "A separate sentence."
            XCTAssertEqual(LineNormalizer.normalize(separate), separate)
        }
    }

    func testOriginalUserExampleKeepsColumnSpacing() {
        let first = "useDag=0 直接物化 Hive    临时升级环境下通过，存在交付限制。 7377/429330 成功 11 人；7378/429331 Hive 成功后因 COUNT=0 失败。但依赖临时 Base64 模板和测试 JAR，验收后恢复了原模板，不能算永久启用"
        XCTAssertEqual(LineNormalizer.normalize(first + "\n" + String(repeating: " ", count: 32) + "完成。"), first + "完成。")
    }

    func testIndependentChineseContinuationAndMultipleLines() {
        let first = "batchMode=2 新版本校验    本轮抽样结果符合预期，后续仍需完成配置迁移以及历史数据"
        let input = first + "\n                核对，等待负责人确认后\n                统一发布。"
        XCTAssertEqual(LineNormalizer.normalize(input), first + "核对，等待负责人确认后统一发布。")
    }

    func testEnglishWordBoundariesAndInternalSpaces() {
        let first = "The migration report    explains why the updated service still requires additional"
        XCTAssertEqual(LineNormalizer.normalize(first + "\n        checks before the release can proceed."), first + " checks before the release can proceed.")
    }

    func testBlankParagraphsAndCRLFRemainExact() {
        let first = "This detailed deployment report explains the remaining work for the next"
        let input = first + "\r\n        release.\r\n  \r\nA short separate paragraph.\r\n"
        XCTAssertEqual(LineNormalizer.normalize(input), first + " release.\r\n  \r\nA short separate paragraph.\r\n")
    }

    func testListsCodeCommandsLogsAndIndentationArePreserved() {
        let samples = [
            "- This detailed deployment report explains the remaining work for the next\n        release.",
            "1. This detailed deployment report explains the remaining work for the next\n        release.",
            "This detailed deployment report explains the remaining work for the next\n        - release item",
            "```text\nThis detailed deployment report explains the remaining work for the next\n        release.\n\n```",
            "~~~python\nprint('a')\n~~~",
            "def explain_the_changes_in_this_detailed_report_for_release():\n        return result",
            "const explanation = this function needs enough words to look like prose\n        + continuation;",
            "curl https://example.test/a/very/long/path --header 'Accept: application/json' \\\n        --output response.json",
            "echo this shell command contains enough ordinary words to resemble a paragraph\n        and must remain untouched",
            "INFO This detailed deployment report explains the remaining work for the next\n        release.",
            "2026-10-08 10:12:13 This detailed deployment report explains the remaining work\n        for the next release.",
            "description: This detailed deployment report explains the remaining work for the next\n        release.",
            "    This detailed deployment report explains the remaining work for the next\n        release.",
            "This detailed deployment report explains the remaining work for the next\n\trelease.",
            "This detailed deployment report explains the remaining work for the next\n        release\n          with nested indentation",
            "KEY=value OTHER=value\n        unchanged"
        ]
        for sample in samples { XCTAssertEqual(LineNormalizer.normalize(sample), sample, sample) }
    }

    func testAmbiguousOrShortTextIsUnchanged() {
        let samples = [
            "one\n        two", "标题\n        说明。", "", "one line", "a\r\nb\r\n",
            "This detailed deployment report explains the remaining work for the next\nrelease.",
            "This detailed deployment report explains the remaining work for the next.\n        Separate sentence.",
            "This detailed deployment report explains the remaining work for the next\n release.",
            "This detailed deployment report explains the remaining work for the next-\n        release.",
            "This detailed deployment report explains the remaining work for the next\n        release.\0"
        ]
        for sample in samples { XCTAssertEqual(LineNormalizer.normalize(sample), sample) }
    }

    func testIdempotence() {
        let sample = "This detailed deployment report explains the remaining work for the next\n        release.\n\n这一份迁移检查报告说明了本次上线之前必须进一步确认的历史数据\n        校验结果。"
        let result = LineNormalizer.normalize(sample)
        XCTAssertNotEqual(result, sample)
        XCTAssertEqual(LineNormalizer.normalize(result), result)
    }
}
