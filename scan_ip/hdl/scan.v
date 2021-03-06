module scan(
  input wire aclk,
  input wire aresetn,

  output wire scan_input,
  input wire scan_output,
  output reg scan_ck_enable,
  output reg scan_enable,

  output reg rd_en,
  input wire [31:0] data_out,
  input wire almost_full,

  output reg wr_en,
  output wire [31:0] data_in,
  input wire empty,

  input wire start,
  input wire [15:0] length
  //output wire done
);

parameter [2:0] IDLE  = 3'b001,//1
  POP                 = 3'b010,//2
  SCAN_LOW            = 3'b011,//3
  SCAN_HIGH           = 3'b100,//4
  PUSH                = 3'b101,//5
  DONE                = 3'b110,//6
  PREPARE_POP         = 3'b111,//7
  WAIT_POP            = 3'b000;//0

  reg [2:0] state;
  reg [5:0] scan_input_index;
  reg [5:0] scan_output_index;
  reg [31:0] scanned_length;
  reg [0:31] scan_output_reg;
  reg [0:31] scan_input_reg;

  wire chunck_done;
  wire done;

  // increment the scan_output_index and flop the scan_output signal
  always @(posedge aclk, posedge aresetn)
  begin
    if( aresetn == 1'b0 )begin
      scan_output_index <= 6'b0;
      scan_output_reg   <= 32'b0;
    end else begin
      if( state == SCAN_LOW && scan_output_index[5] == 1'b0 ) begin
        scan_output_reg[scan_output_index]   <= scan_output;
        scan_output_index                    <= scan_output_index + 1;
      end else if( state == PREPARE_POP)
        scan_output_index <= 6'b0;
      else
        scan_output_index <= scan_output_index;
    end
  end

  // connect fifo data input to the scan_output_reg
  // each time the fsm reach the state 'PUSH', data are pushed
  assign data_in = scan_output_reg;

  // update the scan_input_index 
  always @(posedge aclk, posedge aresetn)
  begin
    if( aresetn == 1'b0) begin
      scan_input_index <= 6'b0;
    end else begin
      if( state == SCAN_HIGH && scan_input_index != 6'D31 )
        scan_input_index = scan_input_index + 1;
      else if( state == PREPARE_POP)
        scan_input_index <= 6'b0;
      else
        scan_input_index <= scan_input_index;
    end
  end

  // update the scan_input_reg 
  always @(posedge aclk, posedge aresetn)
  begin
    if( aresetn == 1'b0 )begin
      scan_input_reg   <= 32'b0;
    end else begin
      if( state == WAIT_POP )
        scan_input_reg   <= data_out;
    end
  end

  assign scan_input = scan_input_reg[scan_input_index];

  // update the scanned_length register
  always @(posedge aclk, posedge aresetn)
  begin
    if( aresetn == 1'b0 )begin
      scanned_length   <= 32'D0;
    end else begin
      if( state == SCAN_HIGH)
        scanned_length   <= scanned_length + 1;
      else if( state == IDLE)
        scanned_length <= 32'D0;
      else
        scanned_length <= scanned_length;
    end
  end

  //assign wr_en = state == PUSH ? 1'b1 : 1'b0;
  //assign rd_en = state == POP  ? 1'b1 : 1'b0;
  assign done = scanned_length >= length ? 1'b1: 1'b0;

  assign chunck_done = scan_output_index == 6'D32 ? 1'b1 : 1'b0;

  // finite state machine
  always @(posedge aclk, posedge aresetn)
  begin
    if( aresetn == 1'b0 )begin
      state = IDLE;
    end else begin
      case(state)
        IDLE:
          if( start == 1'b1)
            state = PREPARE_POP;
        PREPARE_POP:
          if( empty == 1'b0)
            state = POP;
        POP:
          state = WAIT_POP;
        WAIT_POP:
          state = SCAN_LOW;
        SCAN_LOW:
          if( done == 1'b1)
            state = DONE;
          else if( chunck_done == 1'b1) 
            state = PUSH;
          else
            state = SCAN_HIGH;
        SCAN_HIGH:
          state = SCAN_LOW;
        PUSH:
          if( almost_full == 1'b0)
            state = PREPARE_POP;
        DONE:
          state = IDLE;
      endcase
    end
  end

  // data
  always @(state)
  begin
    case(state)
      IDLE: 
      begin
        scan_ck_enable = 1'b0;
        scan_enable    = 1'b0;
        rd_en          = 1'b0;
        wr_en          = 1'b0;
      end
      PREPARE_POP:
      begin
        scan_ck_enable = 1'b0;
        scan_enable    = 1'b1;
        rd_en          = 1'b0;
        wr_en          = 1'b0;
      end
      POP:
      begin
        scan_ck_enable = 1'b0;
        scan_enable    = 1'b1;
        rd_en          = 1'b1;
        wr_en          = 1'b0;
      end
      WAIT_POP:
      begin
        scan_ck_enable = 1'b0;
        scan_enable    = 1'b1;
        rd_en          = 1'b0;
        wr_en          = 1'b0;
      end
      PUSH:
      begin
        scan_ck_enable = 1'b0;
        scan_enable    = 1'b1;
        rd_en          = 1'b0;
        wr_en          = 1'b1;
      end
      SCAN_LOW:
      begin
        scan_ck_enable = 1'b0;
        scan_enable    = 1'b1;
        rd_en          = 1'b0;
        wr_en          = 1'b0;
      end
      SCAN_HIGH:
       begin
        scan_ck_enable = 1'b1;
        scan_enable    = 1'b1;
        rd_en          = 1'b0;
        wr_en          = 1'b0;
      end
      DONE:
      begin
        scan_ck_enable = 1'b0;
        scan_enable    = 1'b0;
        rd_en          = 1'b0;
        wr_en          = 1'b1;
      end
      default:
      begin
        scan_ck_enable = 1'b0;
        scan_enable    = 1'b0;
        rd_en          = 1'b0;
        wr_en          = 1'b0;
      end
    endcase
  end

endmodule
