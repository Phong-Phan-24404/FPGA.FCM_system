# Platform Designer System Architecture

This directory contains the Qsys/Platform Designer subsystem used for host-to-FPGA image streaming.

## Components

- `image_upload_system.qsys`: Platform Designer system comprising:
  - **JTAG to Avalon Master Bridge**: Provides Avalon-MM master access driven via Quartus System Console scripts.
  - **image_upload_avalon_slave**: Project-local Avalon-MM slave wrapper (`rtl/src/image_upload_avalon_slave.sv` and component definition `rtl/qsys/image_upload_avalon_slave_hw.tcl`) translating 32-bit Avalon-MM transactions into pixel writes toward the SDRAM write FIFO.
- `create_image_upload_system.tcl`: Script to generate or regenerate the Qsys system in Quartus Prime.

## SDRAM Subsystem Configuration

The external SDRAM interface is controlled by the project-local Terasic SDRAM controller (`rtl/sdram_control/`), wrapped by `rtl/src/terasic_sdram_controller.sv`:

- **Controller & Client Bridge Clock**: 100 MHz.
- **External SDRAM Clock (`DRAM_CLK`)**: 100 MHz with -3,000 ps phase shift.
- **SDRAM Memory Geometry**: 13 row bits, 10 column bits, 4 banks, 16-bit data width (IS42S16320D-7TL, 64 MB).
- **Buffer FIFOs**: Independent read (`Sdram_RD_FIFO`) and write (`Sdram_WR_FIFO`) FIFOs with dual-clock domain isolation.

## Dataflow

1. **Host Upload**: The host PC streams 32-bit words via JTAG Avalon Master -> `image_upload_avalon_slave` unpacks them into 8-bit pixels -> packed into 16-bit words in `sdram_image_store` -> buffered into `Sdram_WR_FIFO` -> written to SDRAM base address `0`.
2. **FCM Streaming**: When user initiates clustering via `KEY1`, `sdram_grayscale_stream_reader` burst-reads 16-bit words from SDRAM -> splits into 8-bit pixel stream with valid/ready handshaking -> crosses clock domains via DCFIFO into the 25 MHz `fcm_stream_pipeline`.
