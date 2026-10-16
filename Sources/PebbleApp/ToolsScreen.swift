// The creative Tools menu (the tools key, G by default, or the toolbox
// button on touch screens): the tool items, every /place structure, every
// creature and the edit commands, without typing. Each entry runs its chat
// command (ToolCatalog), and what that command prints shows at the bottom.

import Foundation
import QuartzCore
import PebbleCore

final class ToolsScreen: Screen {
    /// the tab and structure layout the menu opens on next (remembered)
    static var lastTab = ToolTab.tools
    static var layout = 0
    private static let LAYOUTS = 10

    private var tab = ToolsScreen.lastTab
    private var entries: [ToolEntry] = []
    private var scroll = 0
    private var px = 0.0, py = 0.0, pw = 0.0, ph = 0.0
    private var listX = 0.0, listY = 0.0, listW = 0.0
    private var cols = 2, rowH = 14.0, visibleRows = 1
    /// when the last entry ran (chat-clock ms): what it printed since shows below
    private var ranAt: Double?

    override init() {
        super.init()
        touchScrolls = true
    }

    private var cellW: Double { ((listW - Double(cols - 1) * 2) / Double(cols)).rounded(.down) }
    private var totalRows: Int { (entries.count + cols - 1) / cols }
    private var maxScroll: Int { max(0, totalRows - visibleRows) }

    override func initScreen(_ ui: UIManager, _ game: GameCore) {
        pw = min(ui.width - 12, 330).rounded(.down)
        ph = min(ui.height - 12, 220).rounded(.down)
        px = ((ui.width - pw) / 2).rounded(.down)
        py = ((ui.height - ph) / 2).rounded(.down)
        rowH = ui.touchMode ? 18 : 14
        listX = px + 8
        listY = py + 38
        listW = pw - 16 - 12
        cols = listW >= 280 ? 3 : 2
        visibleRows = max(1, Int((ph - 82) / rowH))
        entries = toolEntries(tab, layout: ToolsScreen.layout)
        scroll = min(scroll, maxScroll)

        let tabs = ToolTab.allCases
        let tw = ((pw - 16 - Double(tabs.count - 1) * 2) / Double(tabs.count)).rounded(.down)
        for (i, t) in tabs.enumerated() {
            buttons.append(Button(px + 8 + Double(i) * (tw + 2), py + 18, tw, 16,
                                  t == tab ? "§e\(t.title)" : t.title, { [weak self, weak ui, weak game] in
                guard let self, let ui, let game, t != self.tab else { return }
                self.tab = t
                ToolsScreen.lastTab = t
                self.scroll = 0
                self.ranAt = nil
                self.relayout(ui, game)
            }))
        }
        let fy = py + ph - 20
        if tab == .structures {
            // the same structure, laid out differently (/place's variant number)
            func step(_ d: Int) -> () -> Void {
                { [weak self, weak ui, weak game] in
                    guard let self, let ui, let game else { return }
                    ToolsScreen.layout = (ToolsScreen.layout + d + Self.LAYOUTS) % Self.LAYOUTS
                    self.relayout(ui, game)
                }
            }
            buttons.append(Button(px + 8, fy, 16, 16, "<", step(-1)))
            buttons.append(Button(px + 26, fy, 70, 16, "Layout \(ToolsScreen.layout + 1)", step(1)))
            buttons.append(Button(px + 98, fy, 16, 16, ">", step(1)))
        }
        buttons.append(Button(px + pw - 68, fy, 60, 16, "Done", { [weak ui, weak game] in
            guard let ui, let game else { return }
            ui.closeTop(game)
        }))
    }

    private func relayout(_ ui: UIManager, _ game: GameCore) {
        buttons.removeAll()
        initScreen(ui, game)
    }

    /// the entry under a point in the list
    private func entryAt(_ mx: Double, _ my: Double) -> Int? {
        guard mx >= listX, mx < listX + listW, my >= listY, my < listY + Double(visibleRows) * rowH else { return nil }
        let col = Int((mx - listX) / (cellW + 2)), row = Int((my - listY) / rowH)
        guard col < cols, mx < listX + Double(col) * (cellW + 2) + cellW else { return nil }
        let i = (scroll + row) * cols + col
        return i < entries.count ? i : nil
    }

    private func run(_ e: ToolEntry, _ game: GameCore) {
        ranAt = CACurrentMediaTime() * 1000
        runCommand(game, e.command)
        // a tool goes in your hand when it lands on the hotbar
        if let name = e.icon, tab == .tools, let id = iidOpt(name), let p = game.player,
           let slot = (0..<9).first(where: { p.inventory[$0]?.id == id }) {
            p.selectedSlot = slot
        }
    }

    override func onMouseDown(_ ui: UIManager, _ game: GameCore, _ mx: Double, _ my: Double, _ btn: Int) -> Bool {
        if super.onMouseDown(ui, game, mx, my, btn) { return true }
        guard let i = entryAt(mx, my) else { return false }
        game.playUISound("ui.button.click")
        run(entries[i], game)
        return true
    }

