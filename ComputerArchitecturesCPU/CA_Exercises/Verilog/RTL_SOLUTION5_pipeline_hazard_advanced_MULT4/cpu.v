//Module: CPU
//Function: Pipelined RISC-V processor with:
//          - Full data forwarding (EX/MEM and MEM/WB)
//          - Hazard detection with 1-cycle stall on load-use
//          - Branch/jump resolved in ID stage with IF/ID flush
//          - Register file internal WB->ID forwarding

module cpu(
		input  wire			   clk,
		input  wire         arst_n,
		input  wire         enable,
		input  wire	[63:0]  addr_ext,
		input  wire         wen_ext,
		input  wire         ren_ext,
		input  wire [31:0]  wdata_ext,
		input  wire	[63:0]  addr_ext_2,
		input  wire         wen_ext_2,
		input  wire         ren_ext_2,
		input  wire [63:0]  wdata_ext_2,

		output wire	[31:0]  rdata_ext,
		output wire	[63:0]  rdata_ext_2
   );

// ============================================================
// Wires
// ============================================================
wire [      63:0] updated_pc, current_pc, current_pc_IF_ID;
wire [      63:0] branch_pc, jump_pc;
wire [      31:0] instruction;
wire [      31:0] instruction_IF_ID;

// Control signals from control_unit (ID stage, raw)
wire [       1:0] alu_op_ctrl;
wire              branch_ctrl, mem_read_ctrl, mem_2_reg_ctrl,
                  mem_write_ctrl, alu_src_ctrl, reg_write_ctrl, jump_ctrl;
wire              reg_dst;

// Control signals after possible bubble injection
wire [       1:0] alu_op;
wire              branch, mem_read, mem_2_reg,
                  mem_write, alu_src, reg_write, jump;

// Register file outputs
wire [      63:0] regfile_rdata_1, regfile_rdata_2;
wire signed [63:0] immediate_extended;

// Branch decision in ID
wire              zero_id;
wire              branch_taken;
wire              flush_IF_ID;
wire [      63:0] branch_operand_1, branch_operand_2;
wire              branch_stall;

// ID/EX pipeline registers
wire [      63:0] current_pc_ID_EX;
wire [       4:0] rs1_ID_EX, rs2_ID_EX, rd_ID_EX;
wire [       4:0] funct_ID_EX;
wire [       1:0] alu_op_ID_EX;
wire              branch_ID_EX, mem_read_ID_EX, mem_2_reg_ID_EX,
                  mem_write_ID_EX, alu_src_ID_EX, reg_write_ID_EX, jump_ID_EX;
wire [      63:0] regfile_rdata_1_ID_EX, regfile_rdata_2_ID_EX;
wire signed [63:0] immediate_extended_ID_EX;

// EX stage
wire [       3:0] alu_control;
wire [      63:0] alu_in_0_forwarded, regfile_rdata_2_forwarded;
wire [      63:0] alu_operand_2;
wire [      63:0] alu_out;
wire              zero_flag;
wire [       1:0] forward_a, forward_b;

// EX/MEM
wire [      63:0] alu_out_EX_MEM, regfile_rdata_2_EX_MEM;
wire [       4:0] rd_EX_MEM;
wire              mem_read_EX_MEM, mem_write_EX_MEM, mem_2_reg_EX_MEM, reg_write_EX_MEM;

// MEM
wire [      63:0] mem_data;

// MEM/WB
wire [      63:0] alu_out_MEM_WB, mem_data_MEM_WB;
wire [       4:0] rd_MEM_WB;
wire              mem_2_reg_MEM_WB, reg_write_MEM_WB;

// WB
wire [      63:0] regfile_wdata;

// Stall
wire              load_use_stall;
wire              stall;
wire              pc_enable;
wire              if_id_enable;

// ============================================================
// Stall control
// ============================================================
assign stall        = load_use_stall || branch_stall;
assign pc_enable    = enable && !stall;
assign if_id_enable = enable && !stall;

