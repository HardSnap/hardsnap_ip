
`timescale 1 ns / 1 ps

module memap_v1_0_M00_AXI #
(
	// Users to add parameters here

	// User parameters ends
	// Do not modify the parameters beyond this line

	// Width of M_AXI address bus.
  // The master generates the read and write addresses of width specified as C_M_AXI_ADDR_WIDTH.
	parameter integer C_M_AXI_ADDR_WIDTH	= 32,
	// Width of M_AXI data bus.
  // The master issues write data and accept read data where the width of the data bus is C_M_AXI_DATA_WIDTH
	parameter integer C_M_AXI_DATA_WIDTH	= 32
)
(
	// Users to add ports here
  input wire cs_ready,
  input wire [31:0] cs_address,
  input wire [31:0] cs_data_i,
  input wire cs_is_read,
  output wire cs_busy,
  output wire cs_done,
  output wire [31:0] cs_data_o,

	// User ports ends
	// Do not modify the ports beyond this line

	// Initiate AXI transactions
	//input wire  INIT_AXI_TXN,
	// Asserts when ERROR is detected
	output reg  ERROR,
	// Asserts when AXI transactions is complete
	//output wire  TXN_DONE,
	// AXI clock signal
	input wire  M_AXI_ACLK,
	// AXI active low reset signal
	input wire  M_AXI_ARESETN,
	// Master Interface Write Address Channel ports. Write address (issued by master)
	output wire [C_M_AXI_ADDR_WIDTH-1 : 0] M_AXI_AWADDR,
	// Write channel Protection type.
  // This signal indicates the privilege and security level of the transaction,
  // and whether the transaction is a data access or an instruction access.
	output wire [2 : 0] M_AXI_AWPROT,
	// Write address valid.
  // This signal indicates that the master signaling valid write address and control information.
	output wire  M_AXI_AWVALID,
	// Write address ready.
  // This signal indicates that the slave is ready to accept an address and associated control signals.
	input wire  M_AXI_AWREADY,
	// Master Interface Write Data Channel ports. Write data (issued by master)
	output wire [C_M_AXI_DATA_WIDTH-1 : 0] M_AXI_WDATA,
	// Write strobes.
  // This signal indicates which byte lanes hold valid data.
  // There is one write strobe bit for each eight bits of the write data bus.
	output wire [C_M_AXI_DATA_WIDTH/8-1 : 0] M_AXI_WSTRB,
	// Write valid. This signal indicates that valid write data and strobes are available.
	output wire  M_AXI_WVALID,
	// Write ready. This signal indicates that the slave can accept the write data.
	input wire  M_AXI_WREADY,
	// Master Interface Write Response Channel ports.
  // This signal indicates the status of the write transaction.
	input wire [1 : 0] M_AXI_BRESP,
	// Write response valid.
  // This signal indicates that the channel is signaling a valid write response
	input wire  M_AXI_BVALID,
	// Response ready. This signal indicates that the master can accept a write response.
	output wire  M_AXI_BREADY,
	// Master Interface Read Address Channel ports. Read address (issued by master)
	output wire [C_M_AXI_ADDR_WIDTH-1 : 0] M_AXI_ARADDR,
	// Protection type.
  // This signal indicates the privilege and security level of the transaction,
  // and whether the transaction is a data access or an instruction access.
	output wire [2 : 0] M_AXI_ARPROT,
	// Read address valid.
  // This signal indicates that the channel is signaling valid read address and control information.
	output wire  M_AXI_ARVALID,
	// Read address ready.
  // This signal indicates that the slave is ready to accept an address and associated control signals.
	input wire  M_AXI_ARREADY,
	// Master Interface Read Data Channel ports. Read data (issued by slave)
	input wire [C_M_AXI_DATA_WIDTH-1 : 0] M_AXI_RDATA,
	// Read response. This signal indicates the status of the read transfer.
	input wire [1 : 0] M_AXI_RRESP,
	// Read valid. This signal indicates that the channel is signaling the required read data.
	input wire  M_AXI_RVALID,
	// Read ready. This signal indicates that the master can accept the read data and response information.
	output wire  M_AXI_RREADY
);

// function called clogb2 that returns an integer which has the
// value of the ceiling of the log base 2

 function integer clogb2 (input integer bit_depth);
	 begin
	 for(clogb2=0; bit_depth>0; clogb2=clogb2+1)
		 bit_depth = bit_depth >> 1;
	 end
 endfunction

// Example State machine to initialize counter, initialize write transactions,
// initialize read transactions and comparison of read data with the
// written data words.
parameter [1:0] IDLE = 2'b00, // This state initiates AXI4Lite transaction
		// after the state machine changes state to INIT_WRITE
		// when there is 0 to 1 transition on INIT_AXI_TXN
	INIT_WRITE   = 2'b01, // This state initializes write transaction,
		// once writes are done, the state machine
		// changes state to INIT_READ
	INIT_READ = 2'b10; // This state initializes read transaction
		// once reads are done, the state machine
		// changes state to INIT_COMPARE

 reg [1:0] mst_exec_state;

  // CS Reg
  //reg done;
// AXI4LITE signals
//write address valid
reg  	axi_awvalid;
//write data valid
reg  	axi_wvalid;
//read address valid
reg  	axi_arvalid;
//read data acceptance
reg  	axi_rready;
//write response acceptance
reg  	axi_bready;

//Asserts when a single beat read transaction is issued and remains asserted till the completion of read trasaction.
reg  	read_issued;
//Asserts when there is a write response error
wire  	write_resp_error;
//Asserts when there is a read response error
wire  	read_resp_error;
//A pulse to initiate a write transaction
reg  	start_single_write;
//A pulse to initiate a read transaction
reg  	start_single_read;
//flag that marks the completion of write trasactions. The number of write transaction is user selected by the parameter C_M_TRANSACTIONS_NUM.
//The error register is asserted when any of the write response error, read response error or the data mismatch flags are asserted.
reg  	error_reg;
//Flag is asserted when the read index reaches the last read transction number
reg  	init_txn_ff;
reg  	init_txn_ff2;
reg  	init_txn_edge;
wire  	init_txn_pulse;


reg [31:0] read_data;
reg _cs_done;
reg _cs_busy;

// I/O Connections assignments

//Set address from input
assign M_AXI_AWADDR	= cs_address;
//AXI 4 write data
assign M_AXI_WDATA	= cs_data_i;
assign M_AXI_AWPROT	= 3'b000;
assign M_AXI_AWVALID	= axi_awvalid;
//Write Data(W)
assign M_AXI_WVALID	= axi_wvalid;
//Set all byte strobes in this example
assign M_AXI_WSTRB	= 4'b1111;
//Write Response (B)
assign M_AXI_BREADY	= axi_bready;
//Read Address (AR)
assign M_AXI_ARADDR	= cs_address;
assign M_AXI_ARVALID	= axi_arvalid;
assign M_AXI_ARPROT	= 3'b001;
//Read and Read Response (R)
assign M_AXI_RREADY	= axi_rready;
//Example design I/O
//assign TXN_DONE	= done;
assign init_txn_pulse	= (!init_txn_ff2) && init_txn_ff;

  assign cs_done = _cs_done;
  assign cs_data_o = read_data; // M_AXI_RDATA
  assign cs_busy = _cs_busy;

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
        init_txn_ff <= cs_ready;
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


//--------------------------------
//User Logic
//--------------------------------

//Address/Data Stimulus

//Address/data pairs for this example. The read and write values should
//match.
//Modify these as desired for different address patterns.

  //implement master command interface state machine
  always @ ( posedge M_AXI_ACLK)
  begin
    if (M_AXI_ARESETN == 1'b0)
      begin
      // reset condition
      // All the signals are assigned default values under reset condition
        mst_exec_state     <= IDLE;
        start_single_write <= 1'b0;
        start_single_read  <= 1'b0;
        read_issued   <= 1'b0;                                                      
        ERROR <= 1'b0;
        _cs_done <= 1'b0;
        read_data <= 32'b0;
        _cs_busy <= 1'b0;
      end
    else
      begin
       // state transition
        case (mst_exec_state)

          IDLE:
          // This state is responsible to initiate
          // AXI transaction when init_txn_pulse is asserted
            if ( init_txn_pulse == 1'b1 )
              begin
                if ( cs_is_read == 1'b1 ) begin
                    _cs_done           <= 1'b0;
  	                mst_exec_state  <= INIT_READ;
                    ERROR <= 1'b0;
                    _cs_busy        <= 1'b1;
                end else begin
                    _cs_done           <= 1'b0;
  	                mst_exec_state  <= INIT_WRITE;
                    ERROR <= 1'b0;
                    _cs_busy        <= 1'b1;
                end
              end
            else
              begin
                mst_exec_state  <= IDLE;
                ERROR           <= 1'b0;
                _cs_busy        <= 1'b0;
              end

          INIT_WRITE:
            // This state is responsible to issue start_single_write pulse to
            // initiate a write transaction. Write transactions will be
            // issued until last_write signal is asserted.
            // write controller
              begin
                  if (~axi_awvalid && ~axi_wvalid && ~M_AXI_BVALID && ~start_single_write)
                    begin
                      start_single_write <= 1'b1;
                      mst_exec_state     <= INIT_WRITE;
                      _cs_done           <= 1'b0;
                    end
                  else if (axi_bready)
                    begin
                      mst_exec_state  <= IDLE;
                      _cs_done        <= 1'b1;
                    end
                  else
                    begin
                      start_single_write <= 1'b0; //Negate to generate a pulse
                      _cs_done           <= 1'b0;
                    end
              end

          INIT_READ:
            // This state is responsible to issue start_single_read pulse to
            // initiate a read transaction. Read transactions will be
            // issued until last_read signal is asserted.
             // read controller
               begin
                 mst_exec_state  <= INIT_READ;

                 if (~axi_arvalid && ~M_AXI_RVALID && ~start_single_read && ~read_issued)
                   begin
                     start_single_read <= 1'b1;
                      _cs_done         <= 1'b0;
                     read_issued  <= 1'b1;                                          
                   end
                 else if (axi_rready)
                   begin
                     mst_exec_state  <= IDLE;
                     read_data       <= M_AXI_RDATA;
                      _cs_done       <= 1'b1;
                     read_issued     <= 1'b0;
                   end
                 else
                   begin
                     start_single_read <= 1'b0; //Negate to generate a pulse
                     _cs_done          <= 1'b0;
                   end
               end
           default :
             begin
               mst_exec_state  <= IDLE;
             end
        endcase
    end
  end //MASTER_EXECUTION_PROC

  //assign LEDs[1:0] = mst_exec_state;
  //assign LEDs[2]   = ERROR;
  //assign LEDs[3]   = _cs_done;
  //assign LEDs[4]   = start_single_write;
  //assign LEDs[5]   = start_single_read;

// User logic ends
endmodule

