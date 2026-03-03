//Module: CPU
//Function: CPU is the top design of the RISC-V processor

//Inputs:
//	clk: main clock
//	arst_n: reset 
// enable: Starts the execution
//	addr_ext: Address for reading/writing content to Instruction Memory
//	wen_ext: Write enable for Instruction Memory
// ren_ext: Read enable for Instruction Memory
//	wdata_ext: Write word for Instruction Memory
//	addr_ext_2: Address for reading/writing content to Data Memory
//	wen_ext_2: Write enable for Data Memory
// ren_ext_2: Read enable for Data Memory
//	wdata_ext_2: Write word for Data Memory

// Outputs:
//	rdata_ext: Read data from Instruction Memory
//	rdata_ext_2: Read data from Data Memory



module cpu(
		input  wire			  clk,
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

wire              zero_flag;
wire [      63:0] branch_pc,updated_pc,current_pc,jump_pc;
wire [      31:0] instruction;
wire [       1:0] alu_op;
wire [       3:0] alu_control;
wire              reg_dst,branch,mem_read,mem_2_reg,
                  mem_write,alu_src, reg_write, jump;
wire [       4:0] regfile_waddr;
wire [      63:0] regfile_wdata,dram_data,alu_out,
                  regfile_rdata_1,regfile_rdata_2,
                  alu_operand_2;

wire signed [63:0] immediate_extended;

// control_bus
wire [9:0] control_ID_original, control_ID,  control_ID_EX;
wire [3:0] control_EX_MEM;
wire [1:0] control_MEM_WB;

wire [4:0] regfile_waddr_MEM_WB;

// enable signal with stalling
wire stall_IF, stall_ID, enable_IF, enable_ID;
assign enable_IF = enable & (~stall_IF);
assign enable_ID = enable & (~stall_ID);

// IF begin
pc #(
   .DATA_W(64)
) program_counter (
   .clk       (clk       ),
   .arst_n    (arst_n    ),
   .branch_pc (branch_pc ),
   .jump_pc   (jump_pc   ),
   .zero_flag (zero_flag ),
   .branch    (    ),
   .jump      (      ),
   .current_pc(current_pc),
   .enable    (enable_IF    ),// enable_IF, if stalling, current pc stops updating.
   .updated_pc(updated_pc)
);

sram_BW32 #(
   .ADDR_W(9 )
) instruction_memory(
   .clk      (clk           ),
   .addr     (current_pc    ),
   .wen      (1'b0          ),
   .ren      (1'b1          ),
   .wdata    (32'b0         ),
   .rdata    (instruction   ),   
   .addr_ext (addr_ext      ),
   .wen_ext  (wen_ext       ), 
   .ren_ext  (ren_ext       ),
   .wdata_ext(wdata_ext     ),
   .rdata_ext(rdata_ext     )
);
// IF End

// IF_ID Begin
wire [      31:0] instruction_IF_ID;
wire [      63:0] updated_pc_IF_ID;

reg_arstn_en#(
    .DATA_W (32)
)instruction_fw_IF_ID(
    .clk     ( clk     ),
    .arst_n  ( arst_n  ),
    .en      ( enable_IF      ),// enable_IF, if stalling, no IF_ID reg update.
    .din     ( instruction     ),
    .dout    ( instruction_IF_ID    )
);

reg_arstn_en#(
    .DATA_W (64)
)updated_pc_fw_IF_ID(
    .clk     ( clk     ),
    .arst_n  ( arst_n  ),
    .en      ( enable_IF      ),// enable_IF, if stalling, no IF_ID reg update.
    .din     ( updated_pc     ),
    .dout    ( updated_pc_IF_ID    )
);
// IF_ID End

// ID Begin
control_unit control_unit(
   .opcode   (instruction_IF_ID[6:0]),
   .alu_op   (alu_op          ),
   .reg_dst  (reg_dst         ),
   .branch   (branch          ),
   .mem_read (mem_read        ),
   .mem_2_reg(mem_2_reg       ),
   .mem_write(mem_write       ),
   .alu_src  (alu_src         ),
   .reg_write(reg_write       ),
   .jump     (jump            )
);

register_file #(
   .DATA_W(64)
) register_file(
   .clk      (clk               ),
   .arst_n   (arst_n            ),
   .reg_write(control_MEM_WB[0]         ), // reg_write, WB
   .raddr_1  (instruction_IF_ID[19:15]),
   .raddr_2  (instruction_IF_ID[24:20]),
   .waddr    (regfile_waddr_MEM_WB ),// rd, WB
   .wdata    (regfile_wdata     ),
   .rdata_1  (regfile_rdata_1   ),
   .rdata_2  (regfile_rdata_2   )
);

alu_control alu_ctrl(
   .func7          (instruction_IF_ID[31:25]),
   .func3          (instruction_IF_ID[14:12]),
   .alu_op         (alu_op            ),
   .alu_control    (alu_control       ) // 4 bit
);

immediate_extend_unit immediate_extend_u(
    .instruction         (instruction_IF_ID),
    .immediate_extended  (immediate_extended)
);
// ID End

