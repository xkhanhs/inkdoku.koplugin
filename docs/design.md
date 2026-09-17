# Thiết kế

Inkdoku là bản Sudoku chạy trong KOReader, nhắm tới Kindle Basic 2022
(màn e-ink 6", 1072x1448, xám 16 mức, cảm ứng, không phím). Không dùng chung dòng
code nào với [bản web](https://github.com/xkhanhs/sudoku); luật chơi và bố cục dịch
từ `js/` của repo đó sang Lua.

## Cài đặt

Chép nguyên thư mục vào `koreader/plugins/` trên máy rồi khởi động lại KOReader:

```bash
scp -P 2222 -r inkdoku.koplugin root@"$(kindle-ip)":/mnt/us/koreader/plugins/
```

Đừng chép bằng Finder: macOS để lại file `._*` trên thẻ FAT32. Với menu gốc của
KOReader, mục **Sudoku** nằm trong **More tools**. ZenOS thay menu đó bằng menu
Settings riêng và chỉ tự thêm vào launcher những plugin cài qua ZenPM; plugin chép
tay phải thêm bằng Settings → **Launcher** → **Add plugin** → **Sudoku**.

Tên plugin là tên thư mục (`inkdoku`), nên cài song song được với
`omer-faruq/sudoku.koplugin`. Ván lưu ở `koreader/settings/inkdoku.lua`, khoá `game`; giới hạn sai ở khoá `max_mistakes`.

Chụp màn hình qua SSH để kiểm tra mà không cần người cầm máy: đọc 1072x1448 byte
đầu của `/dev/fb0` (8 bit xám) rồi đổi sang PNG. Ảnh đọc từ bộ nhớ đệm nên có thể còn
vết thanh trạng thái ZenOS không hiện trên màn thật.

## Cấu trúc

| File | Vai trò |
|---|---|
| `main.lua` | Vỏ plugin: mục menu, nạp/lưu ván bằng `LuaSettings`, mở màn chơi |
| `inkdoku_game.lua` | Trạng thái và luật chơi (dịch `js/state.js`, `js/ui-controller.js`) |
| `inkdoku_logic.lua` | Solver bitmask chọn ô ít ứng viên trước, đếm nghiệm, sinh đề |
| `inkdoku_bank.lua` | Chọn ngẫu nhiên một đề trong `puzzles/*.txt` |
| `inkdoku_board.lua` | Widget bàn cờ vẽ lên BlitBuffer (dịch `js/board-render.js`) |
| `inkdoku_screen.lua` | Bố cục, nút, number pad, modal, đồng hồ, chớp, khoá dọc |
| `inkdoku_i18n.lua` | Chuỗi giao diện tiếng Anh và tiếng Việt, chọn theo ngôn ngữ của KOReader |
| `icons/*.svg` | Icon lấy nguyên từ `index.html`, đổi `currentColor` thành đen |
| `puzzles/` | 300 đề mỗi mức khó nhất, nguồn public domain, xem `SOURCE.txt` |

`inkdoku_game`, `inkdoku_logic`, `inkdoku_bank`, `inkdoku_i18n` là Lua thuần, không phụ thuộc KOReader. Mọi module mang tiền tố
`inkdoku_` và được require ngay khi nạp `main.lua`: pluginloader chỉ thêm thư mục
plugin vào `package.path` trong lúc `dofile(main.lua)`, và `package.loaded` dùng
chung cho mọi plugin nên tên trần như `state`, hay `sudoku_bank` của plugin
omer-faruq, sẽ đụng nhau.

## Kiểm tra trên máy tính

```bash
luajit tools/test-logic.lua
```

Sinh 20 đề mỗi mức tự sinh và kiểm từng đề đúng một nghiệm, kiểm mọi đề đóng gói,
rồi chạy qua luật chơi: sai, khoá ô, ghi chú, undo, clear, gợi ý, thua, thắng,
đồng hồ, lưu và nạp. Phần giao diện chỉ kiểm được trên máy hoặc emulator KOReader.

## Sinh đề

- **Dễ / Trung bình / Khó** tự sinh: một lời giải ngẫu nhiên, rồi đục 31 / 41 / 51
  ô theo thứ tự ngẫu nhiên, mỗi ô đục đều đếm nghiệm (dừng ở 2) và trả lại ô nếu
  đề mất tính duy nhất. Trên Mac mất khoảng 1 ms mỗi đề mức Khó.
- **Chuyên gia / Thành thạo / Cao thủ** lấy từ `puzzles/`: rating Sukaku Explainer
  3.0–4.9, 5.0–6.9 và từ 7.0. Đục tham lam tới 17–25 ô gợi ý mà vẫn duy nhất
  thường không tới được, nên các mức này không tự sinh. Dựng lại bộ đề bằng
  `tools/build-puzzle-bank.lua`.

Đây là chỗ khác bản web: `removeNumbers()` bên JS đục ô không kiểm tra, nên đề khó
có thể nhiều lời giải và người chơi điền một lời giải hợp lệ khác vẫn bị báo sai.

## Đánh đổi cho e-ink

**Màu thành mức xám, chọn ô bằng viền thay vì tô nền.**

| Vai trò | Web | KOReader |
|---|---|---|
| nền | `#fffdf9` | trắng |
| dấu cộng hàng/cột/khối | nền `#fff6e6` | không có |
| ô đang chọn | nền `#18958f` | viền đen đậm |
| ô cùng số | nền `#73bcb3` | viền đen mảnh, bỏ cạnh trùng đường kẻ đậm |
| ô sai | chữ `#E3A99B` | nền đen, chữ trắng |
| số đề bài / số mình điền | `#6B5A47` / `#18958f` | đen / `COLOR_GRAY_5`, cùng nét thường |
| ghi chú | `#6B5A47` | `COLOR_GRAY_4` |
| lưới mảnh / đậm | `#d4c4b0` / `#9d8b7a` | `COLOR_GRAY_9` / đen |

Thử trên máy mới ra bảng này:

- **Tô nền xám làm nháy.** Refresh `"ui"` chạy qua đen rồi mới về mức xám. Chọn ô
  đổi nền cả chục ô trong dấu cộng, nên mỗi lần chạm cả hàng lẫn cột nháy đen. Viền
  chỉ đổi vài pixel nên gần như không thấy. Vì cùng lý do, ô cùng số dùng viền mảnh
  chứ không tô xám.
- **Viền căn giữa đường kẻ lưới** (`Board:paintCellBorder`). Vẽ lọt vào trong ô thì
  viền các ô ở hàng khác nhau lệch nhau và lệch khỏi lưới.
- **Ô sai luôn nền đen.** Chữ đỏ nhạt của web không có mức xám nào tách được khỏi số
  thường. Ô đang chọn vì thế không được tô nền đậm, nếu không ô vừa điền đúng (vẫn
  đang chọn) trông y hệt ô sai.
- **Số đề bài và số mình điền cùng nét thường**, chỉ khác màu (đen và `GRAY_5`).
  Bản trước in đậm số đề bài vì `GRAY_4` so với đen gần như không phân biệt được; khi
  font là Bookerly thì nét đậm trông quá nặng trong ô nên bỏ.

**Sóng loang thành khung viền.** Hàng, cột, khối vừa hoàn thành được đóng khung đen
đậm ngay trong lần refresh hiện số vừa điền, rồi tự gỡ sau 1.5 giây. Trong lúc có
khung, không viền ô cùng số để khỏi chồng nhiều khung. Không có hoạt ảnh nào: đã thử
một cú chớp đảo màu bằng refresh `"fast"`, nhưng `"fast"` chỉ có đen trắng nên các ô
xám trong vùng cũng nháy theo, trông như nháy cả mảng.

**Font để KOReader quyết định.** Chữ thường và số trên bàn cờ xin `cfont`, chữ đậm
(tiêu đề, badge) xin `tfont`; plugin không đóng gói font riêng. ZenOS ghi đè `Font.fontmap` bằng
font thư viện người dùng chọn (`modules/global/patches/menu_font.lua`), nên cả màn chơi,
kể cả số trên bàn cờ, hiện bằng font đó. Bản ZenOS nào còn tìm font đậm gốc qua `ffont`
thì không đổi được `tfont`, và tiêu đề, badge sẽ lệch font với phần còn lại. Số trong ô chiếm
72% cạnh ô.

**Modal trên nền trống.** Khi hiện modal thắng hay modal chọn độ khó, bàn cờ trắng
trơn, bỏ cả lưới, để viền modal không chồng lên đường kẻ. Tạm dừng thì còn lưới, nút
play ở giữa và nút "Giới hạn sai" ngay dưới (3 → 5 → không giới hạn). Cài đặt đặt ở
đây thay vì thêm icon lên hàng nút hay menu Tools: hàng nút đã chật, còn menu Tools
sẽ bắt thêm một lần chạm mỗi lần mở game.

**Đồng hồ vẽ lại mỗi phút.** Mỗi lần cập nhật là một lần refresh vùng, mỗi giây một
lần thì hao pin và nháy màn. Thời gian vẫn tính tới giây từ `os.time()`; khi đang
chạy chỉ hiện số phút, tạm dừng, thua hoặc thắng thì hiện `mm:ss`.

**Vẽ thẳng lên màn hình, refresh đúng vùng đổi.** Chạm ô vẽ lại bàn cờ bằng
`UIManager:widgetRepaint`, rồi chỉ refresh hình chữ nhật bao các ô trông khác lần
vẽ trước (`Board:changedRect`), nới thêm nửa bề dày viền. Nếu có hộp thoại đè lên
thì để UIManager vẽ lại cả chồng cửa sổ.

**Màu là cdata FFI.** So sánh một màu Blitbuffer với `nil` bằng `==` gọi `__eq` của
Blitbuffer và làm KOReader crash thoát hẳn. Đánh dấu kiểu ô bằng cờ boolean, không
so màu. Bản chạy thử trên máy tính dùng bảng Lua thay cho cdata nên không bắt được
lỗi này.

**Vuốt xuống mở menu nhanh.** Màn chơi phủ toàn màn hình nên nhận hết cử chỉ. Vuốt
xuống từ 14% trên cùng được chuyển cho `menu_top_swipe.handleSwipe` của ZenOS, hoặc
menu file manager nếu không có ZenOS.

**Luôn dọc.** Mở màn chơi thì xoay về `DEVICE_ROTATED_UPRIGHT` nếu đang ở hướng
khác, nuốt sự kiện `SetRotationMode` trong lúc chơi, đóng thì trả lại hướng cũ và
refresh toàn màn. Mẫu lấy từ `frontend/ui/screensaver.lua`.

## Khác bản web

- Không có bàn phím vật lý. Có thêm nút đóng ở top menu.
- Máy đi ngủ giữa ván thì tự tạm dừng (thay cho `visibilitychange`).
- Ô gợi ý bị khoá như ô điền đúng, và cũng đóng khung vùng nếu hoàn thành.
- Trạng thái thua/thắng được lưu: mở lại ván đã thua vẫn hiện modal thua, không
  chơi tiếp được như bản web.
- Modal chọn độ khó xếp hai cột theo độ khó tăng dần.
- Điền đúng (hoặc gợi ý) một số thì ghi chú số đó ở cùng hàng, cột, khối tự xoá.
- Số đã nằm đủ 9 ô khoá thì phím số mờ đi và bấm vào không làm gì, kể cả ở chế độ
  ghi chú.
