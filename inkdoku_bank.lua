-- ==================== ĐỀ ĐÓNG GÓI SẴN ====================
-- Ba mức khó nhất không tự sinh: đục tới 17-25 ô gợi ý mà vẫn giữ nghiệm duy nhất
-- thì phải quay lui rất lâu trên CPU máy đọc sách. Thay vào đó chọn ngẫu nhiên một
-- đề trong puzzles/<mức>.txt, mỗi dòng 81 chữ số, 0 là ô trống.
--
-- Nguồn đề và cách dựng lại: tools/koreader/build-puzzle-bank.lua, puzzles/SOURCE.txt.

local Logic = require("sudoku_logic")

local Bank = {}

Bank.LEVELS = { expert = true, master = true, extreme = true }

function Bank.readLines(path)
    local file = io.open(path, "r")
    if not file then return nil end

    local lines = {}
    for line in file:lines() do
        line = line:gsub("%s+$", "")
        if #line == 81 then
            lines[#lines + 1] = line
        end
    end
    file:close()
    return lines
end

-- Trả về đề và lời giải, hoặc nil nếu file thiếu/hỏng
function Bank.pick(dir, difficulty, random)
    local lines = Bank.readLines(dir .. "/" .. difficulty .. ".txt")
    if not lines or #lines == 0 then return nil end

    local puzzle = Logic.parse(lines[(random or math.random)(#lines)])
    if not puzzle then return nil end

    local solution = Logic.solve(puzzle)
    if not solution then return nil end

    return puzzle, solution
end

return Bank
