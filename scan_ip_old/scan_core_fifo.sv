`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/10/2019 10:28:19 AM
// Design Name: 
// Module Name: scan_core_fifo
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


module scan_core_fifo(
    input wire aclk,
    input wire aresetn,
    
    output wire interrupt,

    // AXI master interface
    output wire cs_ready,
    output wire [31:0] cs_address,
    output wire cs_is_read,
    output wire cs_done,
    output wire [31:0] cs_data_o,
    input wire [31:0] cs_data_i,
    input wire cs_busy,

    // User configuration
    input  wire [31:0] _scan_address_src,
    input  wire [31:0] _scan_address_dst,
    input  wire [31:0] scan_length,
    input  wire scan_start,
    output wire p_scan_done,
    
    // Scan signal
    output wire p_scan_en_clk,
    output wire p_scan_enable,
    output wire p_scan_input,
    input  wire scan_output    
    );

// local param 
localparam IDLE        = 4'b0000;
localparam INIT_DATA   = 4'b0001;
localparam PREPARE     = 4'b0010;
localparam SCAN        = 4'b0011;
localparam DONE        = 4'b0100;
localparam DONE_2      = 4'B0101;
localparam WAIT_INPUT  = 4'B0110;
localparam WAIT_OUTPUT = 4'B0111;
parameter WIDTH = 32;
parameter [3:0] RW_IDLE = 4'b0000,
        RW_READY            = 4'b0010,
        POP_INPUT_FIFO_WAIT = 4'b0011,
        RW_READ             = 4'b0100,
        DUTY_CYCLE1         = 4'b0101,
        DUTY_CYCLE2         = 4'b0110,
        DUTY_CYCLE3         = 4'b0111,
        POP_INPUT_FIFO_END  = 4'b1000,
        PUSH_OUTPUT_FIFO_END= 4'b1001,
        READ_MEM_END        = 4'b1010,
        WRITE_MEM_END       = 4'b1011,
        POP_OUTPUT_FIFO_END = 4'b1100;

reg scan_clock_en;
reg scan_input;
reg scan_enable;
reg _cs_ready;
reg _cs_is_read;
reg [31:0] _cs_address;
reg [31:0] _cs_data_o;
reg [3:0] fsm_rw_state;
reg [3:0] rw_dst_state;
reg [WIDTH-1:0] output_fifo_data_in;
reg output_fifo_write;
reg output_fifo_read;
reg output_fifo_error;
reg [WIDTH-1:0] input_fifo_data_in;
reg input_fifo_write;
reg input_fifo_read;
reg input_fifo_error;
reg input_request;
reg input_request_done;
reg output_request;
reg output_request_done;
reg [31:0] scan_address_src;
reg [31:0] scan_address_dst;
reg [31:0] read_counter;
reg [3:0] fsm_state;
reg [31:0] scanned_length;
reg [31:0] snapshot_chunk;
reg [4:0] snapshot_chunk_ptr;
reg [31:0] dumped_chunk;
reg [4:0] dumped_chunk_ptr;
reg scan_done;
reg int_reg;
reg scan_start_requested;

wire internal_scan_start;
wire output_fifo_full;
wire output_fifo_empty;
wire output_fifo_not_empty;
wire output_fifo_not_full;
wire [WIDTH-1:0] output_fifo_data_out;
wire [WIDTH-1:0] input_fifo_data_out;
wire input_fifo_full;
wire input_fifo_empty;
wire input_fifo_not_empty;
wire input_fifo_not_full;

assign p_scan_enable   = scan_enable;
assign p_scan_input    = scan_input;
assign p_scan_en_clk   = scan_clock_en;
assign p_scan_done     = scan_done;
assign cs_ready   = _cs_ready;
assign cs_address = _cs_address;
assign cs_is_read = _cs_is_read;
assign cs_data_o  = _cs_data_o;
assign interrupt = int_reg;

fifo #(
    .WIDTH(32),
    .DEPTH(2)
)output_fifo_inst(
    .data_in(output_fifo_data_in),
    .clk(aclk),
    .write(output_fifo_write),
    .read(output_fifo_read),
    .data_out(output_fifo_data_out),
    .fifo_full(output_fifo_full),
    .fifo_empty(output_fifo_empty),
    .fifo_not_empty(output_fifo_not_empty),
    .fifo_not_full(output_fifo_not_full)
);


fifo #(
    .WIDTH(32),
    .DEPTH(2)
)input_fifo_inst(
    .data_in(input_fifo_data_in),
    .clk(aclk),
    .write(input_fifo_write),
    .read(input_fifo_read),
    .data_out(input_fifo_data_out),
    .fifo_full(input_fifo_full),
    .fifo_empty(input_fifo_empty),
    .fifo_not_empty(input_fifo_not_empty),
    .fifo_not_full(input_fifo_not_full)
);


always @(posedge aclk)
begin
    if( aresetn == 1'b0)
    begin
        fsm_rw_state       <= RW_IDLE;
        _cs_ready            <= 1'b0;
        _cs_is_read          <= 1'b0;
        _cs_address          <= 32'H1000_0000;
        _cs_data_o           <= 32'H0000_0000;
        scan_address_src     <= 32'H1000_0000;
        scan_address_dst     <= 32'H1000_0020;
        read_counter         <= 32'h0000_0000;
        input_fifo_write     <= 1'b0;
        input_fifo_data_in   <= 32'b0;
        output_fifo_read     <= 1'b0;
        input_fifo_read      <= 1'b0;
        input_request_done   <= 1'b0;
        output_request_done  <= 1'b0;
    end else begin
        case( fsm_rw_state )
            RW_IDLE:
            begin
                if( internal_scan_start == 1'b1 )
                begin
                    _cs_ready            <= 1'b0;
                    fsm_rw_state         <= RW_READY;
                    rw_dst_state         <= RW_READY;
                end else begin
                    fsm_rw_state         <= IDLE;
                    read_counter         <= 32'h0000_0000;
                    input_fifo_read      <= 1'b0;
                    input_fifo_write     <= 1'b0;
                    output_fifo_write    <= 1'b0;
                    output_fifo_read     <= 1'b0;
                    _cs_ready            <= 1'b0;
                    _cs_is_read          <= 1'b0;
                    scan_address_src     <= _scan_address_src;
                    scan_address_dst     <= _scan_address_dst;
                    input_request_done   <= 1'b0;
                    output_request_done  <= 1'b0;
                end
            end
            POP_INPUT_FIFO_WAIT:
            begin
                if( input_fifo_read == 1'b1 )
                begin
                    input_fifo_read      <= 1'b0;
                end else if ( input_fifo_read == 1'b0 ) begin
                    //snapshot_chunk       <= input_fifo_data_out;
                    input_request_done   <= 1'b1;
                    fsm_rw_state         <= DUTY_CYCLE3;
                    rw_dst_state         <= RW_READY;
                end
            end
            POP_INPUT_FIFO_END:
            begin
                input_request_done   <= 1'b1;
                fsm_rw_state         <= RW_READY;
            end
            POP_OUTPUT_FIFO_END:
            begin
                if( output_fifo_read == 1'b1 )
                begin
                    output_fifo_read      <= 1'b0;
                end else if ( output_fifo_read == 1'b0 ) begin
                    _cs_address            <= scan_address_dst;
                    scan_address_dst       <= scan_address_dst + 4;
                    _cs_is_read            <= 1'b0;
                    _cs_ready              <= 1'b1;
                    _cs_data_o             <= output_fifo_data_out;
                    fsm_rw_state           <= DUTY_CYCLE1;
                    rw_dst_state           <= WRITE_MEM_END;
                    $display("DUMPED CHUNK %H", output_fifo_data_out);
                end
            end
            PUSH_OUTPUT_FIFO_END:
            begin
                if( output_fifo_write == 1'b1)
                begin
                    output_fifo_write    <= 1'b0;
                    output_request_done  <= 1'b1;
                    fsm_rw_state         <= PUSH_OUTPUT_FIFO_END;
                end else begin
                    fsm_rw_state         <= RW_READY;                
                end
            end
            READ_MEM_END:
            begin
                if ( cs_done == 1'b1 && input_fifo_write == 1'b0 )
                begin
                    read_counter       <= read_counter + 32'D32;
                    input_fifo_write   <= 1'b1;
                    input_fifo_data_in <= cs_data_i;
                end else if( cs_done == 1'b1 && input_fifo_write == 1'b1 ) begin
                    input_fifo_write   <= 1'b0;
                    fsm_rw_state       <= RW_READY;
                end else begin
                    fsm_rw_state       <= READ_MEM_END;
                end
            end
            WRITE_MEM_END:
            begin
                if ( cs_done == 1'b1 )
                begin
                    fsm_rw_state       <= RW_READY;
                end else begin
                    fsm_rw_state       <= WRITE_MEM_END;
                end
            end
            RW_READY:
            begin

                output_request_done <= 1'b0;
                input_request_done   <= 1'b0;

                if( input_request == 1'b1 )
                begin
                    if( input_fifo_empty == 1'b1 )
                    begin
                        // FIFO empty, read from memory
                        _cs_address            <= scan_address_src;
                        scan_address_src       <= scan_address_src + 4;
                        _cs_is_read            <= 1'b1;
                        _cs_ready              <= 1'b1;
                        fsm_rw_state           <= DUTY_CYCLE1;
                        rw_dst_state           <= READ_MEM_END;
                    end else begin
                        // FIFO not empty, pop data
                        input_fifo_read        <= 1'b1;
                        fsm_rw_state           <= POP_INPUT_FIFO_WAIT;
                        rw_dst_state           <= RW_READY;
                    end
                end else if ( output_request == 1'b1) begin
                    if( output_fifo_full == 1'b1 )
                    begin
                        // FIFO full, write to memory
                        output_fifo_read       <= 1'b1;
                        fsm_rw_state           <= POP_OUTPUT_FIFO_END;
                        rw_dst_state           <= RW_READY;
                    end else begin
                        // FIFO not empty, pop data
                        output_fifo_write      <= 1'b1;
                        output_fifo_data_in    <= dumped_chunk;
                        fsm_rw_state           <= PUSH_OUTPUT_FIFO_END;
                        rw_dst_state           <= RW_READY;
                    end
                end else if ( (read_counter < scan_length ) && (input_fifo_full == 1'b0) ) begin
                    // Most of the time we come here
                    _cs_address                <= scan_address_src;
                    scan_address_src           <= scan_address_src + 4;
                    _cs_is_read                <= 1'b1;
                    _cs_ready                  <= 1'b1;
                    fsm_rw_state               <= DUTY_CYCLE1;
                    rw_dst_state               <= READ_MEM_END;
                end else if ( output_fifo_empty == 1'b0 ) begin
                    output_fifo_read       <= 1'b1;
                    fsm_rw_state           <= POP_OUTPUT_FIFO_END;
                    rw_dst_state           <= RW_READY;
                end else if (fsm_state == IDLE ) begin
                    fsm_rw_state               <= RW_IDLE;
                end
            end
            DUTY_CYCLE1:
            begin
                 output_fifo_write    <= 1'b0;
                 _cs_ready          <= 1'b0;
                fsm_rw_state        <= DUTY_CYCLE2;
            end
            DUTY_CYCLE2:
            begin
                 _cs_ready          <= 1'b0;
                fsm_rw_state        <= DUTY_CYCLE3;
            end
            DUTY_CYCLE3:
            begin
                 _cs_ready          <= 1'b0;
                fsm_rw_state        <= rw_dst_state;
            end
            default:
            begin
                fsm_rw_state        <= RW_IDLE;
            end
        endcase
    end
end



/*
* SCAN LOGIC
*/

reg scan_start_r;
always @(posedge aclk, posedge aresetn)
begin
    if(aresetn == 1'b0)
    begin
        scan_start_r        <= 1'b0;
    end else
    begin
        scan_start_r <= scan_start;
    end
end

assign internal_scan_start = scan_start_r & ~scan_start;

/*
always @(posedge aclk, posedge aresetn)
begin
    if(aresetn == 1'b0)
    begin
        internal_scan_start        <= 1'b0;
        scan_start_requested       <= 1'b0;
    end else
    begin
        if( scan_start == 1'b1 && scan_start_requested == 1'b0 )
        begin
            internal_scan_start        <= 1'b1;
            scan_start_requested       <= 1'b1;
        end else if( internal_scan_start == 1'b1 )
        begin
            internal_scan_start        <= 1'b0;
        end else if( scan_start == 1'b0 )
        begin
            scan_start_requested <= 1'b0;
        end
    end
end
*/

always @(posedge aclk, posedge aresetn)
begin
    if(aresetn == 1'b0)
    begin
        scan_clock_en      <= 1'b0;
        scan_input         <= 1'b0;
        scan_enable        <= 1'b0;
        snapshot_chunk_ptr <= 5'D31;
        dumped_chunk       <= 32'b0;
        dumped_chunk_ptr   <= 5'D31;
        scanned_length     <= 32'b1;
        fsm_state          <= IDLE;
        scan_done          <= 1'b0;
        input_request      <= 1'b0;
        output_request     <= 1'b0;
        snapshot_chunk     <= 32'h0000_0000;
        int_reg            <= 1'b0;
    end else
    begin
        case(fsm_state)
        IDLE:
        begin
            if( internal_scan_start == 1'b1)
            begin
                scan_done          <= 1'b0;
                scan_clock_en      <= 1'b0;
                scan_enable        <= 1'b1;
                fsm_state          <= WAIT_INPUT;
                snapshot_chunk     <= 32'h0000_0000;
                scanned_length     <= 32'H0000_0001;
                dumped_chunk_ptr   <= 5'D31;
                snapshot_chunk_ptr <= 5'D31;
                dumped_chunk       <= 32'b0;
                input_request      <= 1'b1;
                output_request     <= 1'b0;
                int_reg            <= 1'b0;
            end else begin
                input_request      <= 1'b0;
                output_request     <= 1'b0;
                fsm_state          <= IDLE;
                int_reg            <= 1'b0;
            end
        end
        WAIT_INPUT:
        begin
            if( (input_request == 1'b1) && (input_request_done == 1'b1) )
            begin
                snapshot_chunk      <= input_fifo_data_out;
                input_request       <= 1'b0;

                scan_input          <= input_fifo_data_out[31];
                snapshot_chunk_ptr  <= 5'D30;

                if( scanned_length == 32'H0000_0001)
                begin
                    dumped_chunk[31]    <= scan_output;
                    dumped_chunk_ptr    <=  5'D30;

                    scan_clock_en       <= 1'b1;
                    fsm_state           <= SCAN;
                end else if ( output_request == 1'b1 ) begin
                        fsm_state       <= WAIT_OUTPUT;
                end else begin
                        fsm_state       <= SCAN;
                end
            end else begin
                fsm_state <= WAIT_INPUT;
            end
        end
        WAIT_OUTPUT:
        begin
            if ( (output_request == 1'b1) && (output_request_done == 1'b1) ) begin
//                scan_clock_en       <= 1'b1;
                fsm_state           <= SCAN;
                output_request      <= 1'b0;
            end else begin
                fsm_state           <= WAIT_OUTPUT;
            end        
        end
        PREPARE:
        begin
            scan_clock_en       <= 1'b0;
            fsm_state           <= SCAN;
        end
        SCAN:
        begin
            if(scan_clock_en == 1'b0)
            begin

                dumped_chunk[dumped_chunk_ptr] <= scan_output;
                dumped_chunk_ptr    <= dumped_chunk_ptr - 1;

                if( scanned_length == scan_length)
                begin
                    fsm_state   <= DONE;
                    scan_enable <= 1'b0;
                end else begin
                    scan_clock_en  <= 1'b1;
                    scanned_length <= scanned_length + 1;
                end
            end else begin
                scan_clock_en  <= 1'b0;

                if( dumped_chunk_ptr == 5'D31 )
                begin
                    input_request  <= 1'b1;
                    output_request <= 1'b1;
                    fsm_state      <= WAIT_INPUT;
                    snapshot_chunk <= 32'h0000_0000;
                end else begin
                    scan_input     <= snapshot_chunk[snapshot_chunk_ptr];
                    snapshot_chunk_ptr <= snapshot_chunk_ptr- 1;
                end
            end
        end
        DONE:
        begin
            fsm_state                      <= DONE_2;
            dumped_chunk[dumped_chunk_ptr] <= scan_output;
            dumped_chunk_ptr               <= dumped_chunk_ptr - 1;
            output_request                 <= 1'b1;
        end
        DONE_2:
        begin
            if( output_request_done == 1'b1)
            begin
                output_request <= 1'b0;
                fsm_state      <= IDLE;
                scan_done      <= 1'b1;
                int_reg        <= 1'b1;
            end else begin
                output_request <= 1'b1;
                fsm_state      <= DONE_2;
            end
        end
        default:
            fsm_state <= IDLE;
       endcase
    end
end

endmodule
