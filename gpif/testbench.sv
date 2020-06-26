`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/01/2020 11:51:04 PM
// Design Name: 
// Module Name: testbench
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

import top_axi_vip_0_0_pkg::*;
import axi_vip_pkg::*;

module testbench();

reg aclk = 0;
reg aresetn = 0;

reg [31:0] dout;
reg [31:0] din = 0;

reg rd_en = 0;
reg wr_en = 0;

wire full;
wire empty;

always @ (posedge aclk or negedge aresetn) begin
    if (!aresetn)
        rd_en <= 1'b0;
    else
        if (!empty && !rd_en)
            rd_en <= 1'b1;
        else
            rd_en <= 1'b0;
end

top_wrapper DUT(
    .aclk_0(aclk),
    .aresetn_0(aresetn),
    .din_0(din),
    .dout_0(dout),
    .empty_0(empty),
    .full_0(full),
    .rd_en_0(rd_en),
    .wr_en_0(wr_en));

always #5ns aclk = ~aclk;

top_axi_vip_0_0_slv_mem_t slv_mem_agent;

xil_axi_prot_t  prot = 0;
xil_axi_resp_t  resp;

initial begin

    slv_mem_agent = new("slave vip agent",DUT.top_i.axi_vip_0.inst.IF);

    //slv_mem_agent.mem_model.set_memory_fill_policy(XIL_AXI_MEMORY_FILL_FIXED);
    slv_mem_agent.mem_model.set_default_memory_value(32'HFFFFFFFF);
    slv_mem_agent.set_agent_tag("Slave VIP");
    slv_mem_agent.set_verbosity(400);

    //Start the agent
    slv_mem_agent.start_slave();

    aresetn = 0;
    #175ns
    aresetn = 1;

    din = 32'hABABABAB;
    wr_en = 1'b1;
    #10ns
    wr_en = 1'b0;
    din = 32'h10000000;
    #10ns
    wr_en = 1'b1;
    #10ns
    wr_en = 1'b0;
    #10ns

    din = 32'hABABABAB;
    wr_en = 1'b1;
    #10ns
    wr_en = 1'b0;
    din = 32'h10000001;
    #10ns
    wr_en = 1'b1;
    #10ns
    wr_en = 1'b0;
    #10ns

    aresetn = 1;
end


endmodule
