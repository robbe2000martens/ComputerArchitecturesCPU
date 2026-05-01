//Module: hazard_detection_unit
//Function: Detects load-use data hazards. Signals when the pipeline
//          must stall for one cycle to wait for load data.
//
// Stall condition (load-use):
//   - Instruction in ID/EX is a load (mem_read_ID_EX = 1)
//   - AND its rd matches rs1 or rs2 of the instruction in IF/ID
//
// When stall is asserted:
//   - PC is not updated (same instruction keeps being fetched)
//   - IF/ID is not updated (same instruction stays in ID)
//   - Control signals into ID/EX are zeroed (NOP bubble injected)

module hazard_detection_unit(
   input  wire [4:0] rs1_IF_ID,
   input  wire [4:0] rs2_IF_ID,
   input  wire [4:0] rd_ID_EX,
   input  wire       mem_read_ID_EX,

   output wire       stall
);

   assign stall = mem_read_ID_EX
                  && (rd_ID_EX != 5'd0)
                  && ((rd_ID_EX == rs1_IF_ID) || (rd_ID_EX == rs2_IF_ID));

endmodule
