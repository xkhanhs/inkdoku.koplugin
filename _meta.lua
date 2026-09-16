local _ = require("gettext")

-- Tên plugin do KOReader lấy từ tên thư mục (sudoku.koplugin → "sudoku"),
-- không đặt `name` ở đây: pluginloader bỏ qua và ghi cảnh báo.
return {
    fullname = _("Sudoku"),
    description = _([[Sudoku của xkhanhs/sudoku, bản cho máy đọc sách e-ink.]]),
    version = "1.0.0",
}
