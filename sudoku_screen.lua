-- ==================== MÀN CHƠI ====================
-- Bố cục dọc như bản mobile: top menu → stats bar → bàn cờ → 5 nút → number pad.
-- Dịch phần điều khiển của js/ui-controller.js và script.js; luật chơi nằm ở
-- sudoku_game.lua, màn này chỉ gọi luật rồi vẽ lại đúng phần vừa đổi.
--
-- Đánh đổi cho e-ink (chi tiết: docs/koreader-plugin.md):
--   * Sóng loang thành khung viền quanh vùng vừa xong, giữ tới lần chạm kế tiếp.
--   * Bàn cờ chỉ refresh vùng các ô vừa đổi.
--   * Đồng hồ vẫn đếm giây trong bộ nhớ nhưng chỉ vẽ lại mỗi phút.
--   * Luôn dọc: xoay về dọc khi mở, trả lại hướng cũ khi đóng.

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local RenderText = require("ui/rendertext")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")

local Bank = require("sudoku_bank")
local Board = require("sudoku_board")
local Game = require("sudoku_game")
local Logic = require("sudoku_logic")

local Screen = Device.screen

local DIFFICULTY_LABELS = {
    easy = "Dễ",
    medium = "Trung bình",
    hard = "Khó",
    expert = "Chuyên gia",
    master = "Thành thạo",
    extreme = "Cao thủ",
}

-- Thứ tự khó tăng dần theo cột, hai cột như modal bản web
local DIFFICULTY_ROWS = {
    { "easy", "expert" },
    { "medium", "master" },
    { "hard", "extreme" },
}

local function faceForPixels(name, pixels)
    local scale = Screen:scaleBySize(1000) / 1000
    return Font:getFace(name, math.max(6, math.floor(pixels / scale)))
end

local function formatClock(seconds)
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- ==================== WIDGET NHỎ ====================

-- Ô chữ có thể bấm: nhãn, nút "Game mới", phím số
local Label = InputContainer:extend{
    width = nil,
    height = nil,
    text = "",
    face = nil,
    color = Blitbuffer.COLOR_BLACK,
    align = "center",
    inset = 0,        -- lề trái/phải của chữ
    background = nil, -- nền bo góc, cho nút
    callback = nil,
}

function Label:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    if self.callback then
        self.ges_events = {
            TapLabel = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        }
    end
end

function Label:getSize()
    return self.dimen
end

function Label:onTapLabel()
    self.callback()
    return true
end

function Label:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)

    local metrics = RenderText:sizeUtf8Text(0, self.width, self.face, self.text, true, false)
    local text_w = metrics.x
    local text_h = metrics.y_top + metrics.y_bottom

    if self.background then
        local pad_x = math.floor(self.height * 0.35)
        local box_w = math.min(self.width, text_w + 2 * pad_x)
        local box_h = math.floor(self.height * 0.72)
        local box_x = x + math.floor((self.width - box_w) / 2)
        local box_y = y + math.floor((self.height - box_h) / 2)
        bb:paintRoundedRect(box_x, box_y, box_w, box_h, self.background, math.floor(box_h * 0.15))
        RenderText:renderUtf8Text(bb, box_x + math.floor((box_w - text_w) / 2),
            box_y + math.floor((box_h + metrics.y_top - metrics.y_bottom) / 2),
            self.face, self.text, true, false, self.color)
        return
    end

    local text_x
    if self.align == "left" then
        text_x = x + self.inset
    elseif self.align == "right" then
        text_x = x + self.width - self.inset - text_w
    else
        text_x = x + math.floor((self.width - text_w) / 2)
    end
    local baseline = y + math.floor((self.height - text_h) / 2) + metrics.y_top
    RenderText:renderUtf8Text(bb, text_x, baseline, self.face, self.text, true, false, self.color)
end

-- Nút icon SVG kèm badge tuỳ chọn (ON/OFF của pencil, số lượt gợi ý)
local IconButton = InputContainer:extend{
    width = nil,
    height = nil,
    icon_size = nil,
    file = nil,        -- đường dẫn SVG trong plugin
    icon = nil,        -- hoặc tên icon có sẵn của KOReader
    badge = nil,       -- chữ trong badge, nil là không có badge
    badge_active = false,
    badge_face = nil,
    callback = nil,
}

