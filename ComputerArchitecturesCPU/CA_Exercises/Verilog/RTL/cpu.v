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
wire              zero_flag_EX_MEM;
wire [      63:0] branch_pc,updated_pc,current_pc, current_pc_IF_ID, current_pc_ID_EX, branch_pc_EX_MEM,jump_pc;
wire [      31:0] instruction, instruction_IF_ID;
wire [       4:0] instruction11_7_ID_EX, instruction11_7_EX_MEM,
                  instruction11_7_MEM_WB;
wire [       3:0] instruction30comma25comma14_12_ID_EX;
wire [       1:0] alu_op, alu_op_ID_EX;
wire [       3:0] alu_control;
wire              reg_dst,branch,mem_read,mem_2_reg,
                  mem_write,alu_src, reg_write, jump;

wire              branch_ID_EX,mem_read_ID_EX,mem_2_reg_ID_EX,
                  mem_write_ID_EX,alu_src_ID_EX, reg_write_ID_EX, jump_ID_EX;
wire              branch_EX_MEM,mem_read_EX_MEM,mem_2_reg_EX_MEM,
                  mem_write_EX_MEM, reg_write_EX_MEM, jump_EX_MEM;
wire              mem_2_reg_MEM_WB, reg_write_MEM_WB;
wire [       4:0] regfile_waddr;
wire [      63:0] regfile_wdata,mem_data, mem_data_MEM_WB,alu_out,
                  regfile_rdata_1,regfile_rdata_2,regfile_rdata_1_ID_EX,regfile_rdata_2_ID_EX,
                  regfile_rdata_2_EX_MEM,alu_operand_2;

wire [      63:0] alu_out_EX_MEM, alu_out_MEM_WB;

wire signed [63:0] immediate_extended,
                   immediate_extended_ID_EX;

immediate_extend_unit immediate_extend_u(
    .instruction         (instruction_IF_ID),
    .immediate_extended  (immediate_extended)
);

pc #(
   .DATA_W(64)
) program_counter (
   .clk       (clk             ),
   .arst_n    (arst_n          ),
   .branch_pc (branch_pc_EX_MEM),
   .jump_pc   (branch_pc_EX_MEM), 
   .zero_flag (zero_flag_EX_MEM),       
   .branch    (branch_EX_MEM   ),
   .jump      (jump_EX_MEM     ),
   .current_pc(current_pc_ID_EX),
   .enable    (enable          ),
   .updated_pc(updated_pc      )
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

sram_BW64 #(
   .ADDR_W(10)
) data_memory(
   .clk      (clk            ),
   .addr     (alu_out_EX_MEM ),
   .wen      (mem_write_EX_MEM),     
   .ren      (mem_read_EX_MEM ),
   .wdata    (regfile_rdata_2_EX_MEM),
   .rdata    (mem_data       ),   
   .addr_ext (addr_ext_2     ),
   .wen_ext  (wen_ext_2      ),
   .ren_ext  (ren_ext_2      ),
   .wdata_ext(wdata_ext_2    ),
   .rdata_ext(rdata_ext_2    )
);

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

reg_arstn_en #(
   .DATA_W(32)
)signal_pipe_IF_ID(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (instruction      ),
   .dout    (instruction_IF_ID)
);

reg_arstn_en #(
   .DATA_W(64)
)signal_pc_IF_ID(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (current_pc       ),
   .dout    (current_pc_IF_ID )
);

reg_arstn_en #(
   .DATA_W(64)
)signal_pc_ID_EX(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (current_pc_IF_ID ),
   .dout    (current_pc_ID_EX )
);

reg_arstn_en #(
   .DATA_W(64)
)signal_pc_EX_MEM(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (branch_pc        ),
   .dout    (branch_pc_EX_MEM )
);

reg_arstn_en #(
   .DATA_W(64)
)signal_rdata_1_ID_EX(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (regfile_rdata_1  ),
   .dout    (regfile_rdata_1_ID_EX)
);

reg_arstn_en #(
   .DATA_W(5)
)signal_instruction11_7_ID_EX(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (instruction[11:7]  ),
   .dout    (instruction11_7_ID_EX)
);

reg_arstn_en #(
   .DATA_W(5)
)signal_instruction11_7_ID_EX(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (instruction[11:7]  ),
   .dout    (instruction11_7_ID_EX)
);

reg_arstn_en #(
   .DATA_W(5)
)signal_instruction11_7_EX_MEM(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (instruction11_7_ID_EX ),
   .dout    (instruction11_7_EX_MEM)
);

reg_arstn_en #(
   .DATA_W(5)
)signal_instruction11_7_MEM_WB(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (instruction11_7_EX_MEM ),
   .dout    (instruction11_7_MEM_WB)
);

reg_arstn_en #(
   .DATA_W(64)
)signal_immediate_extended_ID_EX(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (immediate_extended ),
   .dout    (immediate_extended_ID_EX)
);

reg_arstn_en #(
   .DATA_W(5)
)signal_instruction30comma25comma14_12_ID_EX(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     ({instruction[30], instruction[25], instruction[14:12]}),
   .dout    (instruction30comma25comma14_12_ID_EX)
);

reg_arstn_en #(
   .DATA_W(2)
)signal_alu_op_ID_EX(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (alu_op),
   .dout    (alu_op_ID_EX)
);

reg_arstn_en #(
   .DATA_W(1)
)signal_branch_ID_EX(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (branch),
   .dout    (branch_ID_EX)
);

reg_arstn_en #(
   .DATA_W(1)
)signal_mem_read_ID_EX(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (mem_read),
   .dout    (mem_read_ID_EX)
);

