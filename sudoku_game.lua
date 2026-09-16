-- ==================== TRẠNG THÁI VÀ LUẬT CHƠI ====================
-- Dịch từ js/state.js + phần luật trong js/ui-controller.js và script.js.
-- Lua thuần, không vẽ gì: màn chơi gọi các hàm ở đây rồi vẽ lại theo kết quả trả về.
--
-- Hàng, cột đánh số từ 1. Các lưới 9x9:
--   given   - ô có sẵn từ đề bài
--   entries - số đang hiển thị, 0 là ô trống
--   notes   - bitmask 9 bit, bit k ứng với số k+1
--   locked  - ô không cho sửa nữa
--   errors  - ô đang điền sai

local bit = require("bit")
local Logic = require("sudoku_logic")

local band, bxor, lshift = bit.band, bit.bxor, bit.lshift

local Game = {}
Game.__index = Game

Game.MAX_MISTAKES = 3
Game.MAX_HINTS = 3
Game.MAX_HISTORY = 50

-- `clock` trả về số giây (mặc định os.time), tách ra để test tua được thời gian
function Game.new(clock)
    return setmetatable({ clock = clock or os.time }, Game)
end

-- Ô nằm trong "dấu cộng" của ô đang chọn: cùng hàng, cùng cột hoặc cùng khối 3x3
function Game.inCross(row, col, from_row, from_col)
    return row == from_row or col == from_col
        or (math.floor((row - 1) / 3) == math.floor((from_row - 1) / 3)
            and math.floor((col - 1) / 3) == math.floor((from_col - 1) / 3))
end

-- ==================== VÁN MỚI ====================

function Game:start(difficulty, puzzle, solution)
    self.difficulty = difficulty
    self.puzzle = Logic.copyGrid(puzzle)
    self.solution = Logic.copyGrid(solution)
    self:retry()
end

-- Chơi lại đúng đề đang có từ đầu
function Game:retry()
    self.given = Logic.emptyGrid(false)
    self.locked = Logic.emptyGrid(false)
    for row = 1, 9 do
        for col = 1, 9 do
            local has_value = self.puzzle[row][col] ~= 0
            self.given[row][col] = has_value
            self.locked[row][col] = has_value
        end
    end
    self.entries = Logic.copyGrid(self.puzzle)
    self.notes = Logic.emptyGrid(0)
    self.errors = Logic.emptyGrid(false)
    self.selected = nil
    self.history = {}
    self.mistakes = 0
    self.hints = Game.MAX_HINTS
    self.pencil = false
    self.lost = false
    self.won = false

    self.elapsed = 0
    self.paused = false
    self.resumed_at = self.clock()
end

-- ==================== ĐỒNG HỒ ====================

function Game:seconds()
    if self.paused then return self.elapsed end
    return self.elapsed + math.max(0, self.clock() - self.resumed_at)
end

-- Chốt số giây đã chơi và dừng đếm. Dùng chung cho tạm dừng, thắng và thua.
function Game:stopClock()
    if not self.paused then
        self.elapsed = self:seconds()
        self.paused = true
    end
end

function Game:pause()
    if self.won or self.lost then return false end
    self:stopClock()
    return true
end

function Game:resume()
    if self.won or self.lost or not self.paused then return false end
    self.paused = false
    self.resumed_at = self.clock()
    return true
end

-- Đang tạm dừng theo nghĩa người chơi thấy màn che (không tính lúc thắng/thua)
function Game:isHidden()
    return self.paused and not self.won and not self.lost
end

function Game:canPlay()
    return not (self.paused or self.won or self.lost)
end

-- ==================== CHỌN Ô VÀ GHI CHÚ ====================

function Game:select(row, col)
    self.selected = { row = row, col = col }
end

function Game:isSelected(row, col)
    local sel = self.selected
    return sel ~= nil and sel.row == row and sel.col == col
end

function Game:hasNote(row, col, num)
    return band(self.notes[row][col], lshift(1, num - 1)) ~= 0
end

function Game:togglePencil()
    self.pencil = not self.pencil
    return self.pencil
end

-- ==================== HOÀN THÀNH ====================

function Game:isWin()
    for row = 1, 9 do
        for col = 1, 9 do
            if self.entries[row][col] ~= self.solution[row][col] then
                return false
            end
        end
    end
    return true
end

