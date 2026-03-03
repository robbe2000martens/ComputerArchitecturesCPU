module mux_2 
  #(
   parameter integer DATA_W = 16
   )(
      input  wire [DATA_W-1:0] input_a,
      input  wire [DATA_W-1:0] input_b,
      input  wire              select_a,
      output reg  [DATA_W-1:0] mux_out
   );

   always@(*)begin
      if(select_a == 1'b1)begin
         mux_out = input_a;
      end else begin
         mux_out = input_b;
      end
   end
endmodule

module mux_3 
  #(
   parameter integer DATA_W = 16
   )(
      input  wire [DATA_W-1:0] input_a,
      input  wire [DATA_W-1:0] input_b,
      input  wire [DATA_W-1:0] input_c,
      input  wire [1:0]        select_a,
      output reg  [DATA_W-1:0] mux_out
   );

   always@(*)begin
       case(select_a)
        2'b00: mux_out = input_a;
        2'b10: mux_out = input_b;
        2'b01: mux_out = input_c;
        default: mux_out = input_a;
       endcase
   end
endmodule