//Register File with internal forwarding (WB -> ID)
//Function: Same as before, but if a write is happening to the same register
//          we are reading from in the same cycle, the wdata is forwarded
//          directly to the read output. This avoids a stale-read hazard
//          when an instruction in WB is writing the register that the
//          instruction in ID is reading.

module register_file#(
   parameter integer DATA_W     = 16
)(
      input  wire              clk,
      input  wire              arst_n,
      input  wire              reg_write,
      input  wire [       4:0] raddr_1,
      input  wire [       4:0] raddr_2,
      input  wire [       4:0] waddr,
      input  wire [DATA_W-1:0] wdata,
      output reg  [DATA_W-1:0] rdata_1,
      output reg  [DATA_W-1:0] rdata_2
   );

   parameter integer N_REG      = 32;

   reg [DATA_W-1:0] reg_array     [0:N_REG-1];
   reg [DATA_W-1:0] reg_array_nxt [0:N_REG-1];

   integer idx;

   // Read with WB->ID forwarding: if the register being written this cycle
   // matches the register being read, return wdata directly.
   always@(*) begin
      if (reg_write && (waddr != 5'd0) && (waddr == raddr_1))
         rdata_1 = wdata;
      else
         rdata_1 = reg_array[raddr_1];

      if (reg_write && (waddr != 5'd0) && (waddr == raddr_2))
         rdata_2 = wdata;
      else
         rdata_2 = reg_array[raddr_2];
   end

   //Register file write process
   always@(*) begin
      for(idx=0; idx<N_REG; idx =idx+1)begin
         if((reg_write == 1'b1) && (waddr == idx)) begin
            reg_array_nxt[idx] = wdata;
         end else begin
            reg_array_nxt[idx] = reg_array[idx];
         end
      end
   end

   always@(posedge clk, negedge arst_n) begin
      if(arst_n == 1'b0)begin
         for(idx=0; idx<N_REG; idx =idx+1)begin
            reg_array[idx] <= 'b0;
         end
      end else begin
         for(idx=1; idx<N_REG; idx =idx+1)begin
            reg_array[idx] <= reg_array_nxt[idx];
         end
      end
   end

endmodule