// ID_EX Begin
wire [      31:0] instruction_ID_EX;
wire [      63:0] updated_pc_ID_EX, immediate_extended_ID_EX;
wire [      63:0] regfile_rdata_1_ID_EX, regfile_rdata_2_ID_EX;

// control bus // 10 bit
//    alu_src(9), alu_control(8:5), branch(4),
//    mem_read(3), mem_write(2),
//    mem_2_reg(1), reg_write(0)
assign control_ID_original = { alu_src, alu_control, branch,
                        mem_read, mem_write,
                        mem_2_reg, reg_write
                    };        

// if stalling, control bits all zeroed out.
mux_2 #(
   .DATA_W(10)
) hazard_control_mux (
   .input_a (control_ID_original),
   .input_b (10'b0    ), 
   .select_a(enable_ID           ),// enable_ID, if stalling, idling next step control signal.
   .mux_out (control_ID     )
);    

reg_arstn_en#(
    .DATA_W (10)
)control_fw_ID_EX(
    .clk     ( clk     ),
    .arst_n  ( arst_n  ),
    .en      ( enable      ),
    .din     ( control_ID),
    .dout    ( control_ID_EX)
);

reg_arstn_en#(
    .DATA_W (32)
)instruction_fw_ID_EX(
    .clk     ( clk     ),
    .arst_n  ( arst_n  ),
    .en      ( enable      ),
    .din     ( instruction_IF_ID     ),
    .dout    ( instruction_ID_EX    )
);

reg_arstn_en#(
    .DATA_W (64)
)updated_pc_fw_ID_EX(
    .clk     ( clk     ),
    .arst_n  ( arst_n  ),
    .en      ( enable      ),
    .din     ( updated_pc_IF_ID     ),
    .dout    ( updated_pc_ID_EX    )
);

reg_arstn_en#(
    .DATA_W (64)
)regfile_data_1_fw_ID_EX(
    .clk     ( clk     ),
    .arst_n  ( arst_n  ),
    .en      ( enable      ),
    .din     ( regfile_rdata_1     ),
    .dout    ( regfile_rdata_1_ID_EX    )
);

reg_arstn_en#(
    .DATA_W (64)
)regfile_data_2_fw_ID_EX(
    .clk     ( clk     ),
    .arst_n  ( arst_n  ),
    .en      ( enable      ),
    .din     ( regfile_rdata_2     ),
    .dout    ( regfile_rdata_2_ID_EX    )
);

reg_arstn_en#(
    .DATA_W (64)
)immediate_fw_ID_EX(
    .clk     ( clk     ),
    .arst_n  ( arst_n  ),
    .en      ( enable      ),
    .din     ( immediate_extended     ),
    .dout    ( immediate_extended_ID_EX    )
);
// ID_EX End


// not fully-correct branch or jump, without harzard control
branch_unit#(
   .DATA_W(64)
)branch_unit(
   .updated_pc         (updated_pc_ID_EX        ),
   .immediate_extended (immediate_extended_ID_EX),
   .branch_pc          (branch_pc         ),
   .jump_pc            (jump_pc           )
);

// hazard control begin
wire [      63:0] alu_operand_a, alu_operand_b, alu_out_EX_MEM;
wire [      31:0] instruction_EX_MEM;
wire [       1:0] forward_A, forward_B;

hazard_control_unit hazard_control_unit_1(
    .arst_n           (  arst_n  ),
    .instruction_opcode_ID_EX (  instruction_ID_EX[6:0]  ), // instr_opcode
    .reg_rs1_ID_EX     (  instruction_ID_EX[19:15]    ),
    .reg_rt_ID_EX     (  instruction_ID_EX[24:20]    ),
    .reg_rd_EX_MEM    (  instruction_EX_MEM[11:7]   ),
    .reg_rd_MEM_WB    (  regfile_waddr_MEM_WB   ),
    .reg_write_EX_MEM (  control_EX_MEM[0]),
    .reg_write_MEM_WB (  control_MEM_WB[0]), // reg_write
    
    .instruction_opcode_IF_ID (  instruction_IF_ID[6:0]  ),// instr_opcode
    .reg_rs1_IF_ID     (  instruction_IF_ID[19:15]  ),
    .reg_rt_IF_ID     (  instruction_IF_ID[24:20]  ),
    .reg_rd_ID_EX     (  instruction_ID_EX[11:7]  ),
    .mem_2_reg_ID_EX  (  control_ID_EX[1]  ), // mem_2_reg(1bit)

    .stall_IF         (  stall_IF  ),
    .stall_ID         (  stall_ID  ),
    .forward_a        (  forward_A       ),
    .forward_b        (  forward_B       )
);

// operand 1
mux_3#(
    .DATA_W  (64)
)mux_3_alu_operand_1(
    .input_a  ( regfile_rdata_1_ID_EX  ),
    .input_b  ( alu_out_EX_MEM  ),
    .input_c  ( regfile_wdata  ),
    .select_a ( forward_A ),
    .mux_out  ( alu_operand_a  )
);