// ============================================================
// IF stage
// ============================================================
pc #(
   .DATA_W(64)
) program_counter (
   .clk       (clk         ),
   .arst_n    (arst_n      ),
   .branch_pc (branch_pc   ),
   .jump_pc   (jump_pc     ),
   .zero_flag (zero_id     ),
   .branch    (branch_ctrl ),
   .jump      (jump_ctrl   ),
   .current_pc(current_pc  ),
   .enable    (pc_enable   ),
   .updated_pc(updated_pc  )
);

sram_BW32 #(
   .ADDR_W(9)
) instruction_memory(
   .clk      (clk        ),
   .addr     (current_pc ),
   .wen      (1'b0       ),
   .ren      (1'b1       ),
   .wdata    (32'b0      ),
   .rdata    (instruction),
   .addr_ext (addr_ext   ),
   .wen_ext  (wen_ext    ),
   .ren_ext  (ren_ext    ),
   .wdata_ext(wdata_ext  ),
   .rdata_ext(rdata_ext  )
);

// Flush mux: when branch/jump is taken, the instruction currently being fetched
// (which is the wrong-path instruction) must be turned into a NOP before it
// enters the IF/ID register. Otherwise it would be executed in the next cycle.
wire [31:0] instruction_to_IF_ID;
assign instruction_to_IF_ID = flush_IF_ID ? 32'h00000013 : instruction;

// IF/ID instruction register
reg_arstn_en #(
   .DATA_W(32)
) signal_pipe_IF_ID (
   .clk    (clk                  ),
   .arst_n (arst_n               ),
   .en     (if_id_enable         ),
   .din    (instruction_to_IF_ID ),
   .dout   (instruction_IF_ID    )
);

// IF/ID PC register
reg_arstn_en #(
   .DATA_W(64)
) signal_pc_IF_ID (
   .clk    (clk             ),
   .arst_n (arst_n          ),
   .en     (if_id_enable    ),
   .din    (current_pc      ),
   .dout   (current_pc_IF_ID)
);

// ============================================================
// ID stage
// ============================================================
control_unit control_unit(
   .opcode   (instruction_IF_ID[6:0]),
   .alu_op   (alu_op_ctrl           ),
   .reg_dst  (reg_dst               ),
   .branch   (branch_ctrl           ),
   .mem_read (mem_read_ctrl         ),
   .mem_2_reg(mem_2_reg_ctrl        ),
   .mem_write(mem_write_ctrl        ),
   .alu_src  (alu_src_ctrl          ),
   .reg_write(reg_write_ctrl        ),
   .jump     (jump_ctrl             )
);

// Bubble injection on stall
assign alu_op    = stall ? 2'b00 : alu_op_ctrl;
assign branch    = stall ? 1'b0  : branch_ctrl;
assign mem_read  = stall ? 1'b0  : mem_read_ctrl;
assign mem_2_reg = stall ? 1'b0  : mem_2_reg_ctrl;
assign mem_write = stall ? 1'b0  : mem_write_ctrl;
assign alu_src   = stall ? 1'b0  : alu_src_ctrl;
assign reg_write = stall ? 1'b0  : reg_write_ctrl;
assign jump      = stall ? 1'b0  : jump_ctrl;

register_file #(
   .DATA_W(64)
) register_file (
   .clk      (clk                     ),
   .arst_n   (arst_n                  ),
   .reg_write(reg_write_MEM_WB        ),
   .raddr_1  (instruction_IF_ID[19:15]),
   .raddr_2  (instruction_IF_ID[24:20]),
   .waddr    (rd_MEM_WB               ),
   .wdata    (regfile_wdata           ),
   .rdata_1  (regfile_rdata_1         ),
   .rdata_2  (regfile_rdata_2         )
);

immediate_extend_unit immediate_extend_u(
   .instruction       (instruction_IF_ID ),
   .immediate_extended(immediate_extended)
);

branch_unit #(
   .DATA_W(64)
) branch_unit (
   .current_pc        (current_pc_IF_ID  ),
   .immediate_extended(immediate_extended),
   .branch_pc         (branch_pc         ),
   .jump_pc           (jump_pc           )
);

