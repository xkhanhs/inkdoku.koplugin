local _ = require("gettext")

-- Tên plugin do KOReader lấy từ tên thư mục (inkdoku.koplugin → "inkdoku"),
-- không đặt `name` ở đây: pluginloader bỏ qua và ghi cảnh báo.
return {
    fullname = _("Sudoku"),
    description = _([[Sudoku for e-ink readers: unique-solution puzzles, 6 difficulty levels, autosave.]]),
    version = "1.1.0",
}
