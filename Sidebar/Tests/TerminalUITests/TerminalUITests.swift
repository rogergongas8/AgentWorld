import Testing
@testable import TerminalUI

@Suite struct TerminalUITests {
    @Test func halfBlocksComposeTwoPixelsPerCell() {
        var pixels = PixelCanvas(width: 3, height: 2)
        let red = RGB(255, 0, 0), blue = RGB(0, 0, 255)
        pixels[0, 0] = red
        pixels[1, 1] = blue
        pixels[2, 0] = red
        pixels[2, 1] = blue

        var canvas = Canvas(width: 3, height: 1)
        pixels.render(into: &canvas, column: 0, row: 0)
        #expect(canvas[0, 0] == Cell("▀", Style(fg: red)))
        #expect(canvas[1, 0] == Cell("▄", Style(fg: blue)))
        #expect(canvas[2, 0] == Cell("▀", Style(fg: red, bg: blue)))

        var solid = PixelCanvas(width: 1, height: 2)
        solid[0, 0] = red
        solid[0, 1] = red
        solid.render(into: &canvas, column: 0, row: 0)
        #expect(canvas[0, 0] == Cell(" ", Style(bg: red)))
    }

    @Test func pixelCanvasClipsAndRoundsHeight() {
        var pixels = PixelCanvas(width: 2, height: 3)
        #expect(pixels.height == 4)
        pixels[-1, 0] = RGB(1, 1, 1)
        pixels[5, 5] = RGB(1, 1, 1)
        #expect(pixels[-1, 0] == nil)
    }

    @Test func canvasTextClips() {
        var canvas = Canvas(width: 5, height: 1)
        let end = canvas.text("abcdefgh", x: 1, y: 0, maxWidth: 3)
        #expect(end == 4)
        #expect(canvas.row(0).map(\.character) == [" ", "a", "b", "c", " "])
    }

    @Test func fittingAddsEllipsis() {
        #expect("hello".fitted(to: 10) == "hello")
        #expect("hello world".fitted(to: 6) == "hello…")
        #expect("hi".padded(to: 4) == "hi  ")
    }

    @Test func screenOnlyRewritesChangedRows() {
        var output: [String] = []
        let screen = Screen(colorMode: .trueColor) { output.append($0) }
        var canvas = Canvas(width: 4, height: 3)
        canvas.text("ab", x: 0, y: 0)
        screen.present(canvas)
        canvas.text("zz", x: 0, y: 2)
        screen.present(canvas)
        #expect(!output[1].contains(ANSI.moveTo(row: 1, column: 1)))
        #expect(output[1].contains(ANSI.moveTo(row: 3, column: 1)))
    }

    @Test func xterm256Quantization() {
        #expect(RGB(0, 0, 0).xterm256 == 16)
        #expect(RGB(255, 255, 255).xterm256 == 231)
        #expect(RGB(255, 0, 0).xterm256 == 196)
        #expect((232...255).contains(RGB(128, 128, 128).xterm256))
    }

    @Test func keyParsing() {
        #expect(Terminal.parseKeys([0x71, 0x09, 0x1B, 0x5B, 0x41]) == [.character("q"), .tab, .up])
        #expect(Terminal.parseKeys(Array("\u{1B}[5~\u{1B}[6~\u{7F}".utf8)) == [.pageUp, .pageDown, .backspace])
    }

    @Test func mouseParsing() {
        #expect(Terminal.parseKeys(Array("\u{1B}[<0;5;3M".utf8)) == [.mouse(MouseEvent(action: .press, x: 4, y: 2))])
        #expect(Terminal.parseKeys(Array("\u{1B}[<65;1;1M\u{1B}[<0;5;3m".utf8)) == [.mouse(MouseEvent(action: .scrollDown, x: 0, y: 0))])
    }

    @Test func colorModeDetection() {
        #expect(ColorMode.detect(environment: ["COLORTERM": "truecolor"]) == .trueColor)
        #expect(ColorMode.detect(environment: ["TERM": "xterm-256color"]) == .ansi256)
        #expect(ColorMode.detect(environment: ["COLORTERM": "truecolor", "AGENTWORLD_COLOR": "256"]) == .ansi256)
    }
}