// Branch decision in ID with forwarding
// Forward from EX/MEM (alu_out_EX_MEM) or from regfile_wdata (MEM/WB output) if needed.
// We CANNOT forward from EX stage (alu_out) because the result for the previous
// instruction may not be ready yet — in that case we must stall.
assign branch_operand_1 =
   (reg_write_EX_MEM && (rd_EX_MEM != 5'd0) && (rd_EX_MEM == instruction_IF_ID[19:15])) ? alu_out_EX_MEM :
   (reg_write_MEM_WB && (rd_MEM_WB != 5'd0) && (rd_MEM_WB == instruction_IF_ID[19:15])) ? regfile_wdata  :
                                                                                          regfile_rdata_1;

assign branch_operand_2 =
   (reg_write_EX_MEM && (rd_EX_MEM != 5'd0) && (rd_EX_MEM == instruction_IF_ID[24:20])) ? alu_out_EX_MEM :
   (reg_write_MEM_WB && (rd_MEM_WB != 5'd0) && (rd_MEM_WB == instruction_IF_ID[24:20])) ? regfile_wdata  :
                                                                                          regfile_rdata_2;

// Branch stall: if the instruction in ID is a branch and the previous instruction
// (in ID/EX) writes a register that this branch reads, we cannot forward in time —
// the EX result isn't ready until end of cycle. Stall 1 cycle.
// Also stall if previous is a load that writes a register the branch needs (load-use for branch).
assign branch_stall = branch_ctrl &&
   reg_write_ID_EX && (rd_ID_EX != 5'd0) &&
   ((rd_ID_EX == instruction_IF_ID[19:15]) || (rd_ID_EX == instruction_IF_ID[24:20]));

assign zero_id      = (branch_operand_1 == branch_operand_2);
assign branch_taken = branch_ctrl && zero_id && !branch_stall;
assign flush_IF_ID  = branch_taken || jump_ctrl;

// Hazard detection (load-use)
hazard_detection_unit hazard_detection_unit(
   .rs1_IF_ID     (instruction_IF_ID[19:15]),
   .rs2_IF_ID     (instruction_IF_ID[24:20]),
   .rd_ID_EX      (rd_ID_EX                ),
   .mem_read_ID_EX(mem_read_ID_EX          ),
   .stall         (load_use_stall          )
);

// ============================================================
// ID/EX pipeline registers
// ============================================================
reg_arstn_en #(.DATA_W(64)) signal_pc_ID_EX (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(current_pc_IF_ID), .dout(current_pc_ID_EX)
);

reg_arstn_en #(.DATA_W(64)) signal_rdata_1_ID_EX (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(regfile_rdata_1), .dout(regfile_rdata_1_ID_EX)
);

reg_arstn_en #(.DATA_W(64)) signal_rdata_2_ID_EX (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(regfile_rdata_2), .dout(regfile_rdata_2_ID_EX)
);

reg_arstn_en #(.DATA_W(64)) signal_imm_ID_EX (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(immediate_extended), .dout(immediate_extended_ID_EX)
);

reg_arstn_en #(.DATA_W(5)) signal_rs1_ID_EX (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(instruction_IF_ID[19:15]), .dout(rs1_ID_EX)
);

reg_arstn_en #(.DATA_W(5)) signal_rs2_ID_EX (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(instruction_IF_ID[24:20]), .dout(rs2_ID_EX)
);

reg_arstn_en #(.DATA_W(5)) signal_rd_ID_EX (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(instruction_IF_ID[11:7]), .dout(rd_ID_EX)
);

reg_arstn_en #(.DATA_W(5)) signal_funct_ID_EX (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din({instruction_IF_ID[30], instruction_IF_ID[25], instruction_IF_ID[14:12]}),
   .dout(funct_ID_EX)
);

reg_arstn_en #(.DATA_W(2)) signal_alu_op_ID_EX (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(alu_op), .dout(alu_op_ID_EX)
);

reg_arstn_en #(.DATA_W(1)) signal_branch_ID_EX (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(branch), .dout(branch_ID_EX)
);