function IconButton:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self:setIcon(self.file, self.icon)
    self.ges_events = {
        TapIcon = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function IconButton:setIcon(file, icon)
    if self[1] then self[1]:free() end
    self.file, self.icon = file, icon
    self[1] = IconWidget:new{
        file = file,
        icon = icon,
        width = self.icon_size,
        height = self.icon_size,
    }
end

function IconButton:getSize()
    return self.dimen
end

function IconButton:onTapIcon()
    self.callback()
    return true
end

function IconButton:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)

    local icon_x = x + math.floor((self.width - self.icon_size) / 2)
    local icon_y = y + math.floor((self.height - self.icon_size) / 2)
    self[1]:paintTo(bb, icon_x, icon_y)

    if not self.badge then return end

    local face = self.badge_face
    local metrics = RenderText:sizeUtf8Text(0, self.width, face, self.badge, true, false)
    local badge_h = math.floor(self.icon_size * 0.46)
    local badge_w = math.max(badge_h, metrics.x + math.floor(badge_h * 0.6))
    local badge_x = math.min(x + self.width - badge_w, icon_x + math.floor(self.icon_size * 0.62))
    local badge_y = icon_y - math.floor(badge_h * 0.35)
    local fill = self.badge_active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY_D
    local text_color = self.badge_active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK

    bb:paintRoundedRect(badge_x, badge_y, badge_w, badge_h, fill, math.floor(badge_h / 2))
    RenderText:renderUtf8Text(bb, badge_x + math.floor((badge_w - metrics.x) / 2),
        badge_y + math.floor((badge_h + metrics.y_top - metrics.y_bottom) / 2),
        face, self.badge, true, false, text_color)
end

-- ==================== MÀN CHƠI ====================

local SudokuScreen = InputContainer:extend{
    name = "sudoku_screen",
    covers_fullscreen = true,
    plugin = nil,
    game = nil,
}

function SudokuScreen:init()
    self:lockPortrait()

    self.icons_dir = self.plugin.path .. "/icons"
    self.puzzles_dir = self.plugin.path .. "/puzzles"
    self.clock_tick = function() self:onClockTick() end

    self:buildLayout()

    self.ges_events = {
        SwipeScreen = {
            GestureRange:new{ ges = "swipe", range = function() return self.dimen end },
        },
    }
end

-- Vuốt xuống từ mép trên mở menu nhanh như ngoài file manager (ZenOS: bật tắt
-- Wi-Fi, đèn...). Màn chơi phủ toàn màn hình nên phải tự chuyển cử chỉ này đi.
function SudokuScreen:onSwipeScreen(_, ges)
    if ges.direction ~= "south" or ges.pos.y > Screen:getHeight() * 0.14 then return true end

    local zen_swipe = package.loaded["modules/global/patches/menu_top_swipe"]
    if zen_swipe and zen_swipe.handleSwipe then
        zen_swipe.handleSwipe(ges)
        return true
    end

    local FileManager = package.loaded["apps/filemanager/filemanager"]
    local menu = FileManager and FileManager.instance and FileManager.instance.menu
    if menu and menu.onShowMenu then menu:onShowMenu() end
    return true
end

-- ==================== KHOÁ DỌC ====================
-- Mẫu của frontend/ui/screensaver.lua + screensaverwidget.lua

function SudokuScreen:lockPortrait()
    local mode = Screen:getRotationMode()
    if mode ~= Screen.DEVICE_ROTATED_UPRIGHT then
        self.orig_rotation_mode = mode
        Screen:setRotationMode(Screen.DEVICE_ROTATED_UPRIGHT)
    end
end

-- Nuốt sự kiện xoay khi đang chơi
function SudokuScreen:onSetRotationMode()
    return true
end

function SudokuScreen:onCloseWidget()
    self.closed = true
    UIManager:unschedule(self.clock_tick)
    self.plugin:saveGame()

    if self.orig_rotation_mode then
        Screen:setRotationMode(self.orig_rotation_mode)
        self.orig_rotation_mode = nil
    end
    UIManager:setDirty(nil, "full")
    self.plugin:onScreenClosed()
end

-- Máy đi ngủ giữa ván thì tạm dừng, như visibilitychange bên web
function SudokuScreen:onSuspend()
    if self.game:pause() then
        self:syncControls()
        UIManager:unschedule(self.clock_tick)
        self.plugin:saveGame()
        UIManager:setDirty(self)
    end
end

-- ==================== BỐ CỤC ====================

