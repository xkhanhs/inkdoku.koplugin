-- ==================== SINH ĐỀ VÀ GIẢI ====================
-- Lua thuần, không phụ thuộc KOReader, chạy thử được bằng luajit trên máy tính.
--
-- Bàn cờ công khai là bảng 9x9 đánh số từ 1, ô trống là 0. Bên trong solver dùng
-- mảng phẳng 81 ô cùng ba bộ bitmask hàng/cột/khối: bit k ứng với số k+1.
--
-- Khác bản web: `removeNumbers()` bên JS đục ô ngẫu nhiên không kiểm tra gì, nên
-- đề khó thường có nhiều lời giải. Ở đây mỗi ô đục đều đếm lại nghiệm, chỉ giữ ô
-- đục nếu đề còn đúng một lời giải.

local bit = require("bit")
local band, bor, bnot, lshift = bit.band, bit.bor, bit.bnot, bit.lshift

local Logic = {}

local ALL_DIGITS = 0x1FF

-- Tra sẵn hàng, cột, khối của từng ô (chỉ số 0..8) để vòng lặp không phải chia
local ROW_OF, COL_OF, BOX_OF = {}, {}, {}
for index = 1, 81 do
    local row = math.floor((index - 1) / 9)
    local col = (index - 1) % 9
    ROW_OF[index] = row
    COL_OF[index] = col
    BOX_OF[index] = math.floor(row / 3) * 3 + math.floor(col / 3)
end

-- Số bit bật và số nhỏ nhất ứng với mỗi mask 9 bit
local POPCOUNT, LOWEST_DIGIT = {}, {}
for mask = 0, ALL_DIGITS do
    local count, lowest = 0, 0
    for digit = 9, 1, -1 do
        if band(mask, lshift(1, digit - 1)) ~= 0 then
            count = count + 1
            lowest = digit
        end
    end
    POPCOUNT[mask] = count
    LOWEST_DIGIT[mask] = lowest
end

-- Số ô cần đục cho các mức tự sinh, giữ đúng số của bản web
Logic.REMOVALS = {
    easy = 31,   -- còn 50 ô
    medium = 41, -- còn 40 ô
    hard = 51,   -- còn 30 ô
}

local function toFlat(grid)
    local cells = {}
    for row = 1, 9 do
        for col = 1, 9 do
            cells[(row - 1) * 9 + col] = grid[row][col]
        end
    end
    return cells
end

local function toGrid(cells)
    local grid = {}
    for row = 1, 9 do
        grid[row] = {}
        for col = 1, 9 do
            grid[row][col] = cells[(row - 1) * 9 + col]
        end
    end
    return grid
end

Logic.toFlat = toFlat
Logic.toGrid = toGrid

function Logic.emptyGrid(value)
    local grid = {}
    for row = 1, 9 do
        grid[row] = {}
        for col = 1, 9 do
            grid[row][col] = value
        end
    end
    return grid
end

function Logic.copyGrid(src)
    local grid = {}
    for row = 1, 9 do
        grid[row] = {}
        for col = 1, 9 do
            grid[row][col] = src[row][col]
        end
    end
    return grid
end

-- Dựng mask đã dùng. Trả về nil nếu đề tự mâu thuẫn (một số lặp trong hàng/cột/khối).
local function buildMasks(cells)
    local rows, cols, boxes = {}, {}, {}
    for i = 0, 8 do
        rows[i], cols[i], boxes[i] = 0, 0, 0
    end
    for index = 1, 81 do
        local value = cells[index]
        if value ~= 0 then
            local digit = lshift(1, value - 1)
            local row, col, box = ROW_OF[index], COL_OF[index], BOX_OF[index]
            if band(bor(rows[row], cols[col], boxes[box]), digit) ~= 0 then
                return nil
            end
            rows[row] = bor(rows[row], digit)
            cols[col] = bor(cols[col], digit)
            boxes[box] = bor(boxes[box], digit)
        end
    end
    return rows, cols, boxes
end

