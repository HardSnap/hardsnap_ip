
`timescale 1 ns / 1 ps

	module scanner #
	(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line


		// Parameters of Axi Slave Bus Interface S00_AXI
		parameter integer C_S00_AXI_DATA_WIDTH	= 32,
		parameter integer C_S00_AXI_ADDR_WIDTH	= 5,

		// Parameters of Axi Master Bus Interface M00_AXI
		parameter integer C_M00_AXI_ADDR_WIDTH	= 32,
		parameter integer C_M00_AXI_DATA_WIDTH	= 32
	)
	(
		// Users to add ports here
        input wire scan_output,
        output wire scan_ck_en,
        output wire scan_input,
        output wire scan_enable,
        
        output wire interrupt,

		// User ports ends
		// Do not modify the ports beyond this line


		// Ports of Axi Slave Bus Interface S00_AXI
		input wire  s00_axi_aclk,
		input wire  s00_axi_aresetn,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
		input wire [2 : 0] s00_axi_awprot,
		input wire  s00_axi_awvalid,
		output wire  s00_axi_awready,
		input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
		input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
		input wire  s00_axi_wvalid,
		output wire  s00_axi_wready,
		output wire [1 : 0] s00_axi_bresp,
		output wire  s00_axi_bvalid,
		input wire  s00_axi_bready,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
		input wire [2 : 0] s00_axi_arprot,
		input wire  s00_axi_arvalid,
		output wire  s00_axi_arready,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
		output wire [1 : 0] s00_axi_rresp,
		output wire  s00_axi_rvalid,
		input wire  s00_axi_rready,

		// Ports of Axi Master Bus Interface M00_AXI
		input wire  m00_axi_aclk,
		input wire  m00_axi_aresetn,
		output wire [C_M00_AXI_ADDR_WIDTH-1 : 0] m00_axi_awaddr,
		output wire [2 : 0] m00_axi_awprot,
		output wire  m00_axi_awvalid,
		input wire  m00_axi_awready,
		output wire [C_M00_AXI_DATA_WIDTH-1 : 0] m00_axi_wdata,
		output wire [C_M00_AXI_DATA_WIDTH/8-1 : 0] m00_axi_wstrb,
		output wire  m00_axi_wvalid,
		input wire  m00_axi_wready,
		input wire [1 : 0] m00_axi_bresp,
		input wire  m00_axi_bvalid,
		output wire  m00_axi_bready,
		output wire [C_M00_AXI_ADDR_WIDTH-1 : 0] m00_axi_araddr,
		output wire [2 : 0] m00_axi_arprot,
		output wire  m00_axi_arvalid,
		input wire  m00_axi_arready,
		input wire [C_M00_AXI_DATA_WIDTH-1 : 0] m00_axi_rdata,
		input wire [1 : 0] m00_axi_rresp,
		input wire  m00_axi_rvalid,
		output wire  m00_axi_rready
	);

    wire cs_ready;
    wire [31:0] cs_address;
    wire cs_is_read;
    wire cs_busy;
    wire cs_done;
    wire [31:0] axi_data_in;
    wire [31:0] axi_data_out;
    wire cs_error;

    wire [31:0] scan_address_src;
    wire [31:0] scan_address_dst;
    wire scan_start;
    wire [31:0] scan_length;
    wire scan_done;

// Instantiation of Axi Bus Interface S00_AXI
	fast_ip_scanner_v1_0_S00_AXI # ( 
		.C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
	) fast_ip_scanner_v1_0_S00_AXI_inst (
        .scan_address_src(scan_address_src),
        .scan_address_dst(scan_address_dst),
        .scan_start(scan_start),
        .scan_length(scan_length),
        .scan_done(scan_done),
		.S_AXI_ACLK(s00_axi_aclk),
		.S_AXI_ARESETN(s00_axi_aresetn),
		.S_AXI_AWADDR(s00_axi_awaddr),
		.S_AXI_AWPROT(s00_axi_awprot),
		.S_AXI_AWVALID(s00_axi_awvalid),
		.S_AXI_AWREADY(s00_axi_awready),
		.S_AXI_WDATA(s00_axi_wdata),
		.S_AXI_WSTRB(s00_axi_wstrb),
		.S_AXI_WVALID(s00_axi_wvalid),
		.S_AXI_WREADY(s00_axi_wready),
		.S_AXI_BRESP(s00_axi_bresp),
		.S_AXI_BVALID(s00_axi_bvalid),
		.S_AXI_BREADY(s00_axi_bready),
		.S_AXI_ARADDR(s00_axi_araddr),
		.S_AXI_ARPROT(s00_axi_arprot),
		.S_AXI_ARVALID(s00_axi_arvalid),
		.S_AXI_ARREADY(s00_axi_arready),
		.S_AXI_RDATA(s00_axi_rdata),
		.S_AXI_RRESP(s00_axi_rresp),
		.S_AXI_RVALID(s00_axi_rvalid),
		.S_AXI_RREADY(s00_axi_rready)
	);

// Instantiation of Axi Bus Interface M00_AXI
	fast_ip_scanner_v1_0_M00_AXI # ( 
		.C_M_AXI_ADDR_WIDTH(C_M00_AXI_ADDR_WIDTH),
		.C_M_AXI_DATA_WIDTH(C_M00_AXI_DATA_WIDTH)
	) fast_ip_scanner_v1_0_M00_AXI_inst (
        .cs_ready(cs_ready),
        .cs_address(cs_address),
        .cs_data_i(axi_data_in),
        .cs_is_read(cs_is_read),
        .cs_busy(cs_busy),
        .cs_done(cs_done),
        .cs_data_o(axi_data_out),
		.ERROR(cs_error),
		.M_AXI_ACLK(m00_axi_aclk),
		.M_AXI_ARESETN(m00_axi_aresetn),
		.M_AXI_AWADDR(m00_axi_awaddr),
		.M_AXI_AWPROT(m00_axi_awprot),
		.M_AXI_AWVALID(m00_axi_awvalid),
		.M_AXI_AWREADY(m00_axi_awready),
		.M_AXI_WDATA(m00_axi_wdata),
		.M_AXI_WSTRB(m00_axi_wstrb),
		.M_AXI_WVALID(m00_axi_wvalid),
		.M_AXI_WREADY(m00_axi_wready),
		.M_AXI_BRESP(m00_axi_bresp),
		.M_AXI_BVALID(m00_axi_bvalid),
		.M_AXI_BREADY(m00_axi_bready),
		.M_AXI_ARADDR(m00_axi_araddr),
		.M_AXI_ARPROT(m00_axi_arprot),
		.M_AXI_ARVALID(m00_axi_arvalid),
		.M_AXI_ARREADY(m00_axi_arready),
		.M_AXI_RDATA(m00_axi_rdata),
		.M_AXI_RRESP(m00_axi_rresp),
		.M_AXI_RVALID(m00_axi_rvalid),
		.M_AXI_RREADY(m00_axi_rready)
	);

	// Add user logic here
 /*   scan_core scan_core_inst(
        // Common Signals
		.aclk(m00_axi_aclk),
		.aresetn(m00_axi_aresetn),
        // User-configuration
        ._scan_address_src(scan_address_src),
        ._scan_address_dst(scan_address_dst),
        .scan_start(scan_start),
        .scan_length(scan_length),
        .p_scan_done(scan_done),
        // Scan Signals
        .scan_output(scan_output),
        .p_scan_en_clk(scan_ck_en),
        .p_scan_input(scan_input),
        .p_scan_enable(scan_enable),
        // Interface with the AXI Master
        .cs_ready(cs_ready),
        .cs_address(cs_address),
        .cs_data_i(cs_data_i),
        .cs_is_read(cs_is_read),
        .cs_done(cs_done),
        .cs_data_o(cs_data_o),
        .cs_busy(cs_busy)
    );*/


    scan_core_fifo scan_core_fifo_inst(
        // Common Signals
		.aclk(m00_axi_aclk),
		.aresetn(m00_axi_aresetn),
		.interrupt(interrupt),
        // User-configuration
        ._scan_address_src(scan_address_src),
        ._scan_address_dst(scan_address_dst),
        .scan_start(scan_start),
        .scan_length(scan_length),
        .p_scan_done(scan_done),
        // Scan Signals
        .scan_output(scan_output),
        .p_scan_en_clk(scan_ck_en),
        .p_scan_input(scan_input),
        .p_scan_enable(scan_enable),
        // Interface with the AXI Master
        .cs_ready(cs_ready),
        .cs_address(cs_address),
        .cs_data_i(axi_data_out),
        .cs_is_read(cs_is_read),
        .cs_done(cs_done),
        .cs_data_o(axi_data_in),
        .cs_busy(cs_busy)
    );
	// User logic ends

	endmodule
