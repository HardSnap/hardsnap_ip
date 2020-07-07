`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/10/2019 03:18:41 PM
// Design Name: 
// Module Name: tb_overall_scan_system
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
import top_axi_vip_1_0_pkg::*;
import axi_vip_pkg::*;

module testbench();

localparam SCANIP_START = 32'H44A0_0000;

localparam REG_SNP1_ADDR  = 32'H44A0_0000;
localparam REG_SNP2_ADDR  = 32'H44A0_0004;
localparam REG_LENGTH     = 32'H44A0_0008;
localparam REG_START_ADDR = 32'H44A0_000C;
localparam REG_STATUS     = 32'H44A0_0010;


reg aclk = 0;
reg aresetn = 0;

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

// Declare agent
top_axi_vip_0_0_slv_mem_t slv_mem_agent;
top_axi_vip_1_0_mst_t master_agent;

xil_axi_prot_t  prot = 0;
xil_axi_resp_t  resp;

reg [127:0] big_reg;

always @(posedge aclk, posedge aresetn)
begin
  if(aresetn == 1'b0)
    big_reg = 128'HBBBBBBBF_BBBBBBBF_BBBBBBBF_BBBBBBBF;
  else begin
    if(scan_enable == 1'b1) begin
      if(scan_ck_enable == 1'b1)
        big_reg[127:0] <= {big_reg[126:0], scan_input};
    end else begin 
      big_reg <= big_reg;
    end 
  end
end

assign scan_output = big_reg[127];

bit [top_axi_vip_0_0_VIP_DATA_WIDTH - 1:0] reg_rd_data;

initial begin
    
    //Create an agent
    slv_mem_agent = new("slave vip agent",DUT.top_i.axi_vip_0.inst.IF);
    master_agent = new("master vip agent",DUT.top_i.axi_vip_1.inst.IF);

    slv_mem_agent.mem_model.set_memory_fill_policy(XIL_AXI_MEMORY_FILL_FIXED);

    // set tag for agents for easy debug
    slv_mem_agent.set_agent_tag("Slave VIP");
    master_agent.set_agent_tag("Master VIP");

    // set print out verbosity level.
    slv_mem_agent.set_verbosity(400);
    master_agent.set_verbosity(400);

    //Start the agent
    slv_mem_agent.start_slave();
    master_agent.start_master();

    aresetn = 0;
    #175ns
    aresetn = 1;

    slv_mem_agent.mem_model.set_default_memory_value(32'hAAAAAAAF);
    //backdoor_mem_write_from_file("/usr/bin/ls", 32'H0000_0000);

    // use the vip axi master to configure the scan ip
    #2ns
    master_agent.AXI4LITE_WRITE_BURST(REG_LENGTH, prot, 32'D128, resp);
    #2ns
    master_agent.AXI4LITE_WRITE_BURST(REG_SNP1_ADDR, prot, 32'H0000_0000,resp);
    #2ns
    master_agent.AXI4LITE_WRITE_BURST(REG_SNP2_ADDR, prot, 32'H0000_1000, resp);
    #2ns
    master_agent.AXI4LITE_WRITE_BURST(REG_START_ADDR, prot, 32'D1, resp);
    #2ns
    master_agent.AXI4LITE_WRITE_BURST(REG_START_ADDR, prot, 32'D0, resp);

    wait(DUT.top_i.t0.inst.done);

    #2ns
    master_agent.AXI4LITE_WRITE_BURST(REG_SNP1_ADDR, prot, 32'H0000_1000,resp);
    #2ns
    master_agent.AXI4LITE_WRITE_BURST(REG_SNP2_ADDR, prot, 32'H0000_0000, resp);
    #2ns
    master_agent.AXI4LITE_WRITE_BURST(REG_START_ADDR, prot, 32'D1, resp);
    #2ns
    master_agent.AXI4LITE_WRITE_BURST(REG_START_ADDR, prot, 32'D0, resp);

    wait(DUT.top_i.t0.inst.done);

    /*
    top_axi_vip_0_0_passthrough.AXI4LITE_WRITE_BURST(SCANIP_START+32'D0, prot, 32'H00000000, resp);
    #2ns
    top_axi_vip_0_0_passthrough.AXI4LITE_WRITE_BURST(SCANIP_START+32'D4, prot, 32'H00001000, resp);
    #2ns
    top_axi_vip_0_0_passthrough.AXI4LITE_WRITE_BURST(SCANIP_START+32'D8, prot, 32'D128, resp);
    #2ns
    top_axi_vip_0_0_passthrough.AXI4LITE_WRITE_BURST(SCANIP_START+32'D12, prot, 32'D1, resp);
    #2ns
    top_axi_vip_0_0_passthrough.AXI4LITE_WRITE_BURST(SCANIP_START+32'D12, prot, 32'D0, resp);
    */

end

task backdoor_mem_write_from_file(input string fname, input bit[31:0] adr);
    integer fd;

    bit [32-1:0] write_data;
    integer 	  offset;

    fd = $fopen(fname, "rb");
    if (fd == 0) begin
        $display("Error can't open %s", fname);
    end else begin
        $display("open %s", fname);
    end

    offset = 0;
    while (!$feof(fd)) begin
        $fread(write_data, fd, offset, 4);
        slv_mem_agent.mem_model.backdoor_memory_write(adr+offset, write_data, 4'b1111);
        offset += 4;	
    end

    $fclose(fd);
endtask

endmodule
