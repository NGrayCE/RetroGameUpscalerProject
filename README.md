# FPGA Retro Game Upscaler

## Overview
This project is a high-performance video upscaler implemented in SystemVerilog on a **Gowin GW5AST-138C FPGA** (Sipeed Tang Console). It digitizes analog composite video and stereo audio from retro game consoles, processes the signal, and outputs a low-latency, upscaled **720p (1280x720) HDMI signal**.

The core objective was to design a custom video pipeline capable of handling asynchronous analog signals, managing clock domain crossings, and generating spec-compliant TMDS/HDMI output without relying on external video scaler ICs.

## Key Features
* **Analog Video Capture**: High-speed sampling of composite video using an **AD9226 ADC**.
* **Custom Sync Separation**: Implemented a logic-based sync separator to detect Horizontal (HSync) and Vertical (VSync) sync pulses from the raw CVBS waveform.
* **Double Buffering Architecture**: Utilizes a "Ping-Pong" buffer scheme backed by Dual-Port Block RAM (BRAM) to handle the speed difference between the input sampling rate and the HDMI output clock.
* **720p HDMI Output**: Generates a standard 60Hz 720p video signal with proper blanking intervals and TMDS encoding.
* **Digital Audio Integration**: Captures I2S stereo audio via a **PCM1808 ADC**, packets it into the HDMI data island, and transmits it synchronized with the video stream.

## Hardware Architecture

### System Diagram
The system pipeline follows this data flow:
`Composite Input -> AD9226 ADC -> Sync Separator -> Ping-Pong RAM Buffer -> HDMI Transmitter -> HDMI Display`

### Modules Description
* **`top.sv`**: The top-level entity that instantiates the PLLs, manages global resets, and routes data between the input capture, memory, and output display modules.
* **`sync_separator.sv`**: Analyzes the incoming raw ADC values to detect sync tips (voltage thresholds). It creates digital HSync and VSync strobes and determines the "Active Video" region.
* **`ping_pong_buffer_controller.sv`**: A memory controller that manages read/write pointers. It writes incoming active video pixels into one memory bank while simultaneously reading the previous line from the other bank for the HDMI output (Scanline doubling/scaling).
* **`i2s_rx.sv`**: A serial-to-parallel interface that decodes the I2S audio stream from the PCM1808 into 16-bit Left/Right PCM samples.
* **HDMI Core**: A comprehensive HDMI transmitter implementation (adapted from Sameer Puri's HDL modules) that handles:
    * 8b/10b TMDS Encoding.
    * Packet assembly for Audio Clock Regeneration (ACR) and InfoFrames.
    * Serialization of the 10-bit parallel data into high-speed differential pairs.

## Technical Details

### Clock Domains
The design utilizes the Gowin PLL to generate specific low-jitter clocks required for video standards:
* **Pixel Clock**: 74.25 MHz (Standard 720p60 timing).
* **Serial Clock**: 371.25 MHz (5x Pixel Clock for DDR serialization).
* **Audio Master Clock**: 12.288 MHz generated internally for the PCM1808.

### Memory Management
To convert the analog line timing to digital HDMI timing, the system uses **Gowin SDPB (Semi-Dual Port Block Memory)**.
* **Write Domain**: Driven by the ADC sampling strobe (~37 MHz).
* **Read Domain**: Driven by the HDMI Pixel Clock (74.25 MHz).

## Hardware Used
* **FPGA**: Sipeed Tang Console (Gowin GW5AST-LV138PG484AC1)
* **Video ADC**: Analog Devices AD9226 (12-bit, 65 MSPS)
* **Audio ADC**: Texas Instruments PCM1808 (24-bit, 48kHz Stereo)

## Build Instructions
1.  Open the project `retro_upscaler.gprj` in **Gowin EDA**.
2.  Ensure the `src/tang_console_neo_138k.cst` constraints file matches your specific pinout configuration.
3.  Run **Synthesis** and **Place & Route**.
4.  Upload the generated `.fs` bitstream to the FPGA via the Gowin Programmer.

## Acknowledgements
* **HDMI Modules**: The HDMI packetization and TMDS encoding logic is based on the open-source work by [Sameer Puri](https://github.com/sameer/hdmi).
* **Gowin EDA**: IP Generators used for PLL and Block RAM instantiation.
