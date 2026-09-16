-- ==================== VỎ PLUGIN ====================
-- Thêm mục "Sudoku" vào menu công cụ, mở màn chơi, lưu ván bằng LuaSettings.
--
-- Mọi module của plugin phải require ngay khi nạp file này: pluginloader chỉ thêm
-- thư mục plugin vào package.path trong lúc dofile(main.lua), require muộn sẽ hỏng.

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Game = require("inkdoku_game")
local Logic = require("inkdoku_logic")
local SudokuScreen = require("inkdoku_screen")

local SETTINGS_FILE = "inkdoku.lua"
local SETTINGS_KEY = "game"

local Sudoku = WidgetContainer:extend{
    name = "inkdoku",
    is_doc_only = false,
}

function Sudoku:init()
    math.randomseed(os.time())
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/" .. SETTINGS_FILE)
    self.ui.menu:registerToMainMenu(self)
end

function Sudoku:addToMainMenu(menu_items)
    menu_items[self.name] = {
        text = _("Sudoku"),
        sorting_hint = "tools",
        callback = function() self:showGame() end,
    }
end

function Sudoku:saveGame()
    if not (self.game and self.game.entries) then return end
    self.settings:saveSetting(SETTINGS_KEY, self.game:serialize())
    self.settings:flush()
end

function Sudoku:showGame()
    if self.screen then return end

    -- Luôn nạp lại từ file: đóng rồi mở lại cũng vào trạng thái tạm dừng như bản web
    local game = Game.new()
    if not game:load(self.settings:readSetting(SETTINGS_KEY)) then
        game:start("easy", Logic.generate("easy"))
    end
    self.game = game

    self.screen = SudokuScreen:new{ plugin = self, game = game }
    UIManager:show(self.screen, "full")

    if game.won or game.lost then
        UIManager:nextTick(function() self.screen:showResultDialog() end)
    else
        self.screen:scheduleClock()
    end
end

function Sudoku:onScreenClosed()
    self.screen = nil
end

-- Đang chơi mà KOReader thoát hay máy sập nguồn thì vẫn còn ván
function Sudoku:onFlushSettings()
    if self.screen then self:saveGame() end
end

return Sudoku
