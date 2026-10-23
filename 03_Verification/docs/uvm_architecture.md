# UVM architecture — 03_Verification

Tài liệu này mô tả **cấu trúc nguồn** của DV system: cái gì nằm ở đâu, class
nào sở hữu file nào, và thứ tự compile. Mục tiêu nội dung kiểm thử nằm ở
[verification_plan.md](verification_plan.md); danh mục testbench nằm ở
[test_traceability.md](test_traceability.md).

## 1. Ba tầng trách nhiệm

| Tầng | Thư mục | Trách nhiệm | Được phép phụ thuộc vào |
| --- | --- | --- | --- |
| Reusable verification components | `agents/` | transaction, interface, sequencer, driver, monitor, agent, agent config | `fcm_pkg`, `fcm_vector_pkg` |
| Verification environments | `env/` | scoreboard, coverage, perf, env, env config | tầng trên + agent tương ứng |
| Test & regression | `tests/`, `sequences/`, `tb/`, `regression/` | scenario, cấu hình, testbench top, tier | cả hai tầng trên |

Hạ tầng dùng chung (`common/`) không được phụ thuộc vào bất kỳ tầng nào ở
trên: nó chỉ đọc file vector và không biết gì về interface cụ thể.

Một quy tắc kiểm tra nhanh khi review: **mũi tên phụ thuộc chỉ đi xuống**.
Nếu một file trong `agents/` nhắc tới một class trong `env/` hoặc `tests/`,
nó đã sai chỗ.

## 2. Cây thư mục

```
03_Verification/
├── common/                     fcm_vector_pkg.sv — đọc vector, hằng đường dẫn
├── agents/
│   ├── member_agent/           fcm_member_if.sv + item/cfg/sequencer/driver/monitor/agent
│   ├── core_agent/             fcm_core_if.sv   + ...
│   └── stream_agent/           fcm_soc_if.sv    + ...
├── env/
│   ├── ip/                     env_cfg, coverage, perf, scoreboard, env (member + core)
│   └── soc/                    env_cfg, coverage, scoreboard, env
├── sequences/{ip,soc}/         stimulus đọc từ vector của reference
├── tests/{ip,soc}/             base test + test dẫn xuất
├── tb/{ip,soc}/                testbench top, harness directed
├── assertions/{ip,soc}/        SVA + module bind
├── packages/                   ba điểm vào UVM package
├── vectors/                    vector do 01_Reference sinh ra (không sửa tay)
├── regression/{scripts,testlists,reports}/
└── docs/
```

Phân vùng theo **verification target trước, vai trò UVM sau**. Không có thư
mục `drivers/` gom mọi driver của mọi DUT: người sở hữu một agent cần đọc
toàn bộ agent đó ở một chỗ.

## 3. Package và phụ thuộc compile

Ba UVM package, mỗi package một điểm vào trong `packages/`:

| Package | Nội dung | Testbench dùng |
| --- | --- | --- |
| `fcm_member_uvm_pkg` | agent `fcm_member` + env + test | `tb_fcm_member_uvm` |
| `fcm_core_uvm_pkg` | agent `fcm_core` + env + test | `tb_fcm_core_uvm` |
| `fcm_soc_uvm_pkg` | agent `fcm_soc` (stream) + env + test | `tb_fcm_stream_pipeline_uvm` |

**Tại sao ba chứ không phải một.** Questa phân giải MỌI kiểu virtual interface
được nhắc tới trong một package lúc elaborate. Khi `fcm_member` và `fcm_core`
nằm chung package, `tb_fcm_core_uvm` phải instantiate một `fcm_member_if` nó
không dùng — chỉ để vsim không báo `vsim-8451`. Tách package xoá hẳn phụ
thuộc đó: mỗi testbench chỉ nạp đúng thứ nó cần.

File `.svh` **không** nằm trong `TbSources`. Chúng được tìm qua `+incdir+`
(khoá `IncludeDirs` trong `07_Scripts/config/*.psd1`) và nạp bằng `` `include ``
theo đúng thứ tự khai báo trong file package. Thứ tự đó là ngữ nghĩa, không
phải thẩm mỹ: một class phải đứng sau mọi class nó tham chiếu.

Thứ tự compile (`TbSources`, vlog compile theo thứ tự dòng lệnh):

```
fcm_pkg (RTL)  →  fcm_vector_pkg  →  <agent>_if.sv  →  <pkg>.sv  →  SVA  →  tb top
```

## 4. Component hierarchy lúc chạy

```
uvm_test_top                     (fcm_core_base_test / fcm_core_smoke_test)
└── env                          fcm_core_env
    ├── core_agent               fcm_core_agent
    │   ├── sequencer            chỉ khi UVM_ACTIVE
    │   ├── driver               chỉ khi UVM_ACTIVE
    │   └── monitor              luôn có
    ├── scoreboard               fcm_core_scoreboard
    ├── coverage                 fcm_core_coverage
    └── perf                     fcm_core_perf
