# Prueba unitaria de la MMU nativa (rtl/core/mmu_native.sv)
#
# Es la de aleste-lx-fpga-sv (hww), tests/unit/memory/mmu_native, escrita para
# la MMU de su rama main. La nuestra viene de la rama dev, asi que la prueba
# esta adaptada:
#   - mmu.h: puertos F0h-FFh (control F0, pagina MMIO F1, syscall F2, slots
#     FA/FB, bancos FC-FF) en vez de D3h-DFh; bit 1 del control = modo nativo
#     y bit 0 = supervisor (escribir 0 sale), al reves que en main.
#   - mmu_native_test.cpp: clke = 1 (habilitacion de reloj del Z80), tres
#     ciclos de reposo tras cada escritura de E/S (la MMU la aplica dos flancos
#     despues de soltar WR, como entre dos E/S de un Z80 real) y los dos
#     valores esperados del control escritos con los bits nuevos.
#   make        compila y pasa las 45 comprobaciones
ROOT := ../../..
all: obj_dir/Vmmu_native
	./obj_dir/Vmmu_native | tail -5

obj_dir/Vmmu_native: mmu_native_test.cpp mmu.h $(ROOT)/rtl/core/mmu_native.sv
	verilator --cc --exe --build --trace -j 0 -Wno-fatal -Wno-lint -Wno-style \
	  --x-assign unique --x-initial unique --timing --timescale 1ns/1ps \
	  -CFLAGS "-I$(CURDIR)" $(ROOT)/rtl/core/mmu_native.sv mmu_native_test.cpp \
	  --top-module mmu_native

clean:
	rm -rf obj_dir *.vcd
