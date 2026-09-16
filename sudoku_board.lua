-- ==================== BÀN CỜ ====================
-- Dịch từ js/board-render.js. Một widget vẽ cả bàn cờ lên BlitBuffer: nền ô, số,
-- ghi chú, lưới. Chạm vào bàn cờ quy đổi toạ độ ra hàng cột như cellFromPoint().
--
-- Màu web đổi sang mức xám của e-ink. Thay cho sóng loang, hàng/cột/khối vừa xong
-- được đóng khung viền đậm (`frames`), vẽ cùng lần refresh hiện số vừa điền: màn
-- e-ink không chạy được hoạt ảnh, và refresh nhanh chỉ có đen trắng nên làm nháy.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText = require("ui/rendertext")

local Screen = Device.screen

local NUMBER_RATIO = 0.62
local NOTE_RATIO = 0.26
local PLAY_RATIO = 0.22 -- nút play khi tạm dừng, theo cạnh bàn cờ

local COLOR = {
    background = Blitbuffer.COLOR_WHITE,
    error = Blitbuffer.COLOR_BLACK,
    given_text = Blitbuffer.COLOR_BLACK,
    entry_text = Blitbuffer.COLOR_GRAY_5,
    note_text = Blitbuffer.COLOR_GRAY_4,
    light_text = Blitbuffer.COLOR_WHITE,
    selected_border = Blitbuffer.COLOR_BLACK,
    frame = Blitbuffer.COLOR_BLACK,
    thin_line = Blitbuffer.COLOR_GRAY_9,
    thick_line = Blitbuffer.COLOR_BLACK,
}

-- Font:getFace() nhân cỡ chữ theo DPI; ở đây cần đúng số pixel theo cạnh ô
local function faceForPixels(name, pixels)
    local scale = Screen:scaleBySize(1000) / 1000
    return Font:getFace(name, math.max(6, math.floor(pixels / scale)))
end

-- Màu là cdata FFI: so sánh `==` với nil gọi __eq của Blitbuffer và crash KOReader.
-- Muốn biết kiểu ô thì dùng cờ boolean trong style, đừng so màu.
local Board = InputContainer:extend{
    game = nil,
    size = nil,        -- cạnh bàn cờ, pixel
    icons_dir = nil,
    on_tap = nil,      -- function(row, col)
    frames = nil,      -- danh sách { top, left, bottom, right } cần đóng khung
}

function Board:init()
    self.cell = math.floor(self.size / 9)
    self.size = self.cell * 9
    self.dimen = Geom:new{ x = 0, y = 0, w = self.size, h = self.size }
    self.thin = math.max(1, math.floor(self.cell / 56))
    self.thick = math.max(2, math.floor(self.cell / 28))
    self.border = math.max(3, math.floor(self.cell / 16))
    self.thin_border = math.max(2, math.floor(self.border / 2))
    self.frame_width = math.max(4, math.floor(self.cell / 11))
    -- Số đề bài in đậm, số mình điền in thường: xám nhạt dần không đủ tách hai loại
    self.given_face = faceForPixels("tfont", self.cell * NUMBER_RATIO)
    self.entry_face = faceForPixels("cfont", self.cell * NUMBER_RATIO)
    self.note_face = faceForPixels("cfont", self.cell * NOTE_RATIO)
    self.painted = {}

    local play_size = math.floor(self.size * PLAY_RATIO)
    -- Giữ làm con để CloseWidget giải phóng ảnh
    self[1] = IconWidget:new{
        file = self.icons_dir .. "/play-big.svg",
        width = play_size,
        height = play_size,
        alpha = true,
    }

    self.ges_events = {
        TapBoard = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        },
    }
end

function Board:getSize()
    return self.dimen
end

function Board:onTapBoard(_, ges)
    local x = ges.pos.x - self.dimen.x
    local y = ges.pos.y - self.dimen.y
    if x < 0 or y < 0 or x >= self.size or y >= self.size then return false end

    local row = math.min(9, math.floor(y / self.cell) + 1)
    local col = math.min(9, math.floor(x / self.cell) + 1)
    if self.on_tap then self.on_tap(row, col) end
    return true
end

-- ==================== KIỂU TỪNG Ô ====================

-- Khác bản web vì e-ink:
--   * Không tô nền dấu cộng hàng/cột/khối hay ô cùng số. Mỗi lần chọn ô đổi nền cả
--     chục ô, refresh "ui" chạy qua đen rồi mới về xám nên cả hàng cột nháy lên.
--     Ô đang chọn có viền đậm, ô cùng số có viền mảnh: chạm ô khác chỉ đổi pixel viền.
--   * Ô sai luôn nền đen chữ trắng.
--   * Tạm dừng thì bàn cờ trống trơn: không số, không viền, không ô sai.
function Board:cellStyle(row, col)
    local game = self.game
    local hidden = game:isHidden()
    local style = {
        value = hidden and 0 or game.entries[row][col],
        notes = hidden and 0 or game.notes[row][col],
        selected = not hidden and game:isSelected(row, col),
    }

    local sel = game.selected
    if not hidden and sel and not style.selected and not game.errors[row][col] then
        local selected_value = game.entries[sel.row][sel.col]
        style.same_number = selected_value ~= 0 and style.value == selected_value
    end

    if game.errors[row][col] and not hidden then
        style.error = true
        style.background = COLOR.error
        style.color = COLOR.light_text
    end

    if not style.color then
        style.color = game.given[row][col] and COLOR.given_text or COLOR.entry_text
    end
    style.given = game.given[row][col]
    for _, frame in ipairs(hidden and {} or self.frames or {}) do
        if row >= frame[1] and row <= frame[3] and col >= frame[2] and col <= frame[4] then
            style.framed = true
        end
    end
    style.key = table.concat({ style.background and style.background:getColor8().a or "-",
        style.color:getColor8().a,
        style.value, style.notes, tostring(style.selected), tostring(hidden),
        tostring(style.framed), tostring(style.same_number) }, "|")
    return style