-- Hàng, cột, khối chứa ô (row, col) vừa được điền kín đúng lời giải.
-- Mỗi vùng là { top, left, bottom, right }, đánh số từ 1, gồm cả hai đầu.
function Game:completedRegions(row, col)
    local box_row = math.floor((row - 1) / 3) * 3 + 1
    local box_col = math.floor((col - 1) / 3) * 3 + 1
    local candidates = {
        { row, 1, row, 9 },
        { 1, col, 9, col },
        { box_row, box_col, box_row + 2, box_col + 2 },
    }

    local regions = {}
    for _, region in ipairs(candidates) do
        local done = true
        for r = region[1], region[3] do
            for c = region[2], region[4] do
                if self.entries[r][c] ~= self.solution[r][c] then done = false end
            end
        end
        if done then regions[#regions + 1] = region end
    end
    return regions
end

-- ==================== ĐIỀN SỐ ====================

local function pushHistory(self, row, col)
    local history = self.history
    history[#history + 1] = {
        row = row,
        col = col,
        value = self.entries[row][col],
        notes = self.notes[row][col],
        error = self.errors[row][col],
    }
    if #history > Game.MAX_HISTORY then
        table.remove(history, 1)
    end
end

-- Kết quả trả về cho màn chơi biết phải vẽ lại gì:
--   nil                          - không làm gì
--   { kind = "note" }            - bật/tắt ghi chú
--   { kind = "wrong" }           - điền sai, còn chơi tiếp
--   { kind = "lost" }            - sai lần thứ MAX_MISTAKES
--   { kind = "correct", regions } - điền đúng; regions là hàng/cột/khối vừa xong
--   { kind = "won" }             - điền ô cuối cùng
local function afterCorrect(self, row, col)
    self.errors[row][col] = false
    self.locked[row][col] = true

    if self:isWin() then
        self.won = true
        self:stopClock()
        return { kind = "won" }
    end

    return { kind = "correct", regions = self:completedRegions(row, col) }
end

function Game:input(num)
    if not self:canPlay() then return nil end

    local sel = self.selected
    if not sel then return nil end

    local row, col = sel.row, sel.col
    if self.locked[row][col] then return nil end

    pushHistory(self, row, col)

    if self.pencil then
        -- Ghi chú chỉ có nghĩa trên ô trống
        self.entries[row][col] = 0
        self.errors[row][col] = false
        self.notes[row][col] = bxor(self.notes[row][col], lshift(1, num - 1))
        return { kind = "note" }
    end

    self.notes[row][col] = 0
    self.entries[row][col] = num

    if num ~= self.solution[row][col] then
        self.errors[row][col] = true
        self.mistakes = self.mistakes + 1
        if self.mistakes >= Game.MAX_MISTAKES then
            self.lost = true
            self:stopClock()
            return { kind = "lost" }
        end
        return { kind = "wrong" }
    end

    -- Điền đúng thì khoá ô lại, không cho sửa nữa
    return afterCorrect(self, row, col)
end

-- ==================== UNDO & CLEAR ====================

function Game:undo()
    if not self:canPlay() then return false end

    local move = table.remove(self.history)
    if not move then return false end
    if self.locked[move.row][move.col] then return false end

    self.entries[move.row][move.col] = move.value
    self.notes[move.row][move.col] = move.notes
    self.errors[move.row][move.col] = move.error
    self:select(move.row, move.col)
    return true
end

function Game:clear()
    local sel = self.selected
    if not sel or not self:canPlay() then return false end

    local row, col = sel.row, sel.col
    if self.locked[row][col] then return false end
    if self.entries[row][col] == 0 and self.notes[row][col] == 0 then return false end

    pushHistory(self, row, col)
    self.entries[row][col] = 0
    self.notes[row][col] = 0
    self.errors[row][col] = false
    return true
end

-- ==================== GỢI Ý ====================

-- Điền lời giải vào một ô trống ngẫu nhiên. Ô gợi ý được khoá như ô điền đúng.
function Game:hint(random)
    if self.hints <= 0 or not self:canPlay() then return nil end

    local empty = {}
    for row = 1, 9 do
        for col = 1, 9 do
            if not self.locked[row][col] and self.entries[row][col] == 0 then
                empty[#empty + 1] = { row = row, col = col }
            end
        end
    end
    if #empty == 0 then return nil end

    local cell = empty[(random or math.random)(#empty)]
    local row, col = cell.row, cell.col

    self.entries[row][col] = self.solution[row][col]
    self.notes[row][col] = 0
    self:select(row, col)
    self.hints = self.hints - 1

    return afterCorrect(self, row, col)
end

-- ==================== LƯU VÀ NẠP ====================

function Game:serialize()
    return {
        version = 1,
        difficulty = self.difficulty,
        puzzle = Logic.serialize(self.puzzle),
        solution = Logic.serialize(self.solution),
        entries = Logic.serialize(self.entries),
        notes = Logic.toFlat(self.notes),
        locked = Logic.toFlat(self.locked),
        errors = Logic.toFlat(self.errors),
        seconds = self:seconds(),
        mistakes = self.mistakes,
        hints = self.hints,
        lost = self.lost,
        won = self.won,
    }
end

local function validFlat(list, kind)
    if type(list) ~= "table" then return false end
    for index = 1, 81 do
        if type(list[index]) ~= kind then return false end
    end
    return true
end

-- Nạp ván đã lưu. Mở lại luôn vào trạng thái tạm dừng như bản web.
function Game:load(data)
    if type(data) ~= "table" or data.version ~= 1 then return false end

    local puzzle = Logic.parse(data.puzzle)
    local solution = Logic.parse(data.solution)
    local entries = Logic.parse(data.entries)
    if not (puzzle and solution and entries) then return false end
    if not (validFlat(data.notes, "number") and validFlat(data.locked, "boolean")
            and validFlat(data.errors, "boolean")) then
        return false
    end

    self.difficulty = data.difficulty
    self.puzzle = puzzle
    self:retry()
    self.solution = solution
    self.entries = entries
    self.notes = Logic.toGrid(data.notes)
    self.locked = Logic.toGrid(data.locked)
    self.errors = Logic.toGrid(data.errors)
    self.mistakes = tonumber(data.mistakes) or 0
    self.hints = tonumber(data.hints) or Game.MAX_HINTS
    self.lost = data.lost == true
    self.won = data.won == true
    self.elapsed = tonumber(data.seconds) or 0
    self.paused = true
    return true
end

return Game