function SudokuScreen:buildLayout()
    local width, height = Screen:getWidth(), Screen:getHeight()
    local side = math.floor(width * 0.03)
    local inner = width - 2 * side

    local top_h = math.floor(height * 0.06)
    local stats_h = math.floor(height * 0.045)
    local action_h = math.floor(height * 0.085)
    local pad_h = math.floor(height * 0.085)
    local gap = math.floor(height * 0.01)
    local line_h = math.max(1, math.floor(height / 700))

    local board_size = math.min(inner,
        height - top_h - line_h - stats_h - action_h - pad_h - 3 * gap)

    local title_face = faceForPixels("tfont", top_h * 0.5)
    local button_face = faceForPixels("cfont", top_h * 0.34)
    local stats_face = faceForPixels("cfont", stats_h * 0.5)
    local digit_face = faceForPixels("cfont", pad_h * 0.55)
    local badge_face = faceForPixels("tfont", action_h * 0.17)

    -- Top menu: tên bên trái, "Game mới" ở giữa, nút đóng bên phải
    local close_w = top_h
    local new_game_w = math.floor(inner * 0.34)
    local title_w = math.floor((inner - new_game_w) / 2)
    self.close_button = IconButton:new{
        width = close_w, height = top_h, icon_size = math.floor(top_h * 0.6),
        icon = "close",
        callback = function() UIManager:close(self) end,
    }
    local top_bar = HorizontalGroup:new{
        Label:new{
            width = title_w, height = top_h,
            text = "Sudoku", face = title_face, align = "left",
        },
        Label:new{
            width = new_game_w, height = top_h,
            text = "Game mới", face = button_face,
            background = Blitbuffer.COLOR_BLACK, color = Blitbuffer.COLOR_WHITE,
            callback = function() self:showDifficultyDialog() end,
        },
        Label:new{ width = inner - title_w - new_game_w - close_w, height = top_h, face = button_face },
        self.close_button,
    }

    -- Stats bar: Sai bên trái, độ khó ở giữa, thời gian bên phải
    local stat_w = math.floor(inner / 3)
    self.mistakes_label = Label:new{
        width = stat_w, height = stats_h, face = stats_face, align = "left",
    }
    self.difficulty_label = Label:new{
        width = inner - 2 * stat_w, height = stats_h, face = stats_face,
    }
    self.clock_label = Label:new{
        width = stat_w, height = stats_h, face = stats_face, align = "right",
    }

    self.board = Board:new{
        game = self.game,
        size = board_size,
        icons_dir = self.icons_dir,
        on_tap = function(row, col) self:onCellTap(row, col) end,
    }

    -- Hàng nút chức năng
    local action_w = math.floor(inner / 5)
    local icon_size = math.floor(action_h * 0.5)
    local function actionButton(name, callback)
        return IconButton:new{
            width = action_w, height = action_h, icon_size = icon_size,
            file = self.icons_dir .. "/" .. name .. ".svg",
            badge_face = badge_face,
            callback = callback,
        }
    end
    self.pause_button = actionButton("pause", function() self:onTogglePause() end)
    self.pencil_button = actionButton("pencil", function() self:onTogglePencil() end)
    self.hint_button = actionButton("hint", function() self:onHint() end)
    local actions = HorizontalGroup:new{
        actionButton("undo", function() self:onUndo() end),
        actionButton("clear", function() self:onClear() end),
        self.pause_button,
        self.pencil_button,
        self.hint_button,
    }

    -- Number pad 9 nút ngang
    local digit_w = math.floor(inner / 9)
    local pad = HorizontalGroup:new{}
    for num = 1, 9 do
        pad[num] = Label:new{
            width = digit_w, height = pad_h,
            text = tostring(num), face = digit_face,
            callback = function() self:onDigit(num) end,
        }
    end

    local used = top_h + line_h + stats_h + gap + board_size + gap + action_h + pad_h
    self.layout = VerticalGroup:new{
        align = "center",
        top_bar,
        LineWidget:new{
            background = Blitbuffer.COLOR_GRAY_D,
            dimen = Geom:new{ w = width, h = line_h },
        },
        HorizontalGroup:new{ self.mistakes_label, self.difficulty_label, self.clock_label },
        VerticalSpan:new{ width = gap },
        self.board,
        VerticalSpan:new{ width = gap },
        actions,
        pad,
        VerticalSpan:new{ width = math.max(0, height - used) },
    }

    self.dimen = Geom:new{ x = 0, y = 0, w = width, h = height }
    self[1] = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        self.layout,
    }

    self:syncControls()
