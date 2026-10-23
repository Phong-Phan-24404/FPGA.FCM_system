# mem/ — thư mục runtime, không phải nguồn

05_Host_PC/fcm_image_uploader.py ghi `input_grayscale.mem` vào đây rồi System
Console đẩy nó lên board. Nội dung thay đổi theo mỗi lần push ảnh, nên file
`.mem` ở đây bị .gitignore bỏ qua.

Ảnh cố định dùng cho testbench KHÔNG nằm ở đây mà ở
`03_Verification/soc/fixtures/` — tách ra để nơi test đọc không phải là nơi
host tool ghi đè.
