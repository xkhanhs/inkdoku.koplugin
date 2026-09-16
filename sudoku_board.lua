-- ==================== BÀN CỜ ====================
-- Dịch từ js/board-render.js. Một widget vẽ cả bàn cờ lên BlitBuffer: nền ô, số,
-- ghi chú, lưới. Chạm vào bàn cờ quy đổi toạ độ ra hàng cột như cellFromPoint().
--
-- Màu web đổi sang mức xám của e-ink, giữ nguyên thứ tự ưu tiên nền ô của
-- cellBackground(). Sóng loang thay bằng một cú chớp: các ô trong `flash` vẽ nền
-- đen chữ trắng, màn chơi lo phần hẹn giờ và refresh.

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
    cross = Blitbuffer.COLOR_GRAY_E,
    same_number = Blitbuffer.COLOR_GRAY_B,
    selected = Blitbuffer.COLOR_GRAY_5,
    error = Blitbuffer.COLOR_BLACK,
    flash = Blitbuffer.COLOR_BLACK,
    given_text = Blitbuffer.COLOR_BLACK,
    entry_text = Blitbuffer.COLOR_GRAY_4,
    note_text = Blitbuffer.COLOR_GRAY_6,
    light_text = Blitbuffer.COLOR_WHITE,
    thin_line = Blitbuffer.COLOR_GRAY_9,
    thick_line = Blitbuffer.COLOR_BLACK,
}

-- Font:getFace() nhân cỡ chữ theo DPI; ở đây cần đúng số pixel theo cạnh ô
local function faceForPixels(name, pixels)
    local scale = Screen:scaleBySize(1000) / 1000
    return Font:getFace(name, math.max(6, math.floor(pixels / scale)))
end

local Board = InputContainer:extend{
    game = nil,
    size = nil,        -- cạnh bàn cờ, pixel
    icons_dir = nil,
    on_tap = nil,      -- function(row, col)
}

function Board:init()
    self.cell = math.floor(self.size / 9)
    self.size = self.cell * 9
    self.dimen = Geom:new{ x = 0, y = 0, w = self.size, h = self.size }
    self.thin = math.max(1, math.floor(self.cell / 56))
    self.thick = math.max(2, math.floor(self.cell / 28))
    self.number_face = faceForPixels("cfont", self.cell * NUMBER_RATIO)
    self.note_face = faceForPixels("cfont", self.cell * NOTE_RATIO)
    self.flash = nil

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

-- ==================== CHỚP ĐẢO MÀU ====================

-- `cells` là danh sách {row, col}, hoặc "all" cho cả bàn. nil để tắt.
function Board:setFlash(cells)
    if cells == nil then
        self.flash = nil
        return
    end
    local flash = {}
    for row = 1, 9 do
        for col = 1, 9 do
            flash[row * 10 + col] = cells == "all"
        end
    end
    if cells ~= "all" then
        for _, cell in ipairs(cells) do
            flash[cell.row * 10 + cell.col] = true
        end
    end
    self.flash = flash
end

-- Hình chữ nhật bao các ô, toạ độ màn hình
function Board:cellsRect(cells)
    if cells == "all" then return self.dimen end

    local top, left, bottom, right = 10, 10, 0, 0
    for _, cell in ipairs(cells) do
        top, bottom = math.min(top, cell.row), math.max(bottom, cell.row)
        left, right = math.min(left, cell.col), math.max(right, cell.col)
    end
    return Geom:new{
        x = self.dimen.x + (left - 1) * self.cell,
        y = self.dimen.y + (top - 1) * self.cell,
        w = (right - left + 1) * self.cell,
        h = (bottom - top + 1) * self.cell,
    }
end

-- ==================== VẼ ====================

local function isFlashed(self, row, col)
    return self.flash ~= nil and self.flash[row * 10 + col]
end

-- Nền ô theo đúng thứ tự ưu tiên của bản web: ô chọn thắng ô cùng số, ô cùng số
-- thắng dấu cộng. Khác web: ô sai luôn nền đen, vì chữ đỏ nhạt không có mức xám nào thay được.
function Board:cellBackground(row, col)
    local game = self.game
    if isFlashed(self, row, col) then return COLOR.flash end
    if game.errors[row][col] and not game:isHidden() then return COLOR.error end

    local sel = game.selected
    if not sel then return nil end

    if sel.row == row and sel.col == col then return COLOR.selected end

    local selected_value = game.entries[sel.row][sel.col]
    local value = game.entries[row][col]
    if selected_value ~= 0 and value == selected_value and not game.errors[row][col]
            and not game:isHidden() then
        return COLOR.same_number
    end

    if game.inCross(row, col, sel.row, sel.col) then return COLOR.cross end

    return nil
end

function Board:textColor(row, col)
    local game = self.game
    if isFlashed(self, row, col) or game.errors[row][col] or game:isSelected(row, col) then
        return COLOR.light_text
    end
    if game.given[row][col] then return COLOR.given_text end

    local sel = game.selected
    if sel then
        local selected_value = game.entries[sel.row][sel.col]
        if selected_value ~= 0 and game.entries[row][col] == selected_value then
            return COLOR.given_text
        end
    end
    return COLOR.entry_text
end

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

    local hidden = game:isHidden()

    for row = 1, 9 do
        for col = 1, 9 do
            local cell_x = x + (col - 1) * cell
            local cell_y = y + (row - 1) * cell

            local background = self:cellBackground(row, col)
            if background then
                bb:paintRect(cell_x, cell_y, cell, cell, background)
            end

            if not hidden then
                local value = game.entries[row][col]
                if value ~= 0 then
                    drawCentered(bb, self.number_face, tostring(value), cell_x, cell_y, cell, cell,
                        self:textColor(row, col))
                elseif game.notes[row][col] ~= 0 then
                    local light = isFlashed(self, row, col) or game:isSelected(row, col)
                    local color = light and COLOR.light_text or COLOR.note_text
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
            end
        end
    end

    self:paintGrid(bb, x, y)

    if hidden then
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