-- Tìm kiếm quay lui chọn ô ít ứng viên nhất trước (MRV).
-- `visit` được gọi mỗi khi điền kín bàn; trả true để dừng tìm.
-- `shuffle` (tuỳ chọn) xáo thứ tự thử số, dùng khi sinh lời giải ngẫu nhiên.
local function search(cells, visit, shuffle)
    local rows, cols, boxes = buildMasks(cells)
    if not rows then return end

    local empties = {}
    for index = 1, 81 do
        if cells[index] == 0 then
            empties[#empties + 1] = index
        end
    end

    local function step(remaining)
        if remaining == 0 then
            return visit(cells)
        end

        -- Đưa ô ít ứng viên nhất về cuối danh sách còn trống
        local best_pos, best_free, best_count = 0, 0, 10
        for pos = 1, remaining do
            local index = empties[pos]
            local free = band(bnot(bor(rows[ROW_OF[index]], cols[COL_OF[index]], boxes[BOX_OF[index]])), ALL_DIGITS)
            local count = POPCOUNT[free]
            if count < best_count then
                best_pos, best_free, best_count = pos, free, count
                if count <= 1 then break end
            end
        end
        if best_count == 0 then return false end

        empties[best_pos], empties[remaining] = empties[remaining], empties[best_pos]
        local index = empties[remaining]
        local row, col, box = ROW_OF[index], COL_OF[index], BOX_OF[index]

        local digits = {}
        local free = best_free
        while free ~= 0 do
            local value = LOWEST_DIGIT[free]
            digits[#digits + 1] = value
            free = band(free, bnot(lshift(1, value - 1)))
        end
        if shuffle then shuffle(digits) end

        for _, value in ipairs(digits) do
            local digit = lshift(1, value - 1)
            cells[index] = value
            rows[row] = bor(rows[row], digit)
            cols[col] = bor(cols[col], digit)
            boxes[box] = bor(boxes[box], digit)

            local stop = step(remaining - 1)

            rows[row] = band(rows[row], bnot(digit))
            cols[col] = band(cols[col], bnot(digit))
            boxes[box] = band(boxes[box], bnot(digit))
            cells[index] = 0

            if stop then
                empties[best_pos], empties[remaining] = empties[remaining], empties[best_pos]
                return true
            end
        end

        empties[best_pos], empties[remaining] = empties[remaining], empties[best_pos]
        return false
    end

    step(#empties)
end

local function shuffleInPlace(list, random)
    random = random or math.random
    for i = #list, 2, -1 do
        local j = random(i)
        list[i], list[j] = list[j], list[i]
    end
    return list
end

Logic.shuffle = shuffleInPlace

-- Đếm nghiệm, dừng khi chạm `limit` (mặc định 2: chỉ cần biết có duy nhất hay không)
function Logic.countSolutions(grid, limit)
    limit = limit or 2
    local count = 0
    search(toFlat(grid), function()
        count = count + 1
        return count >= limit
    end)
    return count
end

-- Lời giải đầu tiên tìm được, hoặc nil nếu đề vô nghiệm
function Logic.solve(grid)
    local solution
    search(toFlat(grid), function(cells)
        solution = toGrid(cells)
        return true
    end)
    return solution
end

function Logic.generateSolution(random)
    local solution
    search(toFlat(Logic.emptyGrid(0)), function(cells)
        solution = toGrid(cells)
        return true
    end, function(digits) shuffleInPlace(digits, random) end)
    return solution
end

-- Đục ô theo thứ tự ngẫu nhiên, bỏ qua ô nào làm đề mất tính duy nhất.
-- Trả về đề và số ô thực sự đục được (có thể ít hơn `removals` nếu hết ô đục được).
function Logic.createPuzzle(solution, removals, random)
    local puzzle = Logic.copyGrid(solution)
    local order = {}
    for index = 1, 81 do
        order[index] = index
    end
    shuffleInPlace(order, random)

    local removed = 0
    for _, index in ipairs(order) do
        if removed >= removals then break end

        local row = ROW_OF[index] + 1
        local col = COL_OF[index] + 1
        local backup = puzzle[row][col]
        puzzle[row][col] = 0

        if Logic.countSolutions(puzzle, 2) == 1 then
            removed = removed + 1
        else
            puzzle[row][col] = backup
        end
    end

    return puzzle, removed
end

-- Sinh trọn một ván cho các mức tự sinh
function Logic.generate(difficulty, random)
    local removals = Logic.REMOVALS[difficulty]
    assert(removals, "mức không tự sinh: " .. tostring(difficulty))

    local solution = Logic.generateSolution(random)
    local puzzle = Logic.createPuzzle(solution, removals, random)
    return puzzle, solution
end

-- Đề dạng chuỗi 81 ký tự, '0' hoặc '.' là ô trống
function Logic.parse(text)
    if type(text) ~= "string" or #text ~= 81 then return nil end

    local grid = Logic.emptyGrid(0)
    for index = 1, 81 do
        local char = text:sub(index, index)
        local value = char == "." and 0 or tonumber(char)
        if not value then return nil end
        grid[ROW_OF[index] + 1][COL_OF[index] + 1] = value
    end
    return grid
end

function Logic.serialize(grid)
    return table.concat(toFlat(grid))
end

return Logic