reg_arstn_en #(.DATA_W(1)) signal_mem_read_ID_EX (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(mem_read), .dout(mem_read_ID_EX)
);

reg_arstn_en #(.DATA_W(1)) signal_mem_2_reg_ID_EX (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(mem_2_reg), .dout(mem_2_reg_ID_EX)
);

reg_arstn_en #(.DATA_W(1)) signal_mem_write_ID_EX (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(mem_write), .dout(mem_write_ID_EX)
);

reg_arstn_en #(.DATA_W(1)) signal_alu_src_ID_EX (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(alu_src), .dout(alu_src_ID_EX)
);

reg_arstn_en #(.DATA_W(1)) signal_reg_write_ID_EX (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(reg_write), .dout(reg_write_ID_EX)
);

reg_arstn_en #(.DATA_W(1)) signal_jump_ID_EX (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(jump), .dout(jump_ID_EX)
);

// ============================================================
// EX stage
// ============================================================
alu_control alu_ctrl(
   .func7_5    (funct_ID_EX[4]  ),
   .func7_0    (funct_ID_EX[3]  ),
   .func3      (funct_ID_EX[2:0]),
   .alu_op     (alu_op_ID_EX    ),
   .alu_control(alu_control     )
);

forwarding_unit forwarding_unit(
   .rs1_ID_EX       (rs1_ID_EX        ),
   .rs2_ID_EX       (rs2_ID_EX        ),
   .rd_EX_MEM       (rd_EX_MEM        ),
   .rd_MEM_WB       (rd_MEM_WB        ),
   .reg_write_EX_MEM(reg_write_EX_MEM ),
   .reg_write_MEM_WB(reg_write_MEM_WB ),
   .forward_a       (forward_a        ),
   .forward_b       (forward_b        )
);

mux_3 #(.DATA_W(64)) forward_a_mux (
   .input_a(regfile_rdata_1_ID_EX),
   .input_b(regfile_wdata        ),
   .input_c(alu_out_EX_MEM       ),
   .select (forward_a            ),
   .mux_out(alu_in_0_forwarded   )
);

mux_3 #(.DATA_W(64)) forward_b_mux (
   .input_a(regfile_rdata_2_ID_EX    ),
   .input_b(regfile_wdata            ),
   .input_c(alu_out_EX_MEM           ),
   .select (forward_b                ),
   .mux_out(regfile_rdata_2_forwarded)
);

mux_2 #(.DATA_W(64)) alu_operand_mux (
   .input_a (immediate_extended_ID_EX ),
   .input_b (regfile_rdata_2_forwarded),
   .select_a(alu_src_ID_EX            ),
   .mux_out (alu_operand_2            )
);

alu #(.DATA_W(64)) alu (
   .alu_in_0 (alu_in_0_forwarded),
   .alu_in_1 (alu_operand_2     ),
   .alu_ctrl (alu_control       ),
   .alu_out  (alu_out           ),
   .zero_flag(zero_flag         ),
   .overflow ()
);

// ============================================================
// EX/MEM pipeline registers
// ============================================================
reg_arstn_en #(.DATA_W(64)) signal_alu_out_EX_MEM (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(alu_out), .dout(alu_out_EX_MEM)
);

reg_arstn_en #(.DATA_W(64)) signal_rdata_2_EX_MEM (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(regfile_rdata_2_forwarded), .dout(regfile_rdata_2_EX_MEM)
);

reg_arstn_en #(.DATA_W(5)) signal_rd_EX_MEM (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(rd_ID_EX), .dout(rd_EX_MEM)
);

reg_arstn_en #(.DATA_W(1)) signal_mem_read_EX_MEM (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(mem_read_ID_EX), .dout(mem_read_EX_MEM)
);

reg_arstn_en #(.DATA_W(1)) signal_mem_write_EX_MEM (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(mem_write_ID_EX), .dout(mem_write_EX_MEM)
);

