// module: Control
// Function: Generates the control signals for each one of the datapath resources

module control_unit(
      input  wire [6:0] opcode,
      output reg  [1:0] alu_op,
      output reg        reg_dst,
      output reg        branch,
      output reg        mem_read,
      output reg        mem_2_reg,
      output reg        mem_write,
      output reg        alu_src,
      output reg        reg_write,
      output reg        jump
   );

   // RISC-V opcode[6:0] (see RISC-V greensheet)
   parameter integer ALU_R      = 7'b0110011;
   parameter integer ALU_I      = 7'b0010011;
   parameter integer BRANCH_EQ  = 7'b1100011;
   parameter integer JUMP       = 7'b1101111;
   parameter integer LOAD       = 7'b0000011;
   parameter integer STORE      = 7'b0100011;

   // RISC-V ALUOp[1:0] (see book Figure 4.12)
   parameter [1:0] ADD_OPCODE     = 2'b00;
   parameter [1:0] SUB_OPCODE     = 2'b01;
   parameter [1:0] R_TYPE_OPCODE  = 2'b10;

   //The behavior of the control unit can be found in Chapter 4, Figure 4.18

   always@(*)begin

      case(opcode)
         ALU_R:begin
            alu_src   = 1'b0;
            mem_2_reg = 1'b0;
            reg_write = 1'b1;
            mem_read  = 1'b0;
            mem_write = 1'b0;
            branch    = 1'b0;
            alu_op    = R_TYPE_OPCODE;
            jump      = 1'b0;
         end
         ALU_I:begin // Only supporting ADDI for now.
            alu_src   = 1'b1;
            mem_2_reg = 1'b0;
            reg_write = 1'b1;
            mem_read  = 1'b0;
            mem_write = 1'b0;
            branch    = 1'b0;
            alu_op    = ADD_OPCODE;
            jump      = 1'b0;
         end
         BRANCH_EQ:begin
            alu_src   = 1'b0;
            mem_2_reg = 1'b0;
            reg_write = 1'b0;
            mem_read  = 1'b0;
            mem_write = 1'b0;
            branch    = 1'b1;
            alu_op    = SUB_OPCODE;
            jump      = 1'b0;
         end
         JUMP:begin
            alu_src   = 1'b0;
            mem_2_reg = 1'b0;
            reg_write = 1'b0;
            mem_read  = 1'b0;
            mem_write = 1'b0;
            branch    = 1'b0;
            alu_op    = SUB_OPCODE;
            jump      = 1'b1;
         end
         LOAD:begin
            alu_src   = 1'b1;
            mem_2_reg = 1'b1;
            reg_write = 1'b1;
            mem_read  = 1'b1;
            mem_write = 1'b0;
            branch    = 1'b0;
            alu_op    = ADD_OPCODE;
            jump      = 1'b0;
         end
         STORE:begin
            alu_src   = 1'b1;
            mem_2_reg = 1'b0;
            reg_write = 1'b0;
            mem_read  = 1'b0;
            mem_write = 1'b1;
            branch    = 1'b0;
            alu_op    = ADD_OPCODE;
            jump      = 1'b0;
         end
         default:begin
            alu_src   = 1'b0;
            mem_2_reg = 1'b0;
            reg_write = 1'b0;
            mem_read  = 1'b0;
            mem_write = 1'b0;
            branch    = 1'b0;
            alu_op    = R_TYPE_OPCODE;
            jump      = 1'b0;
         end
      endcase
   end

endmodule



// module: Hazard Control Unit
// Function: Forwarding/Stalling for hazards

module hazard_control_unit(
      input arst_n,
      input  wire [6:0] instruction_opcode_ID_EX,
      input  wire [4:0] reg_rs1_ID_EX,
      input  wire [4:0] reg_rt_ID_EX,// temp rs2
      input  wire [4:0] reg_rd_EX_MEM,
      input  wire [4:0] reg_rd_MEM_WB,

      input wire reg_write_EX_MEM,
      input wire reg_write_MEM_WB,

      input  wire [6:0] instruction_opcode_IF_ID,
      input  wire [4:0] reg_rs1_IF_ID,
      input  wire [4:0] reg_rt_IF_ID,// temp rs2
      input  wire [4:0] reg_rd_ID_EX,
      input wire mem_2_reg_ID_EX,
      output reg stall_IF,
      output reg stall_ID,

      output reg  [1:0] forward_a,
      output reg  [1:0] forward_b
   );

// RISC-V opcode[6:0] (see RISC-V greensheet)
parameter integer ALU_I      = 7'b0010011;
parameter integer LOAD       = 7'b0000011;

// forwarding
wire [4:0] reg_rs2_ID_EX;
assign reg_rs2_ID_EX = (instruction_opcode_ID_EX == ALU_I || instruction_opcode_ID_EX == LOAD )? 5'bx : reg_rt_ID_EX; // I-Type does not have rt(rs2).

// forward valid case: previous instruction has a dependent reg_write (MEM or WB stage) and is not on x0 (constant-0).
wire forward_valid_EX, forward_valid_MEM;
assign forward_valid_EX = reg_write_EX_MEM && (reg_rd_EX_MEM != 0);
assign forward_valid_MEM = reg_write_MEM_WB && (reg_rd_MEM_WB != 0);

// rs1 forwarding
always @(*) begin
    if(forward_valid_EX && (reg_rd_EX_MEM == reg_rs1_ID_EX)) forward_a = 2'b10;  
    else if (forward_valid_MEM && (reg_rd_MEM_WB == reg_rs1_ID_EX)) forward_a = 2'b01;
    else forward_a = 2'b00;  
end

// rs2 forwarding
always @(*) begin
    if(forward_valid_EX && (reg_rd_EX_MEM == reg_rs2_ID_EX)) forward_b = 2'b10;  
    else if (forward_valid_MEM && (reg_rd_MEM_WB == reg_rs2_ID_EX)) forward_b = 2'b01;
    else forward_b = 2'b00;  
end


// stalling
wire [4:0] reg_rs2_IF_ID;
assign reg_rs2_IF_ID = (instruction_opcode_IF_ID == ALU_I || instruction_opcode_IF_ID == LOAD)? 5'b0 : reg_rt_IF_ID; // I-Type does not have rt (rs2), use the static x0 instead.

// stall valid case: previous instruction has a dependent load and is not on x0 (constant-0).
wire stall_valid;
assign stall_valid = mem_2_reg_ID_EX && (reg_rd_ID_EX != 0);

// the later pipeline should be stalled
always@(*) begin
    stall_IF = (stall_valid && (reg_rd_ID_EX == reg_rs1_IF_ID || reg_rd_ID_EX == reg_rs2_IF_ID));
    stall_ID = (stall_valid && (reg_rd_ID_EX == reg_rs1_IF_ID || reg_rd_ID_EX == reg_rs2_IF_ID));
end


endmodule