`timescale 1ns / 1ps

import top_axi_vip_0_0_pkg::*;
import axi_vip_pkg::*;

module testbench();

reg aclk;
reg resetn;

wire scan_ck_enable;
wire scan_enable;
wire scan_input;
wire scan_output;

top_wrapper DUT
  (.aclk(aclk),
  .aresetn(aresetn),
  .scan_ck_enable(scan_ck_enable),
  .scan_enable(scan_enable),
  .scan_input(scan_input),
  .scan_output(scan_output));

always #1ns aclk = ~aclk;

top_axi_vip_0_0_mst_t master_agent_sha256;

xil_axi_prot_t  prot = 0;
xil_axi_resp_t  resp;

reg [128:0] big_reg;

always @(posedge aclk, posedge aresetn)
begin
  if(aresetn == 1'b0)
    big_reg = 32'b0;
  else begin
    if(scan_enable == 1'b1) begin
      if(scan_ck_enable == 1'b1)
        big_reg <= {big_reg[127:1], scan_input};
    end else begin 
      big_reg <= big_reg;
    end 
  end
end

assign scan_output <= big_reg[127];

initial begin
    master_agent_sha256 = new("slave vip agent",DUT.top_i.axi_vip_0.inst.IF);
    master_agent_sha256.set_agent_tag("Master VIP");
    master_agent_sha256.set_verbosity(400);
    master_agent_sha256.start_master();

    aresetn = 0;
    #175ns
    aresetn = 1;
end

endmodule