reg_arstn_en #(
   .DATA_W(1)
)signal_mem_2_reg_ID_EX(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (mem_2_reg),
   .dout    (mem_2_reg_ID_EX)
);

reg_arstn_en #(
   .DATA_W(1)
)signal_mem_write_ID_EX(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (mem_write),
   .dout    (mem_write_ID_EX)
);

reg_arstn_en #(
   .DATA_W(1)
)signal_alu_src_ID_EX(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (alu_src),
   .dout    (alu_src_ID_EX)
);

reg_arstn_en #(
   .DATA_W(1)
)signal_reg_write_ID_EX(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (reg_write),
   .dout    (reg_write_ID_EX)
);

reg_arstn_en #(
   .DATA_W(1)
)signal_jump_ID_EX(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (jump),
   .dout    (jump_ID_EX)
);

reg_arstn_en #(
   .DATA_W(64)
)signal_alu_out_EX_MEM(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (alu_out          ),
   .dout    (alu_out_EX_MEM   )
);

reg_arstn_en #(
   .DATA_W(64)
)signal_alu_out_MEM_WB(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (alu_out_EX_MEM   ),
   .dout    (alu_out_MEM_WB   )
);

reg_arstn_en #(
   .DATA_W(64)
)signal_mem_data_MEM_WB(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (mem_data   ),
   .dout    (mem_data_MEM_WB   )
);

reg_arstn_en #(
   .DATA_W(1)
)signal_zero_flag_EX_MEM(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (zero_flag        ),
   .dout    (zero_flag_EX_MEM )
);

reg_arstn_en #(
   .DATA_W(1)
)signal_jump_EX_MEM(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (jump_ID_EX       ),
   .dout    (jump_EX_MEM      )
);

reg_arstn_en #(
   .DATA_W(1)
)signal_branch_EX_MEM(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (branch_ID_EX     ),
   .dout    (branch_EX_MEM    ) 
);

reg_arstn_en #(
   .DATA_W(1)
)signal_mem_read_EX_MEM(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (mem_read_ID_EX       ),
   .dout    (mem_read_EX_MEM      )
);

reg_arstn_en #(
   .DATA_W(1)
)signal_mem_write_EX_MEM(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (mem_write_ID_EX       ),
   .dout    (mem_write_EX_MEM      )
);

reg_arstn_en #(
   .DATA_W(1)
)signal_mem_2_reg_EX_MEM(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (mem_2_reg_ID_EX       ),
   .dout    (mem_2_reg_EX_MEM      )
);

reg_arstn_en #(
   .DATA_W(1)
)signal_reg_write_EX_MEM(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (reg_write_ID_EX       ),
   .dout    (reg_write_EX_MEM      )
);

reg_arstn_en #(
   .DATA_W(64)
)signal_regfile_rdata_2_EX_MEM(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (regfile_rdata_2_ID_EX ),
   .dout    (regfile_rdata_2_EX_MEM)
);

reg_arstn_en #(
   .DATA_W(1)
)signal_mem_2_reg_MEM_WB(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (mem_2_reg_EX_MEM ),
   .dout    (mem_2_reg_MEM_WB )
);

reg_arstn_en #(
   .DATA_W(1)
)signal_reg_write_MEM_WB(
   .clk     (clk              ),
   .arst_n  (arst_n           ),
   .en      (enable           ),
   .din     (reg_write_EX_MEM ),
   .dout    (reg_write_MEM_WB )
);


register_file #(
   .DATA_W(64)
) register_file(
   .clk      (clk               ),
   .arst_n   (arst_n            ),
   .reg_write(reg_write_MEM_WB  ),
   .raddr_1  (instruction_IF_ID[19:15]),
   .raddr_2  (instruction_IF_ID[24:20]),
   .waddr    (instruction11_7_MEM_WB), 
   .wdata    (regfile_wdata     ),
   .rdata_1  (regfile_rdata_1   ),
   .rdata_2  (regfile_rdata_2   )
);

alu_control alu_ctrl(
   .func7_5       (instruction30comma25comma14_12_ID_EX[4]  ),
   .func7_0       (instruction30comma25comma14_12_ID_EX[3]  ),
   .func3         (instruction30comma25comma14_12_ID_EX[2:0]),
   .alu_op        (alu_op_ID_EX                             ),
   .alu_control   (alu_control                              )
);

mux_2 #(
   .DATA_W(64)
) alu_operand_mux (
   .input_a (immediate_extended_ID_EX),
   .input_b (regfile_rdata_2_ID_EX   ),
   .select_a(alu_src_ID_EX           ),
   .mux_out (alu_operand_2           )
);

alu#(
   .DATA_W(64)
) alu(
   .alu_in_0 (regfile_rdata_1_ID_EX),
   .alu_in_1 (alu_operand_2   ),
   .alu_ctrl (alu_control     ),
   .alu_out  (alu_out         ),
   .zero_flag(zero_flag       ),
   .overflow (                )
);

mux_2 #(
   .DATA_W(64)
) regfile_data_mux (
   .input_a  (mem_data_MEM_WB ),  
   .input_b  (alu_out_MEM_WB  ),
   .select_a (mem_2_reg_MEM_WB),
   .mux_out  (regfile_wdata)
);

branch_unit#(
   .DATA_W(64)
)branch_unit(
   .current_pc         (current_pc_ID_EX  ),
   .immediate_extended (immediate_extended_ID_EX),
   .branch_pc          (branch_pc         ),
   .jump_pc            (jump_pc           )
);


endmodule