reg_arstn_en #(.DATA_W(1)) signal_mem_2_reg_EX_MEM (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(mem_2_reg_ID_EX), .dout(mem_2_reg_EX_MEM)
);

reg_arstn_en #(.DATA_W(1)) signal_reg_write_EX_MEM (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(reg_write_ID_EX), .dout(reg_write_EX_MEM)
);

// ============================================================
// MEM stage
// ============================================================
sram_BW64 #(
   .ADDR_W(10)
) data_memory (
   .clk      (clk                   ),
   .addr     (alu_out_EX_MEM        ),
   .wen      (mem_write_EX_MEM      ),
   .ren      (mem_read_EX_MEM       ),
   .wdata    (regfile_rdata_2_EX_MEM),
   .rdata    (mem_data              ),
   .addr_ext (addr_ext_2            ),
   .wen_ext  (wen_ext_2             ),
   .ren_ext  (ren_ext_2             ),
   .wdata_ext(wdata_ext_2           ),
   .rdata_ext(rdata_ext_2           )
);

// ============================================================
// MEM/WB pipeline registers
// ============================================================
reg_arstn_en #(.DATA_W(64)) signal_alu_out_MEM_WB (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(alu_out_EX_MEM), .dout(alu_out_MEM_WB)
);

reg_arstn_en #(.DATA_W(64)) signal_mem_data_MEM_WB (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(mem_data), .dout(mem_data_MEM_WB)
);

reg_arstn_en #(.DATA_W(5)) signal_rd_MEM_WB (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(rd_EX_MEM), .dout(rd_MEM_WB)
);

reg_arstn_en #(.DATA_W(1)) signal_mem_2_reg_MEM_WB (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(mem_2_reg_EX_MEM), .dout(mem_2_reg_MEM_WB)
);

reg_arstn_en #(.DATA_W(1)) signal_reg_write_MEM_WB (
   .clk(clk), .arst_n(arst_n), .en(enable),
   .din(reg_write_EX_MEM), .dout(reg_write_MEM_WB)
);

// ============================================================
// WB stage
// ============================================================
mux_2 #(.DATA_W(64)) regfile_data_mux (
   .input_a (mem_data_MEM_WB ),
   .input_b (alu_out_MEM_WB  ),
   .select_a(mem_2_reg_MEM_WB),
   .mux_out (regfile_wdata   )
);

endmodule


// ============================================================
// Forwarding unit
// ============================================================
module forwarding_unit(
   input  wire [4:0] rs1_ID_EX,
   input  wire [4:0] rs2_ID_EX,
   input  wire [4:0] rd_EX_MEM,
   input  wire [4:0] rd_MEM_WB,
   input  wire       reg_write_EX_MEM,
   input  wire       reg_write_MEM_WB,
   output wire [1:0] forward_a,
   output wire [1:0] forward_b
);
   assign forward_a =
      (reg_write_EX_MEM && (rd_EX_MEM != 5'd0) && (rd_EX_MEM == rs1_ID_EX)) ? 2'b10 :
      (reg_write_MEM_WB && (rd_MEM_WB != 5'd0) && (rd_MEM_WB == rs1_ID_EX)) ? 2'b01 :
                                                                              2'b00;
   assign forward_b =
      (reg_write_EX_MEM && (rd_EX_MEM != 5'd0) && (rd_EX_MEM == rs2_ID_EX)) ? 2'b10 :
      (reg_write_MEM_WB && (rd_MEM_WB != 5'd0) && (rd_MEM_WB == rs2_ID_EX)) ? 2'b01 :
                                                                              2'b00;
endmodule


// ============================================================
// 3-to-1 multiplexer
// ============================================================
module mux_3 #(
   parameter integer DATA_W = 64
)(
   input  wire [DATA_W-1:0] input_a,
   input  wire [DATA_W-1:0] input_b,
   input  wire [DATA_W-1:0] input_c,
   input  wire [       1:0] select,
   output wire [DATA_W-1:0] mux_out
);
   assign mux_out = (select == 2'b10) ? input_c :
                    (select == 2'b01) ? input_b :
                                        input_a;
endmodule
