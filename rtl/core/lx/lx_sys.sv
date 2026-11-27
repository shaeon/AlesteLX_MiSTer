// ============================================================================
// lx_sys.sv - Alesta LX system devices
//
// PIC:
//   +0 COMMAND      W   bit7=0: обычная команда (supervisor only)
//                       bit7=1: установить приоритет канала (supervisor only)
//   +1 CLAIM        R   атомарно выбрать и захватить канал
//   +2 VECTOR       RW  vector base IM 2 (reset = 0xFF), write: supervisor only
//
//   +3 PENDING_L    R
//   +4 PENDING_H    R
//   +5 REPEAT_L     R
//   +6 REPEAT_H     R
//   +7 IN_SERVICE_L R
//   +8 IN_SERVICE_H R
//   +9 ENABLE_L     R
//   +A ENABLE_H     R
//   +B STATUS_L     R   PENDING & ENABLE & ~IN_SERVICE
//   +C STATUS_H     R
//
// COMMAND, bit7=0:
//   bits[6:4] = opcode
//   bits[3:0] = channel
//
//   000 NOP
//   001 COMPLETE
//   010 ENABLE
//   011 DISABLE
//   100 CLEAR_PENDING
//   101 CLEAR_REPEAT
//   110 CLEAR_BOTH
//   111 reserved
//
// COMMAND, bit7=1:
//   bits[6:4] = priority (0..7, 7 = highest)
//   bits[3:0] = channel
//
// CLAIM:
//   bit7    = VALID
//   bit6    = REPEAT
//   bits5:4 = reserved
//   bits3:0 = channel ID
//
// CLAIM atomically:
//   - clears the old PENDING and REPEAT state of the selected channel;
//   - sets IN_SERVICE for that channel.
//   New IRQ edges arriving during service are accumulated independently.
//   COMPLETE only clears IN_SERVICE; it does not clear new pending events.
//
// VECTOR is a base vector register for IM 2. The PIC does NOT auto-generate
// the vector: vector_o (= VECTOR) is what the system puts on the data bus
// during the interrupt acknowledge (reset FF = RST 38h in IM 0), and the
// kernel dispatches with CLAIM. int_ack_i is intentionally not used to modify PIC state.
//
// TIMER:
//   F4 R: latch the 16-bit RT into the caller's RT_SNAPSHOT, return its low
//         byte. There is one snapshot per mode (supervisor / user, by
//         sup_i), so a supervisor handler that reads the time between a
//         user F4 and F5 does not disturb the user's pair. Reads have no
//         other side effect (they do not open WINDOW).
//   F4 W: buffer COMPARE low + WINDOW=1                  (supervisor only)
//   F5 R: high byte of the caller's RT_SNAPSHOT
//   F5 W: commit COMPARE {dat_i, buf_lo} + WINDOW=0
//         + ARMED=1 + ENABLE=1 + FIRED=0 + immediate comparison
//   F6 R: {reserved, FIRED, DUE, WINDOW, ARMED, ENABLE}
//   F6 W: bit0 = ENABLE (supervisor only)
//
//   RT: 16-bit free-running counter @ 1 MHz.
//   DUE = ARMED & ~(RT - COMPARE)[15] (live comparator, diagnostic).
//   TIMER IRQ: rising edge of DUE, commit while DUE, or enable while DUE,
//   at most ONCE per commit: the request sets FIRED, and only an F5 commit
//   clears it. Without FIRED the modulo comparison would rise again every
//   65536 us (DUE falls 32768 us after the target and rises 32768 us later).
//
// WINDOW (supervisor F4 write -> F5 write) blocks INT; it does NOT block NMI.
//   A 32 us hardware timeout auto-clears WINDOW so a forgotten F4/F5
//   sequence can never block INT forever. Normal F4->F5 sequences are
//   unaffected (they complete in a few microseconds).
//
// TIMER writes require supervisor privilege.
// PIC COMMAND and VECTOR writes require supervisor privilege.
// PIC data/status reads and CLAIM are permitted in both modes.
//
// Bus contract:
//   - One bus cycle => exactly one internal operation, regardless of how
//     long cs_i stays asserted. bus_taken latches the acceptance of the
//     cycle; rd/wr are single-cycle strobes.
//   - Read data that depends on side-effecting reads (CLAIM, F4) is
//     captured into a register at the strobe and returned on dat_o while
//     ack_o is asserted. This makes the module independent of the exact
//     cycle in which the bridge samples dat_o.
//
// External IRQ lines are assumed asynchronous; they are synchronized with
// two flops before edge detection. Bit 6 is the internal timer request
// (t_irq), already synchronous, and is not routed through the synchronizer.
// ============================================================================