    override func onWheel(_ ui: UIManager, _ game: GameCore, _ dy: Double) -> Bool {
        scroll = max(0, min(maxScroll, scroll + (dy > 0 ? 1 : -1)))
        return true
    }

    override func onKey(_ ui: UIManager, _ game: GameCore, _ key: String) -> Bool {
        // the key that opened it closes it again
        if key == game.keybinds["tools"] {
            ui.closeTop(game)
            if !ui.hasScreen() { gRuntime?.input.captureMouse() }
            return true
        }
        return super.onKey(ui, game, key)
    }

    /// `s` cut to fit `w` units, with ".." when it doesn't
    private func fit(_ s: String, _ w: Double) -> String {
        if Double(textWidth(s)) <= w { return s }
        var t = s
        while !t.isEmpty && Double(textWidth(t + "..")) > w { t.removeLast() }
        return t + ".."
    }

    /// what the last entry printed (its last line), or a hint for the tab
    private func status(_ ui: UIManager) -> String {
        if let t = ranAt, let m = chatLog.last(where: { $0.time >= t }) { return m.text }
        let tap = ui.touchMode ? "Tap" : "Click"
        switch tab {
        case .tools: return "§7\(tap) a tool to put it in your hand"
        case .structures: return "§7Lands in front of you. Undo is on the Edit tab"
        case .creatures: return "§7They appear in front of you, facing you"
        case .edit: return "§7Mark a box with the Selection Wand or the corners, then copy"
        }
    }

    private func drawScrollBar(_ ui: UIManager) {
        let cv = ui.cv
        let barX = px + pw - 16, barH = Double(visibleRows) * rowH - 1
        cv.setFill("#1c1c1c")
        cv.fillRect(barX, listY, 8, barH)
        let knobH = max(10, (barH * Double(visibleRows) / Double(totalRows)).rounded())
        let kf = Double(scroll) / Double(maxScroll)
        let ky = listY + ((barH - knobH) * kf).rounded()
        cv.setFill("#9a9a9a")
        cv.fillRect(barX, ky, 8, knobH)
        cv.setFill("#d8d8d8")
        cv.fillRect(barX, ky, 8, 1)
    }

    override func draw(_ ui: UIManager, _ game: GameCore) {
        ui.drawDarkBg(0.45)
        let cv = ui.cv
        ui.drawPanel(px, py, pw, ph)
        cv.drawText("Creative Tools", px + 8, py + 6, 1, "#3f3f3f", shadow: false)
        if let key = game.keybinds["tools"], key.hasPrefix("Key") {
            let hint = "Key: \(key.dropFirst(3))"
            cv.drawText(hint, px + pw - 8 - Double(textWidth(hint)), py + 6, 1, "#6f6f6f", shadow: false)
        }
        let hovered = ui.touchMode ? nil : entryAt(ui.mouseX, ui.mouseY)
        let cw = cellW
        for row in 0..<visibleRows {
            for col in 0..<cols {
                let i = (scroll + row) * cols + col
                guard i < entries.count else { break }
                let e = entries[i]
                let x = listX + Double(col) * (cw + 2), y = listY + Double(row) * rowH
                cv.setFill(i == hovered ? "#7a8cbf" : "#6f6f6f")
                cv.fillRect(x, y, cw, rowH - 1)
                cv.setFill(i == hovered ? "#aab8e0" : "#8b8b8b")
                cv.fillRect(x, y, cw, 1)
                var tx = x + 4
                if let name = e.icon, let id = iidOpt(name) {
                    let s = rowH >= 18 ? 16.0 : 12.0
                    cv.drawItemIcon(id, nil, x + 2, y + ((rowH - 1 - s) / 2).rounded(.down), s, s)
                    tx = x + s + 5
                }
                cv.drawText(fit(e.title, x + cw - 3 - tx), tx, y + ((rowH - 9) / 2).rounded(.down), 1)
                if i == hovered {
                    ui.tooltipLines = [e.title] + (e.detail.map { ["§7" + $0] } ?? []) + ["§8" + e.command]
                    ui.tooltipAvoid = (x, y, cw, rowH)
                }
            }
        }
        // scroll bar, when there's more than fits
        if maxScroll > 0 { drawScrollBar(ui) }
        // what happened, two lines at most, on a dark strip so chat's
        // colours read; a wrapped line keeps the colour it started with
        cv.setFill("#2a2a2a")
        cv.fillRect(px + 6, py + ph - 43, pw - 12, 21)
        let text = status(ui)
        let lead = text.hasPrefix("§") ? String(text.prefix(2)) : ""
        for (j, l) in wrapText(text, Int(pw - 16)).prefix(2).enumerated() {
            cv.drawText(j > 0 && !l.hasPrefix("§") ? lead + l : l, px + 8, py + ph - 41 + Double(j) * 10, 1)
        }
        ui.drawButtons(self)
    }
}
