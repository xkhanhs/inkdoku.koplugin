-- Kiểm tra logic thuần của plugin KOReader, không cần KOReader:
--   luajit tools/koreader/test-logic.lua

package.path = "sudoku.koplugin/?.lua;" .. package.path
local Logic = require("sudoku_logic")
local Game = require("sudoku_game")
local Bank = require("sudoku_bank")

math.randomseed(os.time())

local failures = 0
local function check(name, ok)
    if not ok then
        failures = failures + 1
        print("FAIL  " .. name)
    end
end

local function validSolution(grid)
    for i = 1, 9 do
        local row, col, box = {}, {}, {}
        for j = 1, 9 do
            local r = grid[i][j]
            local c = grid[j][i]
            local b = grid[math.floor((i - 1) / 3) * 3 + math.floor((j - 1) / 3) + 1]
                         [((i - 1) % 3) * 3 + (j - 1) % 3 + 1]
            if r < 1 or row[r] or col[c] or box[b] then return false end
            row[r], col[c], box[b] = true, true, true
        end
    end
    return true
end

-- ==================== SINH ĐỀ ====================

for _, difficulty in ipairs({ "easy", "medium", "hard" }) do
    local total, worst = 0, 0
    for _ = 1, 20 do
        local started = os.clock()
        local puzzle, solution = Logic.generate(difficulty)
        local spent = os.clock() - started
        total, worst = total + spent, math.max(worst, spent)

        local blanks = 0
        for row = 1, 9 do
            for col = 1, 9 do
                if puzzle[row][col] == 0 then
                    blanks = blanks + 1
                else
                    check(difficulty .. " đề khớp lời giải", puzzle[row][col] == solution[row][col])
                end
            end
        end
        check(difficulty .. " lời giải hợp lệ", validSolution(solution))
        check(difficulty .. " nghiệm duy nhất", Logic.countSolutions(puzzle, 3) == 1)
        check(difficulty .. " đủ ô trống", blanks == Logic.REMOVALS[difficulty])
    end
    print(string.format("%-7s 20 đề, trung bình %.2f ms, chậm nhất %.2f ms",
        difficulty, total / 20 * 1000, worst * 1000))
end

-- ==================== ĐỀ ĐÓNG GÓI ====================