`default_nettype none

module lx_sys #(
    parameter int CLK_HZ = 54_000_000
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        cs_i,
    input  logic        we_i,
    input  logic [7:0]  adr_i,
    input  logic [7:0]  dat_i,
    output logic [7:0]  dat_o,
    output logic        ack_o,

    input  logic        sup_i,

    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [15:0] irq_i,       // bit 6 is the internal timer (t_irq);
                                     // external irq_i[6] is intentionally unused
    input  logic        int_ack_i,   // reserved for physical CPU acknowledge;
                                     // intentionally does not modify PIC state
    /* verilator lint_on UNUSEDSIGNAL */
    output logic        int_o,
    output logic [7:0]  vector_o,    // VECTOR, for the bus during INTACK
    output logic        int_block_o,
    output logic        nmi_block_o
);

    // ------------------------------------------------------------------------
    // Bus decoding
    // ------------------------------------------------------------------------

    localparam int US_DIV = CLK_HZ / 1_000_000;
    localparam int PRE_W  = (US_DIV <= 1) ? 1 : $clog2(US_DIV);

    // WINDOW auto-timeout (microseconds). Normal F4->F5 takes a few us.
    localparam int WIN_TIMEOUT_US = 32;
    localparam int WIN_W = $clog2(WIN_TIMEOUT_US + 1);

    wire pic_sel = (adr_i[7:5] == 3'b000);

    wire tmr_sel = (adr_i == 8'hF4) ||
                   (adr_i == 8'hF5) ||
                   (adr_i == 8'hF6);

    // ------------------------------------------------------------------------
    // Single-cycle bus strobe
    //
    // bus_taken latches the acceptance of the current bus cycle. While cs_i
    // remains asserted, no further rd/wr are generated. When cs_i drops,
    // the state machine is ready for the next cycle.
    // ------------------------------------------------------------------------

    logic bus_taken;
    logic ack_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            bus_taken <= 1'b0;
            ack_q     <= 1'b0;
        end else begin
            if (!cs_i) begin
                bus_taken <= 1'b0;
                ack_q     <= 1'b0;
            end else if (!bus_taken) begin
                bus_taken <= 1'b1;
                ack_q     <= 1'b1;
            end
            // else: cs_i still high, cycle already accepted; wait for release
        end
    end

    assign ack_o = ack_q;

    wire wr = cs_i &  we_i & ~bus_taken & ~ack_q;
    wire rd = cs_i & ~we_i & ~bus_taken & ~ack_q;

    // ========================================================================
    // TIMER
    // ========================================================================

    logic [15:0] rt;
    logic [PRE_W-1:0] us_pre;

    logic [15:0] compare;
    logic [15:0] rt_snap_sup;     // per-mode snapshots (see F4 read)
    logic [15:0] rt_snap_usr;
    logic [7:0]  cmp_buf_lo;

    logic window;
    logic [WIN_W-1:0] win_timer;
    logic armed;
    logic enable;
    logic fired;                  // the request of this commit was sent

    // Signed-difference comparison: only the sign bit is needed.
    // Signed-difference comparison: only bit 15 (sign) is used.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [15:0] delta        = rt - compare;
    wire [15:0] commit_delta = rt - {dat_i, cmp_buf_lo};
    /* verilator lint_on UNUSEDSIGNAL */

    wire due                = armed & ~delta[15];
    wire compare_commit_due = ~commit_delta[15];

    logic due_q;
    logic t_irq;

    wire tmr_wr = wr & tmr_sel & sup_i;
    wire tmr_rd = rd & tmr_sel;
    wire us_tick = (us_pre == PRE_W'(US_DIV - 1));

    always_ff @(posedge clk) begin
        t_irq <= 1'b0;

        if (rst) begin
            rt          <= 16'd0;
            us_pre      <= '0;
            compare     <= 16'd0;
            rt_snap_sup <= 16'd0;
            rt_snap_usr <= 16'd0;
            cmp_buf_lo  <= 8'd0;
            window      <= 1'b0;
            win_timer   <= '0;
            armed       <= 1'b0;
            enable      <= 1'b0;
            fired       <= 1'b0;
            due_q       <= 1'b0;
            t_irq       <= 1'b0;
        end else begin

            // -----------------------------------------------------------------
            // Free-running RT @ 1 MHz + WINDOW auto-timeout (both in us domain)
            // -----------------------------------------------------------------
            if (us_tick) begin
                us_pre <= '0;
                rt     <= rt + 16'd1;

                if (window) begin
                    if (win_timer == WIN_W'(WIN_TIMEOUT_US - 1)) begin
                        window    <= 1'b0;
                        win_timer <= '0;
                    end else begin
                        win_timer <= win_timer + 1'b1;
                    end
                end else begin
                    win_timer <= '0;
                end
            end else begin
                us_pre <= us_pre + 1'b1;
            end

            due_q <= due;

            // -----------------------------------------------------------------
            // Timer reads
            // -----------------------------------------------------------------
            // F4: atomic 16-bit snapshot of the caller's mode; F5 reads its
            // high byte. No WINDOW: a read cannot block interrupts.
            if (tmr_rd && adr_i == 8'hF4) begin
                if (sup_i) rt_snap_sup <= rt;
                else       rt_snap_usr <= rt;
            end

            // -----------------------------------------------------------------
            // Timer writes: supervisor only
            // -----------------------------------------------------------------
            if (tmr_wr) begin
                case (adr_i)

                    8'hF4: begin
                        cmp_buf_lo <= dat_i;
                        window     <= 1'b1;
                        win_timer  <= '0;
                    end

                    8'hF5: begin
                        compare   <= {dat_i, cmp_buf_lo};
                        window    <= 1'b0;
                        win_timer <= '0;
                        armed     <= 1'b1;
                        enable    <= 1'b1;
                        fired     <= 1'b0;

                        // Immediate comparison after commit
                        if (compare_commit_due) begin
                            t_irq <= 1'b1;
                            fired <= 1'b1;
                        end
                    end

                    8'hF6: begin
                        enable <= dat_i[0];

                        if (dat_i[0] && armed && due && !fired) begin
                            t_irq <= 1'b1;
                            fired <= 1'b1;
                        end
                    end

                    default: ;
                endcase
            end

            // Rising edge of DUE (once per commit). Not in the cycle of an F5
            // commit: the commit decides by itself (compare_commit_due).
            if (enable && armed && due && !due_q && !fired &&
                !(tmr_wr && adr_i == 8'hF5)) begin
                t_irq <= 1'b1;
                fired <= 1'b1;
            end
        end
    end

    // ========================================================================
    // PIC
    // ========================================================================

    // External IRQ synchronizers (two flops). Bit 6 is the internal timer
    // request (t_irq), already synchronous; it is not routed through the
    // synchronizer. irq_sync layout: {irq_i[15:7], irq_i[5:0]}.
    logic [14:0] irq_meta;
    logic [14:0] irq_sync;
    logic [15:0] irq_prev;

    always_ff @(posedge clk) begin
        if (rst) begin
            irq_meta <= '0;
            irq_sync <= '0;
        end else begin
            irq_meta <= {irq_i[15:7], irq_i[5:0]};
            irq_sync <= irq_meta;
        end
    end

    logic [15:0] irq_lines;

    logic [15:0] pending;
    logic [15:0] repeat_f;
    logic [15:0] in_service;
    logic [15:0] enabled;

    logic [2:0] chan_prio [0:15];

    logic [7:0] vector;

    assign irq_lines = {
        irq_sync[14:6],   // irq_i[15:7]
        t_irq,            // internal timer, bit 6
        irq_sync[5:0]     // irq_i[5:0]
    };

    // New rising-edge requests
    wire [15:0] edge_new = irq_lines & ~irq_prev;

    // Only pending channels which are enabled and not already in service
    wire [15:0] eligible = pending & enabled & ~in_service;

    assign int_o       = |eligible;
    assign vector_o    = vector;
    assign int_block_o = window;
    assign nmi_block_o = 1'b0;   // NMI must not be blocked by WINDOW

    // ------------------------------------------------------------------------
    // Priority arbitration
    //
    // Highest priority wins.
    // For equal priorities, the lowest channel number wins.
    // Priority only orders simultaneous requests; it does not preempt an
    // in-service channel (Z80 with automatic DI on interrupt entry).
    //
    // The winner is registered every clock (best_valid_q / best_ch_q), so
    // the 16-way priority compare is not in series with the CLAIM update
    // of PENDING / IN_SERVICE (timing). A bus cycle lasts many clocks and
    // cs_i must drop between cycles, so the registered winner always
    // reflects the state after the previous command or CLAIM. It is
    // re-checked against ELIGIBLE at the strobe.
    // ------------------------------------------------------------------------

    logic       arb_valid;
    logic [3:0] arb_channel;
    logic [2:0] arb_priority;

    integer k;

    always_comb begin
        arb_valid    = 1'b0;
        arb_channel  = 4'd0;
        arb_priority = 3'd0;

        for (k = 0; k < 16; k = k + 1) begin
            if (eligible[k]) begin
                if (!arb_valid || (chan_prio[k] > arb_priority)) begin
                    arb_valid    = 1'b1;
                    arb_channel  = k[3:0];
                    arb_priority = chan_prio[k];
                end
            end
        end
    end

    logic       best_valid_q;
    logic [3:0] best_ch_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            best_valid_q <= 1'b0;
            best_ch_q    <= 4'd0;
        end else begin
            best_valid_q <= arb_valid;
            best_ch_q    <= arb_channel;
        end
    end

    wire       claim_valid   = best_valid_q & eligible[best_ch_q];
    wire [3:0] claim_channel = best_ch_q;

    // ------------------------------------------------------------------------
    // Bus events
    // ------------------------------------------------------------------------

    wire pic_command_wr =
        wr && pic_sel && (adr_i[4:0] == 5'd0) && sup_i;

    wire claim_rd =
        rd && pic_sel && (adr_i[4:0] == 5'd1);

    wire vector_wr =
        wr && pic_sel && (adr_i[4:0] == 5'd2) && sup_i;

    wire [3:0] command_channel = dat_i[3:0];
    wire [2:0] command_opcode  = dat_i[6:4];

    // ------------------------------------------------------------------------
    // CLAIM result register
    //
    // Captured at the strobe; dat_o returns claim_q while ack_o is asserted.
    // This decouples the returned value from the post-claim state.
    // ------------------------------------------------------------------------

    logic [7:0] claim_q;

    // ------------------------------------------------------------------------
    // PIC state
    // ------------------------------------------------------------------------

    integer i;

    always_ff @(posedge clk) begin
        if (rst) begin
            irq_prev   <= 16'd0;
            pending    <= 16'd0;
            repeat_f   <= 16'd0;
            in_service <= 16'd0;
            enabled    <= 16'd0;
            vector     <= 8'hFF;
            claim_q    <= 8'h00;

            for (i = 0; i < 16; i = i + 1)
                chan_prio[i] <= 3'd0;

        end else begin

            irq_prev <= irq_lines;

            // ---------------------------------------------------------------
            // Capture new IRQ edges.
            //
            // First edge sets PENDING.
            // Further edges while PENDING is already set set REPEAT.
            // ---------------------------------------------------------------

            pending  <= pending | edge_new;
            repeat_f <= repeat_f | (pending & edge_new);

            // ---------------------------------------------------------------
            // CLAIM: consume the old request and enter service.
            //
            // If a new edge arrives on the same clock as CLAIM, it remains
            // pending as a new event. The old request is what CLAIM consumes.
            // The result byte is captured here, before state changes are
            // visible on dat_o.
            // ---------------------------------------------------------------

            if (claim_rd) begin
                claim_q <= claim_valid
                         ? {1'b1, repeat_f[claim_channel], 2'b00, claim_channel}
                         : 8'h00;

                if (claim_valid) begin
                    pending[claim_channel]    <= edge_new[claim_channel];
                    repeat_f[claim_channel]   <= 1'b0;
                    in_service[claim_channel] <= 1'b1;
                end
            end

            // ---------------------------------------------------------------
            // COMMAND register
            // ---------------------------------------------------------------

            if (pic_command_wr) begin

                if (dat_i[7]) begin
                    // Operand form: set channel priority.
                    chan_prio[command_channel] <= dat_i[6:4];

                end else begin
                    // Ordinary command form.
                    case (command_opcode)

                        3'b000: begin
                            // NOP
                        end

                        3'b001: begin
                            // COMPLETE: release service state only.
                            in_service[command_channel] <= 1'b0;
                        end

                        3'b010: begin
                            // ENABLE channel.
                            enabled[command_channel] <= 1'b1;
                        end

                        3'b011: begin
                            // DISABLE channel.
                            enabled[command_channel] <= 1'b0;
                        end

                        3'b100: begin
                            // CLEAR_PENDING.
                            // A simultaneous new edge is preserved.
                            pending[command_channel] <=
                                edge_new[command_channel];
                        end

                        3'b101: begin
                            // CLEAR_REPEAT.
                            // Preserve a newly detected overrun.
                            repeat_f[command_channel] <=
                                pending[command_channel] &
                                edge_new[command_channel];
                        end

                        3'b110: begin
                            // CLEAR_BOTH.
                            // A simultaneous new edge becomes a fresh pending
                            // event, not a repeat of the cleared event.
                            pending[command_channel] <=
                                edge_new[command_channel];

                            repeat_f[command_channel] <= 1'b0;
                        end

                        default: ;
                    endcase
                end
            end

            // VECTOR register (supervisor only)
            if (vector_wr)
                vector <= dat_i;
        end
    end

    // ========================================================================
    // READ DATA
    //
    // Side-effecting reads (CLAIM, F4/F5) return values captured into
    // registers at the strobe. dat_o is therefore stable while ack_o is
    // asserted, independent of the bridge's sample cycle.
    // ========================================================================

    always_comb begin
        dat_o = 8'hFF;

        if (pic_sel) begin
            case (adr_i[4:0])

                // COMMAND is write-only.
                5'd1: begin
                    // CLAIM read result (captured at the strobe).
                    dat_o = claim_q;
                end

                5'd2: dat_o = vector;

                5'd3: dat_o = pending[7:0];
                5'd4: dat_o = pending[15:8];

                5'd5: dat_o = repeat_f[7:0];
                5'd6: dat_o = repeat_f[15:8];

                5'd7: dat_o = in_service[7:0];
                5'd8: dat_o = in_service[15:8];

                5'd9:  dat_o = enabled[7:0];
                5'd10: dat_o = enabled[15:8];

                5'd11: dat_o = eligible[7:0];
                5'd12: dat_o = eligible[15:8];

                default: ;
            endcase

        end else if (tmr_sel) begin
            case (adr_i)

                8'hF4: dat_o = sup_i ? rt_snap_sup[7:0]  : rt_snap_usr[7:0];
                8'hF5: dat_o = sup_i ? rt_snap_sup[15:8] : rt_snap_usr[15:8];
                8'hF6: dat_o = {
                    3'b000,
                    fired,
                    due,
                    window,
                    armed,
                    enable
                };

                default: ;
            endcase
        end
    end

    // int_ack_i is intentionally not used to modify PIC state.
    // CPU acknowledge and software CLAIM are separate operations.

endmodule

`default_nettype wire