```

Mức member và mức SoC giống hệt, với `member_agent` / `stream_agent` và không
có `perf`. Tên instance nói rõ agent nào — một env về sau có thể giữ nhiều
agent, và `agent` thì không phân biệt được trong log hay trong `config_db`.

## 5. Luồng configuration

```
tb top        uvm_config_db #(virtual fcm_core_if)::set(null, "uvm_test_top", "vif", vif)
   │
test          đọc vif + plusarg  →  dựng fcm_core_env_cfg (vector_dirs, max_items,
   │                                 agent_cfg.vif, agent_cfg.is_active)
   │          set(this, "env", "cfg", cfg)
env           set(this, "core_agent", "cfg", cfg.agent_cfg)
agent         set(this, "driver", "cfg", cfg);  set(this, "monitor", "cfg", cfg)
driver/monitor  vif = cfg.vif
```

Hai điều quan trọng:

- **Không có wildcard `"*"`.** Mọi `set` dùng đường dẫn instance tường minh.
  Thêm agent thứ hai cùng kiểu interface sẽ không vô tình nhận cấu hình của
  agent thứ nhất — loại lỗi đó vẫn compile sạch nên rất khó thấy.
- **Chỉ test đọc plusarg.** `+FCM_VECTORS` và `+FCM_MAX_ITEMS` được đọc một
  lần, ở `configure()` của base test. Muốn biết một lần chạy dùng bộ vector
  nào thì chỉ cần đọc class test.

## 6. Active / passive

`<agent>_agent_cfg.is_active` mặc định `UVM_ACTIVE`. Ở `UVM_PASSIVE`, agent
chỉ dựng monitor; env bỏ qua các kết nối xuất phát từ driver. Cần khi agent
mức IP được tái sử dụng trong một env cấp cao hơn, nơi DUT đã được lái bởi
thứ khác.

## 7. Code ownership

Một file `.svh` = một class = một đơn vị review. Ranh giới sở hữu đề nghị:

| Vùng | Nội dung | Ghi chú |
| --- | --- | --- |
| `agents/member_agent/` | agent fcm_member | đổi ở đây ảnh hưởng mọi env dùng agent này |
| `agents/core_agent/` | agent fcm_core | |
| `agents/stream_agent/` | agent mức SoC | |
| `env/ip/` | scoreboard + coverage mức IP | nơi giữ nghĩa "đúng" của contract |
| `env/soc/` | scoreboard + coverage mức SoC | |
| `sequences/`, `tests/` | scenario | |
| `assertions/` | SVA | sửa SVA là sửa yêu cầu, cần review kỹ nhất |
| `regression/`, `07_Scripts/config/*.psd1` | tier, runner, report | |

Cột "người sở hữu" cố ý để trống: điền khi phân công thật, đừng ghi tên giả.

## 8. Những ràng buộc không hiển nhiên

- **Một license vsim.** Questa Intel FPGA Starter Edition chỉ chạy một sim một
  lúc. Hai lần chạy song song sẽ hỏng và trông hệt như regression RTL fail.
- **Không có license `svverification`.** Không dùng được `covergroup`,
  `randomize`, `randcase`, `randsequence`. Coverage hiện là bộ đếm thuần
  trong `uvm_subscriber`. Nếu sau này có license đầy đủ, thay phần đó bằng
  `covergroup` thật mà không phải đụng tới agent hay scoreboard.
- **`bind` nằm trong module.** Không dùng `-mfcu` thì mỗi file là một
  compilation unit riêng, nên lệnh `bind` phải nằm trong một module và
  testbench phải instantiate module đó. Thiếu một dòng instantiate thì nhóm
  assertion tương ứng im lặng và testbench vẫn báo PASS.
- **Đường dẫn vector tính từ thư mục project Quartus**, nơi `Invoke-Sim.ps1`
  chạy `vsim`. Hằng mặc định ở `fcm_vector_pkg::FCM_DEFAULT_VECTOR_DIR`.