for level in pairs(Bank.LEVELS) do
    local lines = Bank.readLines("sudoku.koplugin/puzzles/" .. level .. ".txt")
    check(level .. " có file đề", lines and #lines > 0)
    local started = os.clock()
    for _, line in ipairs(lines or {}) do
        local puzzle = Logic.parse(line)
        check(level .. " đọc được đề", puzzle ~= nil)
        check(level .. " nghiệm duy nhất " .. line, Logic.countSolutions(puzzle, 2) == 1)
    end
    local puzzle, solution = Bank.pick("sudoku.koplugin/puzzles", level)
    check(level .. " pick có lời giải", puzzle and validSolution(solution))
    print(string.format("%-7s %d đề đều duy nhất, %.2f ms/đề", level, #(lines or {}),
        (os.clock() - started) / math.max(1, #(lines or {})) * 1000))
end

-- ==================== LUẬT CHƠI ====================

local now = 1000
local function clock() return now end

local puzzle, solution = Logic.generate("easy")

local function firstEmpty(game)
    for row = 1, 9 do
        for col = 1, 9 do
            if not game.locked[row][col] and game.entries[row][col] == 0 then
                return row, col
            end
        end
    end
end

local function wrongDigit(row, col)
    return solution[row][col] % 9 + 1
end

do -- điền sai, điền đúng khoá ô, undo không mở khoá
    local game = Game.new(clock)
    game:start("easy", puzzle, solution)
    local row, col = firstEmpty(game)
    check("chưa chọn ô thì bỏ qua", game:input(1) == nil)
    game:select(row, col)
    check("điền sai", game:input(wrongDigit(row, col)).kind == "wrong")
    check("tăng lỗi", game.mistakes == 1 and game.errors[row][col])
    check("undo điền sai", game:undo() and game.entries[row][col] == 0 and not game.errors[row][col])
    check("điền đúng", game:input(solution[row][col]).kind == "correct")
    check("khoá ô", game.locked[row][col])
    check("ô khoá không nhận số", game:input(wrongDigit(row, col)) == nil)
    check("undo ô khoá bị bỏ", not game:undo() and game.entries[row][col] == solution[row][col])
end

do -- ghi chú bitmask, clear, giới hạn history
    local game = Game.new(clock)
    game:start("easy", puzzle, solution)
    local row, col = firstEmpty(game)
    game:select(row, col)
    game:togglePencil()
    game:input(3)
    game:input(7)
    check("ghi chú 3 và 7", game.notes[row][col] == 4 + 64 and game:hasNote(row, col, 7))
    game:input(3)
    check("tắt ghi chú 3", not game:hasNote(row, col, 3) and game:hasNote(row, col, 7))
    check("clear", game:clear() and game.notes[row][col] == 0)
    check("clear ô trống thì bỏ qua", not game:clear())
    for i = 1, 60 do game:input(i % 9 + 1) end
    check("history tối đa 50", #game.history == Game.MAX_HISTORY)
end

do -- thua sau 3 lỗi
    local game = Game.new(clock)
    game:start("easy", puzzle, solution)
    local row, col = firstEmpty(game)
    game:select(row, col)
    game:input(wrongDigit(row, col))
    game:input(wrongDigit(row, col))
    local result = game:input(wrongDigit(row, col))
    check("thua", result.kind == "lost" and game.lost and not game:canPlay())
    check("thua không che số", not game:isHidden())
    game:retry()
    check("chơi lại", game.mistakes == 0 and not game.lost and game.entries[row][col] == 0)
end

do -- hoàn thành vùng, gợi ý, thắng
    local game = Game.new(clock)
    game:start("easy", puzzle, solution)
    local last_col
    for col = 1, 9 do
        if not game.locked[1][col] then last_col = col end
    end
    for col = 1, 9 do
        if not game.locked[1][col] and col ~= last_col then
            game:select(1, col)
            check("chưa xong hàng thì không có vùng", #game:input(solution[1][col]).regions == 0
                or col == last_col)
        end
    end
    game:select(1, last_col)
    local done = game:input(solution[1][last_col])
    local has_row = false
    for _, region in ipairs(done.regions) do
        if region[1] == 1 and region[2] == 1 and region[3] == 1 and region[4] == 9 then has_row = true end
    end
    check("xong hàng trả về vùng hàng 1", has_row)

    local hint = game:hint()
    check("gợi ý giảm lượt và khoá ô", hint and game.hints == 2
        and game.locked[game.selected.row][game.selected.col])

    local won
    while true do
        local row, col = firstEmpty(game)
        if not row then break end
        game:select(row, col)
        won = game:input(solution[row][col])
    end
    check("thắng", won and won.kind == "won" and game.won and not game:isHidden())
end

do -- đồng hồ, tạm dừng, lưu và nạp
    now = 1000
    local game = Game.new(clock)
    game:start("hard", puzzle, solution)
    now = now + 75
    check("đếm giây", game:seconds() == 75)
    game:pause()
    now = now + 500
    check("tạm dừng không đếm", game:seconds() == 75 and game:isHidden() and not game:canPlay())
    game:resume()
    now = now + 5
    check("chạy tiếp", game:seconds() == 80)

    local row, col = firstEmpty(game)
    game:select(row, col)
    game:togglePencil()
    game:input(5)
    game:togglePencil()
    local row2, col2 = row, col + 1
    while game.locked[row2] and (col2 > 9 or game.locked[row2][col2]) do
        col2 = col2 + 1
        if col2 > 9 then row2, col2 = row2 + 1, 1 end
    end
    game:select(row2, col2)
    game:input(wrongDigit(row2, col2))

    local saved = game:serialize()
    local loaded = Game.new(clock)
    check("nạp ván", loaded:load(saved))
    check("nạp vào trạng thái tạm dừng", loaded:isHidden() and loaded:seconds() == 80)
    check("nạp ghi chú", loaded:hasNote(row, col, 5))
    check("nạp ô sai và số lỗi", loaded.errors[row2][col2] and loaded.mistakes == 1)
    check("nạp đề gốc", loaded.given[1][1] == (puzzle[1][1] ~= 0))
    check("từ chối dữ liệu hỏng", not Game.new(clock):load({ version = 1, puzzle = "123" }))
end

if failures > 0 then
    print(failures .. " kiểm tra thất bại")
    os.exit(1)
end
print("Tất cả kiểm tra đều qua")
