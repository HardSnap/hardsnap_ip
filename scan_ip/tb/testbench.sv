`timescale 1ns / 1ps

import top_axi_vip_0_0_pkg::*;
import axi_vip_pkg::*;

module testbench();

localparam SCANIP_START = 32'H44A0_0000;

reg aclk;
reg aresetn;

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

//top_axi_vip_0_0_mst_t master_agent_sha256;
top_axi_vip_0_0_passthrough_t  mst_agent;

xil_axi_uint          mst_agent_verbosity = XIL_AXI_VERBOSITY_NONE;

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

assign scan_output = big_reg[127];

bit [top_axi_vip_0_0_VIP_DATA_WIDTH - 1:0] reg_rd_data;

initial begin
    // new the agents
    mst_agent = new("top_axi_vip_0_0_passthrough", DUT.top_i.axi_vip_0.inst.IF);
    //mst_agent.start_master();
    //mst_agent.start_slave();

    mst_agent.set_agent_tag("Master VIP");
    mst_agent.set_verbosity(400);
    mst_agent.start_master();

    $timeformat (-12, 1, "ps", 1);
    
    // Set verbosity
    mst_agent.set_verbosity(mst_agent_verbosity);
    
    // Set agent modes
    DUT.top_i.axi_vip_0.inst.set_master_mode();
    
    // start the agents
    mst_agent.start_master();
    
    // initialize first 4kB of slave VIP memory with random data
    backdoor_mem_write(32'h00000000,32'h00001000);
    
    // Set up CDMA to perform transfer
    // Refer to PG034 for CDMA register details.    
    master_reg_write(SCANIP_START+32'D0, 32'H00000000); // Source address
    master_reg_write(SCANIP_START+32'D4, 32'H00001000); // Destination address
    master_reg_write(SCANIP_START+32'D8, 32'H00000128); // Number of bytes to transfer
    master_reg_write(SCANIP_START+32'D12,32'H00000001); // Start
    master_reg_write(SCANIP_START+32'D12,32'H00000000); // Start Pulse
    
    // poll IDLE bit in status register to see if transaction finishes
    do
      begin
        master_reg_read(SCANIP_START+32'D16, reg_rd_data);
      end
     while((reg_rd_data & 32'h00000002) == 32'h00000000);


    aresetn = 0;
    #175ns
    aresetn = 1;

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


  // Task to generate single beat, 32-bit register write transactions
  task master_reg_write;
    input   [top_axi_vip_0_0_VIP_ADDR_WIDTH - 1:0]  address;
    input   [top_axi_vip_0_0_VIP_ADDR_WIDTH - 1:0]  data;
    axi_transaction              wr_transaction;     //Declare an object handle of write transaction
    xil_axi_uint                 mtestID;            // Declare ID  
    xil_axi_ulong                mtestADDR;          // Declare ADDR  
    xil_axi_len_t                mtestBurstLength;   // Declare Burst Length   
    xil_axi_size_t               mtestDataSize;      // Declare SIZE  
    xil_axi_burst_t              mtestBurstType;     // Declare Burst Type  
    xil_axi_data_beat [255:0]    mtestWUSER;         // Declare Wuser  
    xil_axi_data_beat            mtestAWUSER;        // Declare Awuser  
    xil_axi_resp_t               mtestBresp;
    /***********************************************************************************************
    * A burst can not cross 4KB address boundry for AXI4
    * Maximum data bits = 4*1024*8 =32768
    * Write Data Value for WRITE_BURST transaction
    * Read Data Value for READ_BURST transaction
    ***********************************************************************************************/
    bit [32767:0]                 mtestWData;         // Declare Write Data 

    mtestID = 0;
    mtestADDR = address;
    mtestBurstLength = 'h0;
    mtestDataSize = XIL_AXI_SIZE_4BYTE;
    mtestBurstType = XIL_AXI_BURST_TYPE_INCR; 
    mtestAWUSER =0;
    mtestWData[top_axi_vip_0_0_VIP_ADDR_WIDTH - 1:0] = data;
    
    
    wr_transaction = mst_agent.mst_wr_driver.create_transaction("write transaction in API");
    wr_transaction.set_write_cmd(mtestADDR,mtestBurstType,mtestID,mtestBurstLength,mtestDataSize);
    wr_transaction.set_data_block(mtestWData);
    wr_transaction.set_awuser(mtestAWUSER);
    for (xil_axi_uint beat = 0; beat < wr_transaction.get_len()+1;beat++) begin
      wr_transaction.set_wuser(beat, mtestWUSER[beat]);
    end  
    wr_transaction.set_driver_return_item_policy(XIL_AXI_PAYLOAD_RETURN);
    mst_agent.mst_wr_driver.send(wr_transaction);
    mst_agent.mst_wr_driver.wait_rsp(wr_transaction);
    mtestBresp = wr_transaction.get_bresp();
    
    $display("Write response: 0x%H",mtestBresp); 
  endtask :master_reg_write

  // Task to generate single beat, 32-bit register read transactions
  task master_reg_read;
    input   [top_axi_vip_0_0_VIP_ADDR_WIDTH - 1:0]  address;
    output  [top_axi_vip_0_0_VIP_ADDR_WIDTH - 1:0]  data;
    
    axi_transaction              rd_transaction;     //Declare an object handle of read transaction
    xil_axi_uint                 mtestID;            // Declare ID  
    xil_axi_ulong                mtestADDR;          // Declare ADDR  
    xil_axi_len_t                mtestBurstLength;   // Declare Burst Length   
    xil_axi_size_t               mtestDataSize;      // Declare SIZE  
    xil_axi_burst_t              mtestBurstType;     // Declare Burst Type    
    
    mtestID = 0;
    mtestADDR = address;
    mtestBurstLength = 'h0;
    mtestDataSize = XIL_AXI_SIZE_4BYTE;
    mtestBurstType = XIL_AXI_BURST_TYPE_INCR; 

    rd_transaction = mst_agent.mst_rd_driver.create_transaction("read transaction");
    rd_transaction.set_read_cmd(mtestADDR,mtestBurstType,mtestID,mtestBurstLength,mtestDataSize);
    rd_transaction.set_driver_return_item_policy(XIL_AXI_PAYLOAD_RETURN);
    mst_agent.mst_rd_driver.send(rd_transaction);
    mst_agent.mst_rd_driver.wait_rsp(rd_transaction);
    data = rd_transaction.get_data_beat(0);

  endtask  :master_reg_read
  
  
/*************************************************************************************************  
    * Task backdoor_mem_write shows how user can do backdoor write to memory model
    * Fills range beginning at start_addr and ending at stop_addr with random data. 
    * Declare default fill in value  mem_fill_payload according to DATA WIDTH
    * Declare backdoor memory write payload according to DATA WIDTH
    * Declare backdoo memory write strobe
    * Set default memory fill policy to random
    * Fill data payload with random data
    * 
    * Task assumes the start/stop address are aligned to data width.
    * Write data to memory model  
    *************************************************************************************************/
  task backdoor_mem_write(
    input xil_axi_ulong     start_addr,
    input xil_axi_ulong     stop_addr
  );
    bit[top_axi_vip_0_0_VIP_ADDR_WIDTH-1:0]              mem_wr_addr;
    bit[top_axi_vip_0_0_VIP_DATA_WIDTH-1:0]              write_data;
    bit[(top_axi_vip_0_0_VIP_DATA_WIDTH/8)-1:0]          write_strb;
    xil_axi_ulong             addr_offset;

    slv_agent.mem_model.set_memory_fill_policy(XIL_AXI_MEMORY_FILL_RANDOM);        // Determines what policy to use when memory model encounters an empty entry
    write_strb = ($pow(2,(top_axi_vip_0_0_VIP_DATA_WIDTH/8)) - 1);            // All strobe bits asserted
    for(mem_wr_addr = start_addr; mem_wr_addr < stop_addr; mem_wr_addr += 16) begin
        WRITE_DATA_FAIL: assert(std::randomize(write_data)); 
        slv_agent.mem_model.backdoor_memory_write(mem_wr_addr, write_data, write_strb);
     end
  endtask :backdoor_mem_write

endmodule
