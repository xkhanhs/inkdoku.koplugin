-- ==================== NGÔN NGỮ ====================
-- Chữ trên giao diện theo ngôn ngữ đang chọn của KOReader (Settings → Language):
-- tiếng Việt thì hiện tiếng Việt, mọi ngôn ngữ khác hiện tiếng Anh. KOReader đổi
-- ngôn ngữ xong phải khởi động lại, nên chỉ cần đọc một lần lúc nạp plugin.
--
-- Không dùng gettext `_()`: catalog của KOReader không có chuỗi của plugin này.

local STRINGS = {
    en = {
        easy = "Easy",
        medium = "Medium",
        hard = "Hard",
        expert = "Expert",
        master = "Master",
        extreme = "Extreme",
        new_game = "New game",
        choose_difficulty = "Choose difficulty",
        mistakes = "Mistakes: %d/%d",
        mistakes_count = "Mistakes: %d",
        mistake_limit = "Mistake limit: %s",
        unlimited = "unlimited",
        minutes = "%d min",
        won = "Congratulations!\nYou solved it in %d:%02d!",
        lost = "Game over\nYou made %d mistakes. Try again!",
        retry = "Retry",
        another_game = "New game",
    },
    vi = {
        easy = "Dễ",
        medium = "Trung bình",
        hard = "Khó",
        expert = "Chuyên gia",
        master = "Thành thạo",
        extreme = "Cao thủ",
        new_game = "Game mới",
        choose_difficulty = "Chọn độ khó",
        mistakes = "Sai: %d/%d",
        mistakes_count = "Sai: %d",
        mistake_limit = "Giới hạn sai: %s",
        unlimited = "không giới hạn",
        minutes = "%d phút",
        won = "Xin chúc mừng!\nBạn đã hoàn thành thử thách trong %d:%02d!",
        lost = "Thua rồi\nBạn đã sai %d lần. Thử lại nhé!",
        retry = "Chơi lại",
        another_game = "Ván mới",
    },
}

local I18n = {}

-- "vi", "vi_VN" → "vi"; còn lại (kể cả "C" mặc định) → "en"
function I18n.pick(lang)
    if type(lang) == "string" and lang:match("^vi") then return "vi" end
    return "en"
end

function I18n.setLanguage(lang)
    I18n.lang = I18n.pick(lang)
end

-- Chuỗi theo khoá; có tham số thì format luôn
function I18n.t(key, ...)
    local text = STRINGS[I18n.lang][key] or STRINGS.en[key] or key
    if select("#", ...) > 0 then return string.format(text, ...) end
    return text
end

-- Ngoài KOReader (test trên máy tính) thì không có gettext, mặc định tiếng Anh
local ok, gettext = pcall(require, "gettext")
I18n.setLanguage(ok and type(gettext) == "table" and gettext.current_lang or nil)

-- Để test so khớp hai bảng có đủ khoá như nhau
I18n.STRINGS = STRINGS

return I18n
