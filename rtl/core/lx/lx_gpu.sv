// lx_gpu.sv - la LX-GPU de hww (deps/lx-gpu-rtl) en el core del Aleste LX
// Shaeon (Carlos Palmero), para AlesteLX_MiSTer.
//
// Reparto de relojes acordado con hww (noviembre de 2026):
// - 54 MHz (clk_bus, el del bus del Z80): los registros del Z80 (host_if, pagina
//   MMIO 3: 0-2 GPU_ADDR, 3 COMMAND, 4 STATUS) y el nucleo de la GPU (gpu_top).
// - 108 MHz (clk_mem, el del arbitro de memoria): solo el lado del arbitro del
//   puente, con la peticion registrada, para no anadir logica a las rutas
//   arbitro -> SDRAM, que van justas de tiempo.
// Los dos relojes salen del mismo PLL y van en fase: el puente cruza con un par
// de conmutadores (peticion y respuesta) sin sincronizadores, y Quartus analiza
// los caminos entre los dos dominios.
//
// El puerto GPU del arbitro: direccion en bytes, datos de 16 bits, sel = 11;
// ack0 trae la primera palabra (lecturas en rafaga de 2) y ack1 marca el final
// (las escrituras son de una palabra). La peticion cae en el mismo ciclo de ack1:
// si siguiera alta, el arbitro repetiria el acceso.
`default_nettype none
module lx_gpu (
    input  wire        clk_bus,        // 54 MHz
    input  wire        clk_mem,        // 108 MHz, en fase con clk_bus
    input  wire        rst,            // del dominio de clk_bus
    // registros del Z80 (pagina MMIO 3)
    input  wire        cs_i,
    input  wire        we_i,
    input  wire [6:0]  adr_i,
    input  wire [7:0]  dat_i,
    output wire [7:0]  dat_o,
    output wire        ack_o,
    output wire        irq_o,          // linea 5 del PIC
    // puerto GPU del arbitro de memoria (clk_mem)
    output logic [23:0] mem_addr_o,
    output logic        mem_req_o,
    output logic        mem_we_o,
    output logic [15:0] mem_dat_o,
    output wire  [1:0]  mem_sel_o,
    input  wire  [15:0] mem_dat_i,
    input  wire         mem_ack0_i,
    input  wire         mem_ack1_i
);
    // ------------------------------------------------------------ 54 MHz
    logic        gpu_start, gpu_reset, gpu_halted, gpu_error;
    logic [23:0] gpu_addr;
    logic [6:0]  gpu_halt_code;

    host_if u_host (
        .clk(clk_bus), .rst(rst),
        .wb_cyc_i(cs_i), .wb_stb_i(cs_i), .wb_we_i(we_i),
        .wb_adr_i({1'b0, adr_i}), .wb_dat_i(dat_i),
        .wb_dat_o(dat_o), .wb_ack_o(ack_o),
        .gpu_start_o(gpu_start), .gpu_reset_o(gpu_reset), .gpu_addr_o(gpu_addr),
        .gpu_halted_i(gpu_halted), .gpu_error_i(gpu_error),
        .gpu_error_code_i({5'd0, gpu_halt_code})
    );

    logic        wbm_cyc, wbm_stb, wbm_we, wbm_ack;
    logic [23:0] wbm_adr;
    logic [15:0] wbm_dat_w, wbm_dat_r;

    // el cargador de la ROM, visto desde el directorio del proyecto (Quartus);
    // la simulacion enlaza lx/ en su directorio de trabajo
    gpu_top #(.BOOT_HEX("lx/aleste-xi-bios/deps/lx-gpu-rtl/boot/bootloader.hex")) u_gpu (
        .clk(clk_bus), .rst(rst),
        .start_i(1'b0),                 // solo con COMMAND = START
        .gpu_start_i(gpu_start),
        .gpu_reset_i(gpu_reset),
        .gpu_addr_i(gpu_addr),
        .irq_ack_i(gpu_start),          // host_if no tiene IRQ_CODE: un START nuevo la borra
        .halted_o(gpu_halted),
        .error_o(gpu_error),
        .halt_code_o(gpu_halt_code),
        .irq_o(irq_o),
        .irq_code_o(),
        .pc_o(),
        .wb_cyc_o(wbm_cyc), .wb_stb_o(wbm_stb), .wb_we_o(wbm_we),
        .wb_adr_o(wbm_adr), .wb_dat_o(wbm_dat_w),
        .wb_dat_i(wbm_dat_r), .wb_ack_i(wbm_ack)
    );

    // lado de la GPU del puente: guarda la peticion y conmuta req_tgl
    logic        req_tgl, ack_seen, pending, ack_r;
    logic [23:0] adr_q;
    logic        we_q;
    logic [15:0] datw_q, datr_q;
    logic        ack_tgl;                 // del dominio de 108 MHz
    logic [15:0] datr_m;                  // del dominio de 108 MHz

    always_ff @(posedge clk_bus) begin
        if (rst) begin
            req_tgl <= 1'b0; ack_seen <= 1'b0; pending <= 1'b0; ack_r <= 1'b0;
        end else begin
            ack_r <= 1'b0;
            if (wbm_cyc && wbm_stb && !pending && !ack_r) begin
                adr_q   <= wbm_adr;
                we_q    <= wbm_we;
                datw_q  <= wbm_dat_w;
                req_tgl <= ~req_tgl;
                pending <= 1'b1;
            end else if (pending && ack_tgl != ack_seen) begin
                ack_seen <= ack_tgl;
                datr_q   <= datr_m;
                pending  <= 1'b0;
                ack_r    <= 1'b1;         // un ciclo: la GPU termina el acceso
            end
        end
    end
    assign wbm_ack   = ack_r;
    assign wbm_dat_r = datr_q;

    // ------------------------------------------------------------ 108 MHz
    // lado del arbitro: la peticion sale de registros (mem_req_o y los datos)
    logic req_seen, busy;
    assign mem_sel_o = 2'b11;

    always_ff @(posedge clk_mem) begin
        if (rst) begin
            req_seen <= 1'b0; busy <= 1'b0; mem_req_o <= 1'b0; ack_tgl <= 1'b0;
        end else if (!busy) begin
            if (req_tgl != req_seen) begin
                req_seen   <= req_tgl;
                busy       <= 1'b1;
                mem_req_o  <= 1'b1;
                mem_addr_o <= adr_q;
                mem_we_o   <= we_q;
                mem_dat_o  <= datw_q;
            end
        end else begin
            if (mem_ack0_i && !mem_we_o) datr_m <= mem_dat_i;
            if (mem_ack1_i) begin
                mem_req_o <= 1'b0;        // cae a la vez que el arbitro vuelve a IDLE
                busy      <= 1'b0;
                ack_tgl   <= ~ack_tgl;
            end
        end
    end
endmodule
`default_nettype wire
