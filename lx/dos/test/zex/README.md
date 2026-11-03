# ZEXDOC y ZEXALL

Ejercitadores de instrucciones del Z80 de Frank Cringle (GPL), tomados de
`tests/unit/cpu/tv80` de aleste-lx-fpga-sv (hww). Son programas CP/M: en el
LX-DOS se ejecutan tal cual (`zexdoc`, `zexall`) y prueban a la vez el Z80
del core (tv80) y el BDOS. ZEXDOC comprueba los flags documentados y ZEXALL
todos; cada una de sus 67 pruebas debe acabar en "OK". En la placa tardan
del orden de una hora; en simulación solo se comprueba que arrancan.