end

-- Hình chữ nhật (toạ độ màn hình) bao các ô trông khác lần vẽ trước, hoặc nil.
-- Refresh đúng vùng này thay vì cả bàn cờ để e-ink không phải chạy lại các ô đứng yên.
function Board:changedRect()
    local top, left, bottom, right = 10, 10, 0, 0
    for row = 1, 9 do
        for col = 1, 9 do
            if self.painted[row * 10 + col] ~= self:cellStyle(row, col).key then
                top, bottom = math.min(top, row), math.max(bottom, row)
                left, right = math.min(left, col), math.max(right, col)
            end
        end
    end
    if bottom == 0 then return nil end

    return Geom:new{
        x = self.dimen.x + (left - 1) * self.cell,
        y = self.dimen.y + (top - 1) * self.cell,
        w = (right - left + 1) * self.cell,
        h = (bottom - top + 1) * self.cell,
    }
end

-- ==================== VẼ ====================

local function drawCentered(bb, face, text, x, y, w, h, color)
    local metrics = RenderText:sizeUtf8Text(0, w, face, text, true, false)
    local baseline = y + math.floor((h + metrics.y_top - metrics.y_bottom) / 2)
    local text_x = x + math.floor((w - metrics.x) / 2)
    RenderText:renderUtf8Text(bb, text_x, baseline, face, text, true, false, color)
end

function Board:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local game, cell = self.game, self.cell

    bb:paintRect(x, y, self.size, self.size, COLOR.background)
    if not game or not game.entries then return end

    local selected_rect
    local same_cells = {}
    for row = 1, 9 do
        for col = 1, 9 do
            local cell_x = x + (col - 1) * cell
            local cell_y = y + (row - 1) * cell
            local style = self:cellStyle(row, col)
            self.painted[row * 10 + col] = style.key

            if style.background then
                bb:paintRect(cell_x, cell_y, cell, cell, style.background)
            end

            if style.value ~= 0 then
                drawCentered(bb, style.given and self.given_face or self.entry_face,
                    tostring(style.value), cell_x, cell_y, cell, cell, style.color)
            elseif style.notes ~= 0 then
                local color = style.error and COLOR.light_text or COLOR.note_text
                local mini = cell / 3
                for num = 1, 9 do
                    if game:hasNote(row, col, num) then
                        local slot = num - 1
                        drawCentered(bb, self.note_face, tostring(num),
                            cell_x + math.floor((slot % 3) * mini),
                            cell_y + math.floor(math.floor(slot / 3) * mini),
                            math.floor(mini), math.floor(mini), color)
                    end
                end
            end

            if style.same_number then
                same_cells[#same_cells + 1] = { cell_x, cell_y }
            end

            if style.selected then
                selected_rect = { cell_x, cell_y, style.error }
            end
        end
    end

    self:paintGrid(bb, x, y)

    -- Viền ô chọn và ô cùng số vẽ sau lưới để không bị đường kẻ đè lên
    for _, pos in ipairs(same_cells) do
        bb:paintBorder(pos[1], pos[2], cell, cell, self.thin_border, COLOR.selected_border)
    end
    if selected_rect then
        local sx, sy, on_black = selected_rect[1], selected_rect[2], selected_rect[3]
        local color = on_black and COLOR.light_text or COLOR.selected_border
        local inset = on_black and self.border or 0
        bb:paintBorder(sx + inset, sy + inset, cell - 2 * inset, cell - 2 * inset, self.border, color)
    end

    for _, frame in ipairs(game:isHidden() and {} or self.frames or {}) do
        bb:paintBorder(x + (frame[2] - 1) * cell, y + (frame[1] - 1) * cell,
            (frame[4] - frame[2] + 1) * cell, (frame[3] - frame[1] + 1) * cell,
            self.frame_width, COLOR.frame)
    end

    if game:isHidden() then
        local play = self[1]
        local play_size = play:getSize()
        play:paintTo(bb, x + math.floor((self.size - play_size.w) / 2),
            y + math.floor((self.size - play_size.h) / 2))
    end
end

-- Kẻ bằng paintRect, đường nằm gọn trong bàn cờ để không lem ra ngoài vùng refresh
function Board:paintGrid(bb, x, y)
    local size, cell = self.size, self.cell

    for i = 1, 8 do
        if i % 3 ~= 0 then
            local offset = i * cell - math.floor(self.thin / 2)
            bb:paintRect(x + offset, y, self.thin, size, COLOR.thin_line)
            bb:paintRect(x, y + offset, size, self.thin, COLOR.thin_line)
        end
    end

    for i = 0, 3 do
        local offset = math.min(size - self.thick, math.max(0, i * 3 * cell - math.floor(self.thick / 2)))
        bb:paintRect(x + offset, y, self.thick, size, COLOR.thick_line)
        bb:paintRect(x, y + offset, size, self.thick, COLOR.thick_line)
    end
end

return Board
