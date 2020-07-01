module scan(
  input wire aclk,

  input wire scan_input,
  output wire scan_output,
  output wire scan_ck_enable,
  output wire scan_enable,

  output wire rd_en,
  input wire [31:0] data_in,
  input wire almost_full,

  output wire wr_en,
  output wire [31:0] data_out,
  input wire empty,

  input wire start,
  input wire [15:0] length,
  output wire done
);
begin

parameter [2:0] IDLE  = 3'b001,
  POP                 = 3'b010,
  SCAN_LOW            = 3'b011,
  SCAN_HIGH           = 3'b100,
  PUSH                = 3'b101,
  DONE                = 3'b110,
  PREPARE_POP         = 3'b111;

  reg [2:0] state;
  reg [4:0] scan_input_index;
  reg [4:0] scan_output_index;
  reg [31:0] scanned_length;
  reg [31:0] scan_output_reg;
  reg [31:0] scan_input_reg;

  wire done;

  // increment the scan_output_index and flop the scan_output signal
  always @(posedge aclk, posedge aresetn)
  begin
    if aresetn == 1'b0 begin
      scan_output_index <= 5'b0;
      scan_output_reg   <= 32'b0;
    end else begin
      if state == SCAN_LOW
        scan_output_reg[scan_output_index]   <= scan_output;
        scan_output_index                    <= scan_output_index + 1;
      else if state == IDLE
        scan_output_index <= 5'b0;
      else
        scan_output_index <= scan_output_index;

  // connect fifo data input to the scan_output_reg
  // each time the fsm reach the state 'PUSH', data are pushed
  assign data_in = scan_output_reg;

  // update the scan_input_index 
  always @(posedge aclk, posedge aresetn)
  begin
    if aresetn == 1'b0 begin
      scan_input_index <= 5'b0;
    end else begin
      if state == SCAN_HIGH
        scan_input_index = scan_input_index + 1;
      else if state == IDLE
        scan_input_index <= 5'b0;
      else
        scan_input_index <= scan_input_index;

  // update the scan_input_reg 
  always @(posedge aclk, posedge aresetn)
  begin
    if aresetn == 1'b0 begin
      scan_input_reg   <= 32'b0;
    end else begin
      if state == POP
        scan_input_reg   <= data_out;

  assign scan_input = scan_input_reg[scan_input_index];

  // update the scanned_length register
  always @(posedge aclk, posedge aresetn)
  begin
    if aresetn == 1'b0 begin
      scanned_length   <= 32'b0;
    end else begin
      if state == PUSH
        scanned_length   <= scanned_length + 1;
      else if state == IDLE
        scanned_length == 32'b0;
      else
        scanned_length <= scanned_length;

  assign wr_en = state == PUSH ? 1'b1 : 1'b0;
  assign rd_en = state == POP  ? 1'b1 : 1'b0;
  assign done = scan_output_index == length ? 1'b1: 1'b0;

  assign chunck_done = scan_output_index == 5'D31 ? 1'b1 : 1'b0;

  // finite state machine
  always @(posedge aclk, posedge aresetn)
  begin
    if aresetn == 1'b0 begin
      state = IDLE;
    end else begin
      case(state)
        IDLE:
          if start == 1'b1
            state = PREPARE_POP;
        PREPARE_POP:
          if empty == 1'b0:
            state = POP;
        POP:
          state = SCAN_LOW;
        SCAN_LOW:
          if done == 1'b1
            state = DONE;
          else if chunck_done == 1'b1 
            state = PUSH;
          else
            state = SCAN_HIGH;
        SCAN_HIGH:
          state = SCAN_LOW;
        PUSH:
          if almost_full == 1'b0
            state = PREPARE_POP;
        DONE:
          state = IDLE;
      endcase
    end
  end

  // data
  always @(*)
  begin
    case(state)
      IDLE:
        scan_ck_enable = 1'b0;
        scan_enable    = 1'b0;
        rd_en          = 1'b0;
        wr_en          = 1'b0;
      PREPARE_POP:
        scan_ck_enable = 1'b0;
        scan_enable    = 1'b1;
        rd_en          = 1'b1;
        wr_en          = 1'b0;
      POP:
        scan_ck_enable = 1'b0;
        scan_enable    = 1'b1;
        rd_en          = 1'b0;
        wr_en          = 1'b0;
      PUSH:
        scan_ck_enable = 1'b0;
        scan_enable    = 1'b1;
        rd_en          = 1'b0;
        wr_en          = 1'b1;
      SCAN_LOW:
        scan_ck_enable = 1'b0;
        scan_enable    = 1'b1;
        rd_en          = 1'b0;
        wr_en          = 1'b0;
      SCAN_HIGH:
        scan_ck_enable = 1'b1;
        scan_enable    = 1'b1;
        rd_en          = 1'b0;
        wr_en          = 1'b0;
      DONE:
        scan_ck_enable = 1'b0;
        scan_enable    = 1'b0;
        rd_en          = 1'b0;
        wr_en          = 1'b0;
      default:
        scan_ck_enable = 1'b0;
        scan_enable    = 1'b0;
        rd_en          = 1'b0;
        wr_en          = 1'b0;
    endcase
  end

endmodule;
