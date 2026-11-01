// ============================================================================
// lx_input.sv - Teclado del Aleste LX (modo LX, macro ALESTE_LX)
//
// Pagina MMIO 8 (FF0400-FF047F, MMIO_PAGE_INPUT de aleste-xi-bios):
//   00 STATUS   R  bit 0 hay eventos en la cola, bit 1 la cola se lleno
//                  (se perdieron eventos; se borra al leer STATUS)
//   01 FLAGS    R  del evento mas antiguo: bit 0 pulsada (0 = soltada),
//                  bit 1 extendida (E0)
//   02 CODE     R  codigo PS/2 (juego 2) del evento mas antiguo; leerlo lo
//                  saca de la cola (leer FLAGS antes)
//   03 CTRL     RW bit 0 interrupcion cuando hay eventos (linea 7 del PIC)
//   10-1A ROW   R  filas 0-10 de la matriz del 520EX/CPC, activo a 0 (la
//                  fila 9 lleva el joystick), para juegos
// Cola de 16 eventos de teclado (los de user_io/hps_io del core).
// ============================================================================
`default_nettype none

module lx_input (
    input  logic        clk,
    input  logic        rst,

    input  logic        cs_i,
    input  logic        we_i,
    input  logic [6:0]  adr_i,
    input  logic [7:0]  dat_i,
    output logic [7:0]  dat_o,
    output logic        ack_o,

    input  logic        key_strobe,
    input  logic        key_pressed,
    input  logic        key_extended,
    input  logic [7:0]  key_code,

    output logic [3:0]  row_o,          // a kbd_520ex.row2
    input  logic [7:0]  cols_i,         // de kbd_520ex.cols2

    output logic        irq_o
);

    logic ack_q;
    always_ff @(posedge clk) ack_q <= cs_i & ~ack_q;
    assign ack_o = ack_q;
    wire rd = cs_i & ~we_i & ~ack_q;
    wire wr = cs_i &  we_i & ~ack_q;

    // Cola: {extendida, pulsada, codigo}
    logic [9:0] fifo [16];
    logic [3:0] wp, rp;
    logic [4:0] cnt;
    logic       ovf;
    logic [7:0] ctrl;

    wire pop  = rd && adr_i == 7'h02 && cnt != 5'd0;
    wire push = key_strobe;

    always_ff @(posedge clk) begin
        if (rst) begin
            wp <= '0; rp <= '0; cnt <= '0; ovf <= 1'b0; ctrl <= '0;
        end else begin
            if (push) begin
                if (cnt == 5'd16 && !pop) ovf <= 1'b1;
                else begin
                    fifo[wp] <= {key_extended, key_pressed, key_code};
                    wp <= wp + 4'd1;
                end
            end
            if (pop) rp <= rp + 4'd1;
            case ({push && !(cnt == 5'd16 && !pop), pop})
                2'b10: cnt <= cnt + 5'd1;
                2'b01: cnt <= cnt - 5'd1;
                default: ;
            endcase
            if (rd && adr_i == 7'h00) ovf <= 1'b0;
            if (wr && adr_i == 7'h03) ctrl <= dat_i;
        end
    end

    assign irq_o = ctrl[0] & (cnt != 5'd0);
    assign row_o = adr_i[3:0];

    wire [9:0] head = fifo[rp];
    always_comb begin
        dat_o = 8'hFF;
        case (adr_i)
            7'h00: dat_o = {6'd0, ovf, cnt != 5'd0};
            7'h01: dat_o = {6'd0, head[9], head[8]};
            7'h02: dat_o = head[7:0];
            7'h03: dat_o = ctrl;
            default: if (adr_i[6:4] == 3'b001 && adr_i[3:0] <= 4'd10) dat_o = cols_i;
        endcase
    end

endmodule