end

-- Đưa chữ và badge về khớp trạng thái ván (không vẽ)
function SudokuScreen:syncControls()
    local game = self.game
    self.mistakes_label.text = string.format("Sai: %d/%d", game.mistakes, Game.MAX_MISTAKES)
    self.difficulty_label.text = DIFFICULTY_LABELS[game.difficulty] or ""

    -- Đang chạy thì chỉ hiện phút, vì chỉ vẽ lại mỗi phút; dừng lại thì hiện tới giây
    local seconds = game:seconds()
    if game:canPlay() then
        self.clock_label.text = string.format("%d phút", math.floor(seconds / 60))
    else
        self.clock_label.text = formatClock(seconds)
    end

    local pause_icon = game:isHidden() and "play" or "pause"
    if not self.pause_button.file:find(pause_icon .. ".svg", 1, true) then
        self.pause_button:setIcon(self.icons_dir .. "/" .. pause_icon .. ".svg")
    end

    self.pencil_button.badge = game.pencil and "ON" or "OFF"
    self.pencil_button.badge_active = game.pencil
    self.hint_button.badge = tostring(game.hints)
    self.hint_button.badge_active = game.hints > 0
end

-- ==================== VẼ LẠI ====================

-- Vẽ riêng một widget con lên màn hình rồi refresh đúng vùng của nó. Có hộp thoại
-- đang đè lên thì để UIManager vẽ lại cả chồng cửa sổ cho đúng thứ tự.
function SudokuScreen:repaint(widget, mode, rect)
    if self.closed then return end
    rect = rect or widget.dimen
    if UIManager:getTopmostVisibleWidget() == self then
        UIManager:widgetRepaint(widget, widget.dimen.x, widget.dimen.y)
        UIManager:setDirty(nil, mode or "ui", rect)
    else
        UIManager:setDirty(self, mode or "ui", rect)
    end
end

-- Bàn cờ chỉ refresh vùng bao các ô trông khác đi
function SudokuScreen:repaintBoard()
    local rect = self.board:changedRect()
    if rect then self:repaint(self.board, "ui", rect) end
end

function SudokuScreen:repaintControls()
    self:syncControls()
    for _, widget in ipairs({ self.mistakes_label, self.clock_label, self.difficulty_label,
            self.pause_button, self.pencil_button, self.hint_button }) do
        self:repaint(widget, "ui")
    end
end

function SudokuScreen:repaintAll()
    self:syncControls()
    UIManager:setDirty(self, "ui")
end

-- ==================== ĐỒNG HỒ ====================

-- Hẹn lần vẽ tiếp theo đúng lúc số phút đổi
function SudokuScreen:scheduleClock()
    UIManager:unschedule(self.clock_tick)
    if self.closed or not self.game:canPlay() then return end
    local delay = 60 - self.game:seconds() % 60
    UIManager:scheduleIn(delay, self.clock_tick)
end

function SudokuScreen:onClockTick()
    self:syncControls()
    self:repaint(self.clock_label, "ui")
    self:scheduleClock()
end

-- ==================== THAO TÁC ====================

-- Khung vùng vừa xong chỉ sống tới lần chạm kế tiếp, chạm ở đâu cũng vậy.
-- Gỡ khung trước khi chuyển chạm cho nút con, rồi vẽ lại nếu thao tác đó không vẽ.
function SudokuScreen:handleEvent(event)
    local ges = event.handler == "onGesture" and event.args[1]
    local had_frames = ges and ges.ges == "tap" and self.board.frames ~= nil
    if had_frames then self.board.frames = nil end

    local handled = InputContainer.handleEvent(self, event)

    if had_frames and not self.closed then self:repaintBoard() end
    return handled
end

function SudokuScreen:onCellTap(row, col)
    local game = self.game
    if game.lost then
        self:showResultDialog()
        return
    end
    if game.won then return end

    -- Bàn cờ đang che thì chạm vào là chơi tiếp, như nút play trên overlay web
    if game:isHidden() then
        self:onTogglePause()
        return
    end

    game:select(row, col)
    self:repaintBoard()
end

