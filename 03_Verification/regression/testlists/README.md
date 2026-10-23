# Testlists

Danh sách testbench của mỗi tier **không** nằm trong thư mục này. Nguồn duy
nhất là khoá `Tiers` trong hai file config:

| Tầng | File | Thư mục log |
| --- | --- | --- |
| IP | `07_Scripts/config/fcm_ip.psd1` | `07_Scripts/.build-fcm-ip/logs/` |
| SoC | `07_Scripts/config/project.psd1` | `07_Scripts/.build/logs/` |

Lý do: `Invoke-Sim.ps1` đọc `Tiers` trực tiếp từ `.psd1` để dựng cả fileset
compile lẫn danh sách top. Chép danh sách đó ra một file thứ hai ở đây sẽ tạo
ra hai nguồn sự thật, và cái sai sẽ là cái không ai chạy.

Thêm một testbench vào tier:

1. thêm file vào `TbSources` của config tương ứng, đúng thứ tự compile;
2. thêm tên module vào `Tiers.<tier>`;
3. nếu là UVM testbench, thêm `UvmTests.<tb> = '<uvm_test>'`;
4. thêm một dòng vào [`docs/test_traceability.md`](../../docs/test_traceability.md)
   nói nó kiểm requirement nào — không có dòng đó thì không ai biết test này
   tồn tại để làm gì.

Chạy:

```powershell
.\03_Verification\regression\scripts\Invoke-Regression.ps1 -Tier regression
```

Báo cáo gộp của cả hai tầng ghi vào `../reports/<timestamp>/summary.md`.
