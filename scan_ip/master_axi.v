`timescale 1 ns / 1 ps

module master_axi #
(
	parameter integer C_M_AXI_ADDR_WIDTH	= 32,
	parameter integer C_M_AXI_DATA_WIDTH	= 32
)
(
  input wire start,

  input wire [31:0] data,
  input wire [31:0] address_dst,
  input wire [31:0] address_src,
  input wire [31:0] length, 

  output wire rd_en,
  input wire [31:0] data_in,
  input wire almost_full,

  output wire wr_en,
  output wire [31:0] data_out,
  input wire empty,

	input wire  M_AXI_ACLK,
	input wire  M_AXI_ARESETN,
	output wire [C_M_AXI_ADDR_WIDTH-1 : 0] M_AXI_AWADDR,
	output wire [2 : 0] M_AXI_AWPROT,
	output wire  M_AXI_AWVALID,
	input wire  M_AXI_AWREADY,
	output wire [C_M_AXI_DATA_WIDTH-1 : 0] M_AXI_WDATA,
	output wire [C_M_AXI_DATA_WIDTH/8-1 : 0] M_AXI_WSTRB,
	output wire  M_AXI_WVALID,
	input wire  M_AXI_WREADY,
	input wire [1 : 0] M_AXI_BRESP,
	input wire  M_AXI_BVALID,
	output wire  M_AXI_BREADY,
	output wire [C_M_AXI_ADDR_WIDTH-1 : 0] M_AXI_ARADDR,
	output wire [2 : 0] M_AXI_ARPROT,
	output wire  M_AXI_ARVALID,
	input wire  M_AXI_ARREADY,
	input wire [C_M_AXI_DATA_WIDTH-1 : 0] M_AXI_RDATA,
	input wire [1 : 0] M_AXI_RRESP,
	input wire  M_AXI_RVALID,
	output wire  M_AXI_RREADY
);

 function integer clogb2 (input integer bit_depth);
	 begin
	 for(clogb2=0; bit_depth>0; clogb2=clogb2+1)
		 bit_depth = bit_depth >> 1;
	 end
 endfunction

parameter [1:0] IDLE = 2'b00,
	INIT_WRITE         = 2'b01,
	INIT_READ          = 2'b10;

reg [1:0] state;

reg  	axi_awvalid;
reg  	axi_wvalid;
reg  	axi_arvalid;
reg  	axi_rready;
reg  	axi_bready;
reg  	read_issued;
reg  	start_single_write;
reg  	start_single_read;
reg  	error_reg;
reg  	init_txn_ff;
reg  	init_txn_ff2;
reg  	init_txn_edge;
reg [31:0] read_data;
reg [31:0] data;
reg [31:0] address;

wire  	init_txn_pulse;
wire  	write_resp_error;
wire  	read_resp_error;

// I/O Connections assignments

assign M_AXI_AWADDR	= address_dst + dst_index;
assign M_AXI_WDATA	= data_in;
assign M_AXI_AWPROT	= 3'b000;
assign M_AXI_AWVALID	= axi_awvalid;
assign M_AXI_WVALID	= axi_wvalid;
assign M_AXI_WSTRB	= 4'b1111;
assign M_AXI_BREADY	= axi_bready;
assign M_AXI_ARADDR	= address_src + src_index;
assign M_AXI_ARVALID	= axi_arvalid;
assign M_AXI_ARPROT	= 3'b001;
assign M_AXI_RREADY	= axi_rready;
assign init_txn_pulse	= (!init_txn_ff2) && init_txn_ff;

//Generate a pulse to initiate AXI transaction.
always @(posedge M_AXI_ACLK)
  begin
    // Initiates AXI transaction delay
    if ( M_AXI_ARESETN == 0 )
      begin
        init_txn_ff <= 1'b0;
        init_txn_ff2 <= 1'b0;
      end
    else
      begin
        init_txn_ff <= start;
        init_txn_ff2 <= init_txn_ff;
      end
  end


//--------------------
//Write Address Channel
//--------------------

// The purpose of the write address channel is to request the address and
// command information for the entire transaction.  It is a single beat
// of information.

// Note for this example the axi_awvalid/axi_wvalid are asserted at the same
// time, and then each is deasserted independent from each other.
// This is a lower-performance, but simplier control scheme.

// AXI VALID signals must be held active until accepted by the partner.

// A data transfer is accepted by the slave when a master has
// VALID data and the slave acknoledges it is also READY. While the master
// is allowed to generated multiple, back-to-back requests by not
// deasserting VALID, this design will add rest cycle for
// simplicity.

// Since only one outstanding transaction is issued by the user design,
// there will not be a collision between a new request and an accepted
// request on the same clock cycle.

  always @(posedge M_AXI_ACLK)
  begin
    //Only VALID signals must be deasserted during reset per AXI spec
    //Consider inverting then registering active-low reset for higher fmax
    if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)
      begin
        axi_awvalid <= 1'b0;
      end
      //Signal a new address/data command is available by user logic
    else
      begin
        if (start_single_write)
          begin
            axi_awvalid <= 1'b1;
          end
     //Address accepted by interconnect/slave (issue of M_AXI_AWREADY by slave)
        else if (M_AXI_AWREADY && axi_awvalid)
          begin
            axi_awvalid <= 1'b0;
          end
      end
  end




//--------------------
//Write Data Channel
//--------------------

//The write data channel is for transfering the actual data.
//The data generation is speific to the example design, and
//so only the WVALID/WREADY handshake is shown here

   always @(posedge M_AXI_ACLK)
   begin
     if (M_AXI_ARESETN == 0  || init_txn_pulse == 1'b1)
       begin
         axi_wvalid <= 1'b0;
       end
     //Signal a new address/data command is available by user logic
     else if (start_single_write)
       begin
         axi_wvalid <= 1'b1;
       end
     //Data accepted by interconnect/slave (issue of M_AXI_WREADY by slave)
     else if (M_AXI_WREADY && axi_wvalid)
       begin
        axi_wvalid <= 1'b0;
       end
   end


//----------------------------
//Write Response (B) Channel
//----------------------------

//The write response channel provides feedback that the write has committed
//to memory. BREADY will occur after both the data and the write address
//has arrived and been accepted by the slave, and can guarantee that no
//other accesses launched afterwards will be able to be reordered before it.

//The BRESP bit [1] is used indicate any errors from the interconnect or
//slave for the entire write burst. This example will capture the error.

//While not necessary per spec, it is advisable to reset READY signals in
//case of differing reset latencies between master/slave.

  always @(posedge M_AXI_ACLK)
  begin
    if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)
      begin
        axi_bready <= 1'b0;
      end
    // accept/acknowledge bresp with axi_bready by the master
    // when M_AXI_BVALID is asserted by slave
    else if (M_AXI_BVALID && ~axi_bready)
      begin
        axi_bready <= 1'b1;
      end
    // deassert after one clock cycle
    else if (axi_bready)
      begin
        axi_bready <= 1'b0;
      end
    // retain the previous value
    else
      axi_bready <= axi_bready;
  end

//Flag write errors
assign write_resp_error = (axi_bready & M_AXI_BVALID & M_AXI_BRESP[1]);


//----------------------------
//Read Address Channel
//----------------------------

  // A new axi_arvalid is asserted when there is a valid read address
  // available by the master. start_single_read triggers a new read
  // transaction
  always @(posedge M_AXI_ACLK)
  begin
    if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)
      begin
        axi_arvalid <= 1'b0;
      end
    //Signal a new read address command is available by user logic
    else if (start_single_read)
      begin
        axi_arvalid <= 1'b1;
      end
    //RAddress accepted by interconnect/slave (issue of M_AXI_ARREADY by slave)
    else if (M_AXI_ARREADY && axi_arvalid)
      begin
        axi_arvalid <= 1'b0;
      end
    // retain the previous value
  end


//--------------------------------
//Read Data (and Response) Channel
//--------------------------------

//The Read Data channel returns the results of the read request
//The master will accept the read data by asserting axi_rready
//when there is a valid read data available.
//While not necessary per spec, it is advisable to reset READY signals in
//case of differing reset latencies between master/slave.

  always @(posedge M_AXI_ACLK)
  begin
    if (M_AXI_ARESETN == 0 || init_txn_pulse == 1'b1)
      begin
        axi_rready <= 1'b0;
      end
    // accept/acknowledge rdata/rresp with axi_rready by the master
    // when M_AXI_RVALID is asserted by slave
    else if (M_AXI_RVALID && ~axi_rready)
      begin
        axi_rready <= 1'b1;
      end
    // deassert after one clock cycle
    else if (axi_rready)
      begin
        axi_rready <= 1'b0;
      end
    // retain the previous value
  end

//Flag write errors
assign read_resp_error = (axi_rready & M_AXI_RVALID & M_AXI_RRESP[1]);

assign data_out = M_AXI_RDATA;

//implement master command interface state machine
always @ ( posedge M_AXI_ACLK)
begin
  if (M_AXI_ARESETN == 1'b0)
    begin
      state              <= IDLE;
      start_single_write <= 1'b0;
      start_single_read  <= 1'b0;
      read_issued        <= 1'b0;                                                      
      read_data          <= 32'b0;
    end
  else
    begin
      case (state)
        IDLE:
          if start == 1'b1
            state  <= RUN;
        RUN:
          if almost_full == 1'b1
            state = INIT_WRITE;
          else if empty == 1'b0
	          state  <= INIT_READ;
        INIT_WRITE:
          begin
            if (~axi_awvalid && ~axi_wvalid && ~M_AXI_BVALID && ~start_single_write)
              start_single_write <= 1'b1;
            else if (axi_bready)
              state  <= DONE;
            else
              start_single_write <= 1'b0;
          end
        INIT_READ:
          if (~axi_arvalid && ~M_AXI_RVALID && ~start_single_read && ~read_issued)
          begin
            start_single_read <= 1'b1;
            read_issued  <= 1'b1;                                          
          end
          else if (axi_rready)
          begin
            state  <= DONE;
            read_issued     <= 1'b0;
            wr_en <= 1'b1;
          end
          else
            start_single_read <= 1'b0;
        DONE:
          if dst_index != (address_dst+length) && src_index != (address_src+length)
            state <= RUN 
          else
            state <= IDLE
        default :
            state  <= IDLE;
      endcase
  end

endmodule
