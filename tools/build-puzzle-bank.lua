-- Dựng puzzles/*.txt từ grantm/sudoku-exchange-puzzle-bank (public domain).
--
--   curl -LO https://github.com/grantm/sudoku-exchange-puzzle-bank/raw/master/hard.txt
--   curl -LO https://github.com/grantm/sudoku-exchange-puzzle-bank/raw/master/diabolical.txt
--   luajit tools/build-puzzle-bank.lua hard.txt diabolical.txt
--
-- File nguồn đã xếp theo hash nên lấy N dòng đầu khớp khoảng rating là đủ ngẫu nhiên.
-- Mỗi đề được kiểm lại đúng một nghiệm trước khi ghi.

package.path = "./?.lua;" .. package.path
local Logic = require("inkdoku_logic")

local PER_LEVEL = 300
local LEVELS = {
    { name = "expert", source = 1, min = 3.0, max = 5.0 },   -- Chuyên gia
    { name = "master", source = 2, min = 5.0, max = 7.0 },   -- Thành thạo
    { name = "extreme", source = 2, min = 7.0, max = 99 },   -- Cao thủ
}

local sources = { arg[1], arg[2] }
assert(sources[1] and sources[2], "cách dùng: luajit build-puzzle-bank.lua hard.txt diabolical.txt")

for _, level in ipairs(LEVELS) do
    local picked = {}
    for line in io.lines(sources[level.source]) do
        local digits, rating = line:match("^%x+ (%d+) +([%d.]+)")
        rating = tonumber(rating)
        if digits and #digits == 81 and rating >= level.min and rating < level.max then
            assert(Logic.countSolutions(Logic.parse(digits), 2) == 1, "đề không duy nhất: " .. digits)
            picked[#picked + 1] = digits
            if #picked == PER_LEVEL then break end
        end
    end
    assert(#picked == PER_LEVEL, level.name .. ": chỉ có " .. #picked .. " đề")

    local out = assert(io.open("puzzles/" .. level.name .. ".txt", "w"))
    out:write(table.concat(picked, "\n"), "\n")
    out:close()
    print(level.name, #picked)
end
