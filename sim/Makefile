# Simulacion del Aleste LX con Verilator (>= 5.0, con --timing)
#   make [ROM=ruta/LX.ROM] [PLUSARGS="..."]
#       carga LX.ROM (por defecto ../lx/build/LX.ROM), arranca la BIOS y vuelca
#       un cuadro en obj/pantalla.ppm (y .png con Python+PIL). Opciones del
#       banco de pruebas (tb_lx.sv):
#         +ms=N          ms que corre tras arrancar la CPU (por defecto 30)
#         +nohalt        no para en el primer HALT
#         +trace_io +nio=N +io_t0=us   traza de E/S
#         +nbus=N +bus_t0=us           traza del bus de la CPU
#         +peek=HEX +peekn=N           memoria al final
' Enter, '~' ESC, '_' espacio)|' Enter, '~' ESC, '_' espacio)
#         +dsk=imagen [+fdc_slow]      disco en la unidad A (+dsk_out=fichero lo guarda al final)
#         +pcm=fichero                 audio de la MS2 (estereo, 16 bits, 48 kHz)
#   make lint
ROOT    := ..
C       := $(ROOT)/rtl/core
H       := $(ROOT)/rtl/hww/src
FLAGS   := --binary --timing -j 0 -Wno-fatal -Wno-lint -Wno-style -Wno-TIMESCALEMOD \
           -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-INITIALDLY \
           --top-module tb_lx -Mdir obj -DALESTE_LX $(DEFS)
SRCS    := $(H)/components/reset/reset_controller.sv \
           $(C)/sdram_wishbone.sv \
           $(C)/mc6845mod.sv \
           $(H)/components/video/hdmi_scaler/dual_port_ram.sv \
           $(H)/components/video/hdmi_scaler/hdmi_scaler.sv \
           $(C)/cpc_colors.sv \
           $(H)/components/video/palette/msx_colors.sv \
           $(C)/color_palette.sv \
           $(H)/components/video/video_buffer/video_buffer.sv \
           $(C)/pixel_pipeline.sv \
           $(C)/memory_arbiter.sv \
           $(H)/systems/aleste_video/wb_arbiter.sv \
           $(H)/systems/aleste_video/address_decoder.sv \
           $(H)/components/cpu/tv80/tv80_core.v \
           $(H)/components/cpu/tv80/tv80_reg.v \
           $(H)/components/cpu/tv80/tv80_alu.v \
           $(H)/components/cpu/tv80/tv80_mcode.v \
           $(C)/z80_system.sv \
           $(H)/components/io/ppi/i8255_wb.sv \
           $(H)/systems/aleste_system/z80_debug.sv \
           $(C)/mmu_legacy.sv \
           $(H)/systems/aleste_system/system_arbiter.sv \
           $(H)/components/interconnect/wishbone/wb_wdt_simple.sv \
           $(C)/tv80lx.v $(C)/mmu_native.sv \
           $(C)/vga_timing.sv $(C)/video_ctrl_vga.sv \
           $(C)/mist_loader.sv $(C)/cpc/UM6845R.v $(C)/cpc/cpc_video.sv $(C)/cpc/kbd_520ex.sv $(C)/cpc/rtc146818.sv $(C)/cpc/magic_sound.sv $(C)/cpc/serial_mouse.sv $(C)/cpc/kempston_mouse.v $(C)/cpc/symbiface_mouse.v $(C)/cpc/multiplay_mouse.v $(C)/cpc/amx_mouse.v $(C)/cpc/tzxplayer.sv $(C)/cpc/u765.sv $(C)/YM2149.sv $(C)/lx/lx_sys.sv $(C)/lx/lx_ms2.sv $(C)/lx/lx_dma.sv $(C)/lx/lx_input.sv $(C)/aleste_lx_core.sv \
           sdram_model.sv

all: run

obj/Vtb_lx: $(SRCS) tb_lx.sv
	verilator $(FLAGS) $(SRCS) tb_lx.sv

run: obj/Vtb_lx
	cp -f $(H)/components/video/palette/*.mem $(C)/*.mem obj/ 2>/dev/null; cd obj && ./Vtb_lx +rom=$(abspath $(or $(ROM),../lx/build/LX.ROM)) $(PLUSARGS)
	-python3 -c "from PIL import Image; Image.open('obj/pantalla.ppm').save('obj/pantalla.png')" 2>/dev/null

lint:
	verilator --lint-only -Wall -Wno-fatal -DALESTE_LX --top-module aleste_lx_core $(filter-out sdram_model.sv,$(SRCS))

clean:
	rm -rf obj
