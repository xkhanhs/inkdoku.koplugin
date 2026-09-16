# Plugin KOReader

`sudoku.koplugin/` là bản Sudoku chạy trong KOReader, nhắm tới Kindle Basic 2022
(màn e-ink 6", 1072x1448, xám 16 mức, cảm ứng, không phím). Không dùng chung dòng
code nào với bản web; luật chơi và bố cục dịch từ `js/` sang Lua.

## Cài đặt

Chép nguyên thư mục vào `koreader/plugins/` trên máy rồi khởi động lại KOReader:

```bash
scp -P 2222 -r sudoku.koplugin root@"$(kindle-ip)":/mnt/us/koreader/plugins/
```

Đừng chép bằng Finder: macOS để lại file `._*` trên thẻ FAT32. Mục **Sudoku** nằm
trong menu công cụ (**More tools**). Trên ZenOS, plugin chép tay không tự vào
launcher (ZenOS chỉ tự thêm plugin cài qua ZenPM).

Tên plugin là tên thư mục (`sudoku`). Nếu máy đã có `omer-faruq/sudoku.koplugin`
thì lệnh trên chép đè lên plugin đó. Ván lưu ở `koreader/settings/sudoku.lua`,
khoá `game`, không đụng khoá `state` của plugin kia.

## Cấu trúc

| File | Vai trò |
|---|---|
| `main.lua` | Vỏ plugin: mục menu, nạp/lưu ván bằng `LuaSettings`, mở màn chơi |
| `sudoku_game.lua` | Trạng thái và luật chơi (dịch `js/state.js`, `js/ui-controller.js`) |
| `sudoku_logic.lua` | Solver bitmask chọn ô ít ứng viên trước, đếm nghiệm, sinh đề |
| `sudoku_bank.lua` | Chọn ngẫu nhiên một đề trong `puzzles/*.txt` |
| `sudoku_board.lua` | Widget bàn cờ vẽ lên BlitBuffer (dịch `js/board-render.js`) |
| `sudoku_screen.lua` | Bố cục, nút, number pad, modal, đồng hồ, chớp, khoá dọc |
| `icons/*.svg` | Icon lấy nguyên từ `index.html`, đổi `currentColor` thành đen |
| `puzzles/` | 300 đề mỗi mức khó nhất, nguồn public domain, xem `SOURCE.txt` |

Ba file đầu là Lua thuần, không phụ thuộc KOReader. Mọi module mang tiền tố
`sudoku_` và được require ngay khi nạp `main.lua`: pluginloader chỉ thêm thư mục
plugin vào `package.path` trong lúc `dofile(main.lua)`, và `package.loaded` dùng
chung cho mọi plugin nên tên trần như `state` dễ đụng nhau.

## Kiểm tra trên máy tính

```bash
luajit tools/koreader/test-logic.lua
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
  `tools/koreader/build-puzzle-bank.lua`.

Đây là chỗ khác bản web: `removeNumbers()` bên JS đục ô không kiểm tra, nên đề khó
có thể nhiều lời giải và người chơi điền một lời giải hợp lệ khác vẫn bị báo sai.

## Đánh đổi cho e-ink

**Màu thành mức xám.** Thứ tự ưu tiên nền ô giữ như `cellBackground()`:

| Vai trò | Web | KOReader |
|---|---|---|
| nền | `#fffdf9` | trắng |
| dấu cộng hàng/cột/khối | `#fff6e6` | `COLOR_GRAY_E` |
| ô cùng số | `#73bcb3` | `COLOR_GRAY_B` |
| ô đang chọn | `#18958f` | `COLOR_GRAY_5`, chữ trắng |
| ô sai | chữ `#E3A99B` | nền đen, chữ trắng |
| số đề bài / số mình điền | `#6B5A47` / `#18958f` | đen / `COLOR_GRAY_4` |
| ghi chú | `#6B5A47` | `COLOR_GRAY_6` |
| lưới mảnh / đậm | `#d4c4b0` / `#9d8b7a` | `COLOR_GRAY_9` / đen |

Ô sai luôn nền đen, không chỉ khi đang chọn: chữ đỏ nhạt của web không có mức xám
nào phân biệt được với số thường.

**Sóng loang thành một cú chớp.** Màn e-ink không chạy được hoạt ảnh. Hàng, cột,
khối vừa xong vẽ nền đen chữ trắng rồi refresh `"fast"` đúng vùng đó, sau 0.15 giây
vẽ lại bình thường với `"fast"`, rồi một lần `"ui"` trả lại các mức xám (`"fast"`
chỉ có đen trắng). Thắng thì chớp cả bàn rồi mới hiện modal. Các pha phải cách nhau
bằng `UIManager:scheduleIn`: `setDirty` gọi liên tiếp trong cùng một tick bị
UIManager gộp thành một lần refresh và mất nhịp chớp.

**Đồng hồ vẽ lại mỗi phút.** Mỗi lần cập nhật là một lần refresh vùng, mỗi giây một
lần thì hao pin và nháy màn. Thời gian vẫn tính tới giây từ `os.time()`; khi đang
chạy chỉ hiện số phút, tạm dừng, thua hoặc thắng thì hiện `mm:ss`.

**Vẽ thẳng lên màn hình.** Chạm ô chỉ vẽ lại bàn cờ bằng `UIManager:widgetRepaint`
rồi refresh đúng vùng của nó, không vẽ lại cả màn. Nếu có hộp thoại đè lên thì để
UIManager vẽ lại cả chồng cửa sổ.

**Luôn dọc.** Mở màn chơi thì xoay về `DEVICE_ROTATED_UPRIGHT` nếu đang ở hướng
khác, nuốt sự kiện `SetRotationMode` trong lúc chơi, đóng thì trả lại hướng cũ và
refresh toàn màn. Mẫu lấy từ `frontend/ui/screensaver.lua`.

## Khác bản web

- Không có bàn phím vật lý. Có thêm nút đóng ở top menu.
- Máy đi ngủ giữa ván thì tự tạm dừng (thay cho `visibilitychange`).
- Ô gợi ý bị khoá như ô điền đúng và cũng kích hoạt chớp khi hoàn thành vùng.
- Trạng thái thua/thắng được lưu: mở lại ván đã thua vẫn hiện modal thua, không
  chơi tiếp được như bản web.
- Modal chọn độ khó xếp hai cột theo độ khó tăng dần.
