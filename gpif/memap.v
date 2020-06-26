module MemAP #
(
	parameter integer C_M_AXI_ADDR_WIDTH	= 32,
	parameter integer C_M_AXI_DATA_WIDTH	= 32
)
(
  input wire [31:0] addr,
  input wire [31:0] data,
  
  input wire start_single_read,
  input wire start_single_write,
  
  output wire busy,
  output wire [31:0] res,

  input wire  m00_axi_aclk, // AXI clock signal
  input wire  m00_axi_aresetn, // AXI active low reset signal 

  input wire  m00_axi_awready, // Write address ready.
  input wire  m00_axi_wready, // Write ready. This signal indicates that the slave can accept the write data.
  input wire [1 : 0] m00_axi_bresp, // Master Interface Write Response Channel ports.
  input wire  m00_axi_bvalid, // Write response valid.
  input wire  m00_axi_arready, // Read address ready.
  input wire [C_M_AXI_DATA_WIDTH-1 : 0] m00_axi_rdata, // Master Interface Read Data Channel ports. Read data (issued by slave)
  input wire [1 : 0] m00_axi_rresp, // Read response. This signal indicates the status of the read transfer.
  input wire  m00_axi_rvalid, // Read valid. This signal indicates that the channel is signaling the required read data.

  output wire [C_M_AXI_ADDR_WIDTH-1 : 0] m00_axi_awaddr, // Master Interface Write Address Channel ports. Write address (issued by master)
  output wire [2 : 0] m00_axi_awprot, // Write channel Protection type.
  output wire  m00_axi_awvalid, // Write address valid.
  output wire [C_M_AXI_DATA_WIDTH-1 : 0] m00_axi_wdata, // Master Interface Write Data Channel ports. Write data (issued by master)
  output wire [C_M_AXI_DATA_WIDTH/8-1 : 0] m00_axi_wstrb, // Write strobes.
  output wire  m00_axi_wvalid, // Write valid. This signal indicates that valid write data and strobes are available.
  output wire  m00_axi_bready, // Response ready. This signal indicates that the master can accept a write response.
  output wire [C_M_AXI_ADDR_WIDTH-1 : 0] m00_axi_araddr, // Master Interface Read Address Channel ports. Read address (issued by master)
  output wire [2 : 0] m00_axi_arprot, // Protection type.
  output wire  m00_axi_arvalid, // Read address valid.
  output wire  m00_axi_rready // Read ready. This signal indicates that the master can accept the read data and response information.
);

  // function called clogb2 that returns an integer which has the
  // value of the ceiling of the log base 2
  function integer clogb2 (input integer bit_depth);
  begin
    for(clogb2=0; bit_depth>0; clogb2=clogb2+1)
      bit_depth = bit_depth >> 1;
  end
  endfunction
  
  parameter [1:0] IDLE = 2'b00, // This state initiates AXI4Lite transaction
                  WAIT_COMPLETION   = 2'b01; // This state initializes write transaction,

  reg [1:0] state;

  reg  	axi_awvalid; //write address valid
  reg  	axi_wvalid; //write data valid
  reg  	axi_arvalid; //read address valid
  reg  	axi_rready; //read data acceptance
  reg  	axi_bready; //write response acceptance
  reg  	read_issued; //Asserts when a single beat read transaction is issued and remains asserted till the completion of read trasaction.
  //reg  	start_single_write; //A pulse to initiate a write transaction
  //reg  	start_single_read; //A pulse to initiate a read transaction
  reg  	error_reg; //The error register is asserted when any of the write response error, read response error or the data mismatch flags are asserted.

  wire write_resp_error; //Asserts when there is a write response error
  wire read_resp_error; //Asserts when there is a read response error
  
  // I/O Connections assignments

  //Set address from input
  assign m00_axi_awaddr	= addr;
  //AXI 4 write data
  assign m00_axi_wdata	= data;
  assign m00_axi_awprot	= 3'b000;
  assign m00_axi_awvalid	= axi_awvalid;
  //Write Data(W)
  assign m00_axi_wvalid	= axi_wvalid;
  //Set all byte strobes in this example
  assign m00_axi_wstrb	= 4'b1111;
  //Write Response (B)
  assign m00_axi_bready	= axi_bready;
  //Read Address (AR)
  assign m00_axi_araddr	= addr;
  assign m00_axi_arvalid	= axi_arvalid;
  assign m00_axi_arprot	= 3'b001;
  //Read and Read Response (R)
  assign m00_axi_rready	= axi_rready;

  assign res = m00_axi_rdata; // M_AXI_RDATA

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
  always @(posedge m00_axi_aclk)
  begin
    //Only VALID signals must be deasserted during reset per AXI spec
    //Consider inverting then registering active-low reset for higher fmax
    if (m00_axi_aresetn == 0)
      begin
        axi_awvalid <= 1'b0;
      end
      else
      begin
        if (start_single_write)
          begin
            axi_awvalid <= 1'b1;
          end
        else if (m00_axi_awready && axi_awvalid)
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
  always @(posedge m00_axi_aclk)
  begin
    if (m00_axi_aresetn == 0)
      begin
        axi_wvalid <= 1'b0;
      end
      //Signal a new address/data command is available by user logic
      else if (start_single_write)
      begin
        axi_wvalid <= 1'b1;
      end
      //Data accepted by interconnect/slave (issue of m00_axi_wready by slave)
      else if (m00_axi_wready && axi_wvalid)
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
  always @(posedge m00_axi_aclk)
  begin
    if (m00_axi_aresetn == 0 )
      begin
        axi_bready <= 1'b0;
      end
    // accept/acknowledge bresp with axi_bready by the master
    // when m00_axi_bvalid is asserted by slave
    else if (m00_axi_bvalid && ~axi_bready)
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
  assign write_resp_error = (axi_bready & m00_axi_bvalid & m00_axi_bresp[1]);


  //----------------------------
  //Read Address Channel
  //----------------------------
  
  // A new axi_arvalid is asserted when there is a valid read address
  // available by the master. start_single_read triggers a new read
  // transaction
  always @(posedge m00_axi_aclk)
  begin
    if (m00_axi_aresetn == 0 )
      begin
        axi_arvalid <= 1'b0;
      end
    //Signal a new read address command is available by user logic
    else if (start_single_read)
      begin
        axi_arvalid <= 1'b1;
      end
    //RAddress accepted by interconnect/slave (issue of m00_axi_arready by slave)
    else if (m00_axi_arready && axi_arvalid)
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
  always @(posedge m00_axi_aclk)
  begin
    if (m00_axi_aresetn == 0 )
      begin
        axi_rready <= 1'b0;
      end
    // accept/acknowledge rdata/rresp with axi_rready by the master
    // when m00_axi_rvalid is asserted by slave
    else if (m00_axi_rvalid && ~axi_rready)
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
assign read_resp_error = (axi_rready & m00_axi_rvalid & m00_axi_rresp[1]);


//--------------------------------
//User Logic
//--------------------------------

  //implement master command interface state machine
  always @ ( posedge m00_axi_aclk)
  begin
    if (m00_axi_aresetn == 1'b0)
      begin
        state     <= IDLE;
      end
    else
      begin
        case (state)
          IDLE:
            if ( start_single_read == 1'b1 || start_single_write == 1'b1)
            begin
              state  <= WAIT_COMPLETION;
            end
          WAIT_COMPLETION:
            begin
              if (axi_bready || axi_rready)
              begin
                state  <= IDLE;
              end
            end
           default :
             begin
               state  <= IDLE;
             end
        endcase
    end
  end //MASTER_EXECUTION_PROC

  assign busy = (start_single_read || start_single_write || state == WAIT_COMPLETION)? 1'b1 : 1'b0;

endmodule