// operand 2
mux_3#(
    .DATA_W  (64)
)mux_3_alu_operand_2(
    .input_a  ( alu_operand_2  ),
    .input_b  ( alu_out_EX_MEM  ),
    .input_c  ( regfile_wdata  ),
    .select_a ( forward_B ),
    .mux_out  ( alu_operand_b  )
);
// hazard control end

// EX Begin

mux_2 #(
   .DATA_W(64)
) alu_operand_mux (
   .input_a (immediate_extended_ID_EX),
   .input_b (regfile_rdata_2_ID_EX    ),
   .select_a(control_ID_EX[9]        ),// alu_src
   .mux_out (alu_operand_2     )
);

wire [      63:0] regfile_rdata_2_EX_MEM;

alu#(
   .DATA_W(64)
) alu(
   .alu_in_0 (alu_operand_a   ),
   .alu_in_1 (alu_operand_b   ),
   .alu_ctrl (control_ID_EX[8:5]     ),// alu_control
   .alu_out  (alu_out         ),
   .zero_flag(zero_flag       ),
   .overflow (                )
);
// EX end

// EX_MEM Begin

// mem_read, mem_write, mem_2_reg, reg_write
reg_arstn_en#(
    .DATA_W (4)
)control_fw_EX_MEM(
    .clk     ( clk     ),
    .arst_n  ( arst_n  ),
    .en      ( enable      ),
    .din     ( control_ID_EX[3:0]   ),
    .dout    ( control_EX_MEM)
);

reg_arstn_en#(
    .DATA_W (64)
)alu_out_fw_EX_MEM(
    .clk     ( clk     ),
    .arst_n  ( arst_n  ),
    .en      ( enable      ),
    .din     ( alu_out     ),
    .dout    ( alu_out_EX_MEM    )
);

reg_arstn_en#(
    .DATA_W (64)
)regfile_data_2_fw_EX_MEM(
    .clk     ( clk     ),
    .arst_n  ( arst_n  ),
    .en      ( enable      ),
    .din     ( regfile_rdata_2_ID_EX     ),
    .dout    ( regfile_rdata_2_EX_MEM    )
);

reg_arstn_en#(
    .DATA_W (32)
)instruction_fw_EX_MEM(
    .clk     ( clk     ),
    .arst_n  ( arst_n  ),
    .en      ( enable      ),
    .din     ( instruction_ID_EX     ),
    .dout    ( instruction_EX_MEM    )
);
// EX_MEM End

// MEM Begin
sram_BW64 #(
   .ADDR_W(10)
) data_memory(
   .clk      (clk            ),
   .addr     (alu_out_EX_MEM        ),// alu_out
   .wen      (control_EX_MEM[2]      ),// mem_write
   .ren      (control_EX_MEM[3]       ),// mem_read
   .wdata    (regfile_rdata_2_EX_MEM),// regfile_data_2
   .rdata    (dram_data       ),   
   .addr_ext (addr_ext_2     ),
   .wen_ext  (wen_ext_2      ),
   .ren_ext  (ren_ext_2      ),
   .wdata_ext(wdata_ext_2    ),
   .rdata_ext(rdata_ext_2    )
);
// MEM End

// MEM_WB Begin
wire [      63:0] dram_data_MEM_WB, alu_out_MEM_WB;

reg_arstn_en#(
    .DATA_W (2)
)control_bundle_MEM_WB(
    .clk     ( clk     ),
    .arst_n  ( arst_n  ),
    .en      ( enable      ),
    .din     ( control_EX_MEM[1:0]), // mem_2_reg, reg_write
    .dout    ( control_MEM_WB   )
);

reg_arstn_en#(
    .DATA_W (64)
)dram_data_fw_MEM_WB(
    .clk     ( clk     ),
    .arst_n  ( arst_n  ),
    .en      ( enable      ),
    .din     ( dram_data     ),
    .dout    ( dram_data_MEM_WB    )
);

reg_arstn_en#(
    .DATA_W (64)
)alu_out_fw_MEM_WB(
    .clk     ( clk     ),
    .arst_n  ( arst_n  ),
    .en      ( enable      ),
    .din     ( alu_out_EX_MEM     ),
    .dout    ( alu_out_MEM_WB     )
);

reg_arstn_en#(
    .DATA_W (5)
)regfile_waddr_fw_MEM_WB(
    .clk     ( clk     ),
    .arst_n  ( arst_n  ),
    .en      ( enable      ),
    .din     ( instruction_EX_MEM[11:7]     ), // RV32I: rd
    .dout    ( regfile_waddr_MEM_WB     )
);
// MEM_WB end

// WB Begin
mux_2 #(
   .DATA_W(64)
) regfile_data_mux (
   .input_a  (dram_data_MEM_WB    ),
   .input_b  (alu_out_MEM_WB      ),
   .select_a (control_MEM_WB[1]     ),// mem_to_reg
   .mux_out  (regfile_wdata)
);
// WB end


endmodule


