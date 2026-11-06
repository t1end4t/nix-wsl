# Công cụ hỗ trợ Windows 10 bản rút gọn

Các script được chia theo công dụng. Bộ cài, chương trình đã giải nén và dữ liệu
trung gian được gom vào `archives/original-files.zip` để giảm số file hiển thị.
Toàn bộ file trước khi sắp xếp lại được giữ nguyên trong ZIP, kể cả README và
`inventory.csv` cũ. Đã kiểm tra SHA-256 từng file trong ZIP so với bản trước refactor.

| Vị trí | Nội dung |
| --- | --- |
| `scripts/diagnostics/` | Kiểm tra Store/AppX, tiến độ DISM và phần cứng nâng cấp |
| `scripts/shell/` | Thiết lập PowerShell, Windows Terminal, PATH, shortcut và profile |
| `scripts/capture/` | Chẩn đoán chụp màn hình/clipboard, khởi động lại shell và thử chụp |
| `scripts/package-tools/` | Phân tích MSIX/manifest ChatGPT và dữ liệu ZIP cũ |
| `archives/original-files.zip` | Bộ file gốc, gồm PowerShell 7.4.13 x64, Terminal/VCLibs, ChatGPT MSIX và nhật ký |
| `Restore-Payload.ps1` | Giải nén dữ liệu khi cần dùng các bộ cài/chương trình |

## Sử dụng

Mở PowerShell tại thư mục này. Ví dụ kiểm tra Store:

```powershell
.\scripts\diagnostics\inspect-store.ps1
```

Trước khi dùng các script cần bộ cài hoặc chương trình đi kèm, giải nén một lần:

```powershell
.\Restore-Payload.ps1
```

Dữ liệu được giải nén vào `payload/`. Các script đã được cập nhật để tìm file ở đó,
không phụ thuộc thư mục đang đứng. Lệnh giải nén không chạy sửa chữa và từ chối ghi
đè khi `payload/` đã tồn tại. Các script cũ trong `payload/` chỉ là bản lưu lịch sử;
dùng các bản đã tổ chức trong `scripts/`.

## Tác động của các script

- `install-shell.ps1` và `finish-terminal.ps1` thay đổi PATH/shortcut của tài khoản.
  `fix-terminal-profile.ps1` sửa profile Terminal và sao lưu cấu hình trước khi ghi.
  Giữ `payload/` tại chỗ sau khi tạo các đường dẫn này.
- `restart-capture-*.ps1` dừng shell hoặc Explorer.
- `test-image-clipboard.ps1` ghi đè clipboard; `verify-screenclip.ps1` điều khiển
  phím/chuột để chụp một vùng màn hình. Các script clipboard cần phiên tương tác
  và chế độ STA.
- Các script dùng đường dẫn ShellExperienceHost khác nhau; kiểm tra đường dẫn
  thực tế trước khi chạy. AppX phụ thuộc thành phần còn lại của Windows và bản PowerShell.
- Đây là các công cụ và bước xử lý đã lưu, chưa phải bộ khôi phục Windows tự động.
  Không có nguồn cài Windows hay bộ khôi phục Store/Snipping Tool hoàn chỉnh.

ZIP và `payload/` được bỏ qua trong Git. Nếu chuyển bộ công cụ sang máy khác,
cần sao chép cả ZIP; Git clone riêng không chứa bộ cài. File gốc tại Documents
vẫn được giữ nguyên. Chưa chạy script sửa hệ thống, commit hoặc đẩy GitHub.
