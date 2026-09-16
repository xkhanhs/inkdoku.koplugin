# Inkdoku

A Sudoku plugin for [KOReader](https://github.com/koreader/koreader), built for
e-ink touch screens. Made for the Kindle Basic 2022 (6", 16 grey levels, touch)
and works on any KOReader device with a touch screen.

[Tiếng Việt](#tiếng-việt) bên dưới.

## Features

- 6 difficulty levels. Easy, Medium and Hard are generated on the device, and each
  puzzle is checked to have exactly one solution. Expert, Master and Extreme come
  from 900 bundled puzzles rated with Sukaku Explainer.
- Pencil notes, undo, erase, 3 hints. Three mistakes and the game is over.
- A correct entry locks the cell and removes that digit from the notes in its row,
  column and box.
- A digit placed in all 9 cells is dimmed on the number pad.
- Cells with the same digit as the selected cell get a thin outline. A finished
  row, column or box is framed for 1.5 seconds.
- Autosave, auto-pause when the device sleeps, portrait lock while playing.
- Built to flicker less: tapping a cell only refreshes the cells that changed, and
  the clock redraws once a minute.
- English and Vietnamese. The plugin follows KOReader's language
  (**Settings → Language**): Vietnamese shows Vietnamese, any other language shows
  English.

## Install

1. Download this repo (**Code → Download ZIP** or `git clone`) and name the folder
   `inkdoku.koplugin`.
2. Copy that folder into `koreader/plugins/` on your device.
3. Restart KOReader. **Sudoku** appears in the tools menu (**More tools**).

When copying from macOS, Finder leaves `._*` files on FAT32 storage. Use `scp` or
`rsync` instead.

Inkdoku can be installed next to
[omer-faruq/sudoku.koplugin](https://github.com/omer-faruq/sudoku.koplugin): the
plugin name, module names and save file (`koreader/settings/inkdoku.lua`) are all
different.

## Development

Game rules and puzzle generation are plain Lua and can be tested with LuaJIT on a
computer:

```bash
luajit tools/test-logic.lua
```

Layout, e-ink trade-offs and differences from the web version are described (in
Vietnamese) in [docs/design.md](docs/design.md).

## Credits

- Rules and interface are ported from the web version
  [xkhanhs/sudoku](https://github.com/xkhanhs/sudoku).
- Bundled puzzles come from
  [grantm/sudoku-exchange-puzzle-bank](https://github.com/grantm/sudoku-exchange-puzzle-bank)
  (public domain), see [puzzles/SOURCE.txt](puzzles/SOURCE.txt).
- The ideas for auto-removing notes and dimming finished digits come from forks of
  omer-faruq/sudoku.koplugin by [jan-herz](https://github.com/jan-herz/sudoku.koplugin)
  and [appel](https://github.com/appel/sudoku.koplugin). The code is written from
  scratch.

## License

[GPL-3.0](LICENSE)

---

## Tiếng Việt

Plugin Sudoku cho KOReader, làm riêng cho màn e-ink cảm ứng. Viết cho Kindle Basic
2022 nhưng chạy được trên mọi máy KOReader có màn cảm ứng.

**Tính năng:** 6 mức khó (3 mức tự sinh trên máy, đề nào cũng đúng một nghiệm; 3
mức khó nhất lấy từ 900 đề đóng gói), ghi chú, undo, xoá ô, 3 lượt gợi ý, sai 3 lần
là thua. Điền đúng thì ô bị khoá và ghi chú số đó ở cùng hàng, cột, khối tự xoá. Số
đã đủ 9 ô thì phím số mờ đi. Tự lưu ván, tự tạm dừng khi máy ngủ, giữ màn dọc lúc
chơi.

**Ngôn ngữ:** plugin theo ngôn ngữ của KOReader (**Settings → Language**). Chọn
Tiếng Việt thì giao diện tiếng Việt, ngôn ngữ khác thì tiếng Anh. Đổi xong khởi động
lại KOReader.

**Cài đặt:** tải repo về, đặt tên thư mục là `inkdoku.koplugin`, chép vào
`koreader/plugins/` rồi khởi động lại KOReader. Mục **Sudoku** nằm trong menu công
cụ (**More tools**). Cài song song được với plugin Sudoku của omer-faruq.

Chi tiết thiết kế và các đánh đổi cho e-ink: [docs/design.md](docs/design.md).