-- Kết quả từ Game:input() / Game:hint()
function SudokuScreen:applyResult(result)
    if result.regions and #result.regions > 0 then
        self.board.frames = result.regions
    end
    self:repaintBoard()
    self:syncControls()
    self:repaint(self.mistakes_label, "ui")
    self:repaint(self.hint_button, "ui")
    self.plugin:saveGame()

    if result.kind == "lost" then
        UIManager:unschedule(self.clock_tick)
        self:repaint(self.clock_label, "ui")
        UIManager:nextTick(function() self:showResultDialog() end)
    elseif result.kind == "won" then
        UIManager:unschedule(self.clock_tick)
        self:repaint(self.clock_label, "ui")
        UIManager:nextTick(function() self:showResultDialog() end)
    end
end

function SudokuScreen:onDigit(num)
    if self.game.lost then
        self:showResultDialog()
        return
    end
    local result = self.game:input(num)
    if result then self:applyResult(result) end
end

function SudokuScreen:onHint()
    local result = self.game:hint()
    if result then self:applyResult(result) end
end

function SudokuScreen:onUndo()
    if self.game:undo() then
        self:repaintBoard()
        self.plugin:saveGame()
    end
end

function SudokuScreen:onClear()
    if self.game:clear() then
        self:repaintBoard()
        self.plugin:saveGame()
    end
end

function SudokuScreen:onTogglePencil()
    self.game:togglePencil()
    self:syncControls()
    self:repaint(self.pencil_button, "ui")
end

function SudokuScreen:onTogglePause()
    local game = self.game
    local changed
    if game:isHidden() then
        changed = game:resume()
    else
        changed = game:pause()
    end
    if not changed then return end

    self:syncControls()
    self:repaintBoard()
    self:repaint(self.pause_button, "ui")
    self:repaint(self.clock_label, "ui")
    self:scheduleClock()
    self.plugin:saveGame()
end

-- ==================== VÁN MỚI, CHƠI LẠI ====================

function SudokuScreen:startGame(difficulty)
    local puzzle, solution
    if Bank.LEVELS[difficulty] then
        puzzle, solution = Bank.pick(self.puzzles_dir, difficulty)
        if not puzzle then
            logger.warn("Sudoku: không đọc được đề đóng gói", difficulty, "- tự sinh mức Khó thay thế")
            puzzle, solution = Logic.generate("hard")
        end
    else
        local started = os.clock()
        puzzle, solution = Logic.generate(difficulty)
        logger.info("Sudoku: sinh đề", difficulty, string.format("%.0f ms", (os.clock() - started) * 1000))
    end

    self.board.frames = nil
    self.game:start(difficulty, puzzle, solution)
    self.plugin:saveGame()
    self:repaintAll()
    self:scheduleClock()
end

function SudokuScreen:retryGame()
    self.board.frames = nil
    self.game:retry()
    self.plugin:saveGame()
    self:repaintAll()
    self:scheduleClock()
end

function SudokuScreen:showDifficultyDialog()
    local dialog
    local buttons = {}
    for _, pair in ipairs(DIFFICULTY_ROWS) do
        local row = {}
        for _, difficulty in ipairs(pair) do
            row[#row + 1] = {
                text = DIFFICULTY_LABELS[difficulty],
                callback = function()
                    UIManager:close(dialog)
                    self:startGame(difficulty)
                end,
            }
        end
        buttons[#buttons + 1] = row
    end

    dialog = ButtonDialog:new{
        title = "Chọn độ khó",
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(dialog)
end

-- Modal thắng/thua, dùng chung hai nút Chơi lại / Ván mới như bản web
function SudokuScreen:showResultDialog()
    local game = self.game
    local title
    if game.won then
        local seconds = game:seconds()
        title = string.format("Xin chúc mừng!\nBạn đã hoàn thành thử thách trong %d:%02d!",
            math.floor(seconds / 60), seconds % 60)
    elseif game.lost then
        title = string.format("Thua rồi\nBạn đã sai %d lần. Thử lại nhé!", Game.MAX_MISTAKES)
    else
        return
    end

    local dialog
    dialog = ButtonDialog:new{
        title = title,
        title_align = "center",
        -- Thua thì bắt buộc chọn, như bản web không cho đóng modal bằng chạm ra ngoài
        dismissable = game.won,
        buttons = {
            {
                {
                    text = "Chơi lại",
                    callback = function()
                        UIManager:close(dialog)
                        self:retryGame()
                    end,
                },
                {
                    text = "Ván mới",
                    callback = function()
                        UIManager:close(dialog)
                        self:showDifficultyDialog()
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

return SudokuScreen
