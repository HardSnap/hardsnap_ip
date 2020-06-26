--
-- Author: Nassim Corteggiani
-- Author: Giovanni Camurati
--
-- Brief: GPIF Protocol

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

USE std.textio.all;
use ieee.std_logic_textio.all;

entity GPIF is
  port(
    aclk       : in std_logic;                                -- clock
    aresetn    : in std_logic;                                -- synchronous, active low, reset

    status     : out std_logic_vector(7 downto 0);            -- status

    clk_out    : out std_logic;                               -- output clk 100 Mhz and 180 phase shift
    data       : inout std_logic_vector(31 downto 0);         -- 32bits bi-directionnal data bus
    addr       : out std_logic_vector(1 downto 0);            -- 2 bits data address
    oe	       : out std_logic;                               -- output output enable select (data bus direction)
    op	       : out std_logic;                               -- output write select

    rd_rdy     : in std_logic;                                -- read ready flag
    wr_rdy     : in std_logic;                                -- write ready flag

    -- FIFO READ
    empty      : in std_logic;
    dout       : in std_logic_vector(31 downto 0);
    rd_en      : out std_logic;

    -- FIFO WRITE
    full       : in std_logic;
    din        : out std_logic_vector(31 downto 0);
    wr_en      : out std_logic
  );
end entity GPIF;

architecture beh of GPIF is

  component tristate is
   port (
     fdata_in : out std_logic_vector(31 downto 0);
     fdata    : inout std_logic_vector(31 downto 0);
     fdata_out_d : in std_logic_vector(31 downto 0);
     tristate_en_n : in std_logic
   );
  end component;
 
  component P_ODDR2 is
   port (
     aclk       : in std_logic;
     clk_out    : out std_logic;
     aresetn    : in std_logic
   );
  end component;

  -- fx3 interface
  signal tristate_en_n                   : std_logic;
  signal data_in                         : std_logic_vector(31 downto 0);
  signal data_in_d                       : std_logic_vector(31 downto 0);
  signal data_out_d                      : std_logic_vector(31 downto 0);
  signal rd_rdy_d                        : std_logic;
  signal wr_rdy_d                        : std_logic;
  signal data_mult_cycle_in              : std_logic_vector(31 downto 0);
  signal data_mult_cycle_out             : std_logic_vector(31 downto 0);

  type state_t is (idle,prepare_read,prepare_write,read1,read2,read3,read4,read5,read6,write0,write1,write2,write3, write4);
  signal state: state_t;

begin

  tristate_inst: tristate
  port map(
    fdata_in      => data_in,
    fdata         => data,
    fdata_out_d   => data_out_d,
    tristate_en_n => tristate_en_n 
  );

  ODDR2_inst: P_ODDR2
  port map(
    aclk      => aclk, 
    clk_out   => clk_out,
    aresetn   => aresetn
  );

  -- io flops
  input_flops_proc: process(aclk)
  begin
    if(aclk'event and aclk='1')then
      if(aresetn='0')then
        rd_rdy_d  <= '0';
        wr_rdy_d  <= '0';
        data_in_d <= (others=>'0');
        data_mult_cycle_in <= (others=>'0');
        data_mult_cycle_out <= (others=>'0');
      else
        rd_rdy_d  <= rd_rdy;
        wr_rdy_d  <= wr_rdy;
        data_mult_cycle_in <= data_in;
        data_in_d <= data_mult_cycle_in;
        data_mult_cycle_out <= dout;
      end if;
    end if;
  end process input_flops_proc;

  din <= data_in_d;
  wr_en <= '1' when (state=read6) else '0';
  -- we need to flop the FIFO dout signal for timing issue
  data_out_d <= data_mult_cycle_out;
  rd_en <= '1' when (state=prepare_write) else '0';

  -- state machine
  gpif_master_fsm_proc: process(aclk)
  begin
    if(aclk'event and aclk='1')then
      if(aresetn='0')then
        state <= idle;
        op <= '0';
        oe <= '0';
        tristate_en_n <= '1';
        addr <= "00";
        -- full empty op oe tristate_en_n rd_rdy wr_rdy
        status <= "0" & full & empty & "01000";
      else
        case state is
          when idle =>
              status <= "0" & full & empty & "00" & rd_rdy & wr_rdy & tristate_en_n ;
            if(rd_rdy_d='1' and full='0')then
              state <= prepare_read;
              addr <= "11";
              status <= "0" & full & empty & "00" & rd_rdy & wr_rdy & tristate_en_n;
            elsif(wr_rdy_d='1' and empty='0')then
              state <= prepare_write;
              addr <= "00";
              status <= "1" & full & empty & "00" & rd_rdy & wr_rdy & tristate_en_n ;
            end if;
          when prepare_read =>
            state <= read1;
            op <= '1';
            oe <= '1';
            status <= "0" & full & empty & "11" & rd_rdy & wr_rdy & tristate_en_n;
          when prepare_write =>
            state <= write0;
            --tristate_en_n <= '0';
            status <= "1" & full & empty & "00" & rd_rdy & wr_rdy & tristate_en_n;
          when read1 =>
            state <= read2;
            op <= '0';
            status <= "0" & full & empty & "01" & rd_rdy & wr_rdy & tristate_en_n ;
          when read2 =>
            state <= read3;
            status <= "0" & full & empty & "01" & rd_rdy & wr_rdy & tristate_en_n ;
          when read3 =>
            state <= read4;
            status <= "0" & full & empty & "01" & rd_rdy & wr_rdy & tristate_en_n ;
          when read4 =>
            state <= read5;
            oe <= '0';
            status <= "0" & full & empty & "00" & rd_rdy & wr_rdy & tristate_en_n ;
          when read5 =>
            state <= read6;
            status <= "0" & full & empty & "00" & rd_rdy & wr_rdy & tristate_en_n ;
          when read6 =>
            state <= idle;
            status <= "0" & full & empty & "00" & rd_rdy & wr_rdy & tristate_en_n ;
          -- when read6 =>
          --   state <= read7;
          -- when read7 =>
          --   state <= read8;
          -- when read8 =>
          --   state <= idle;
          --when write0 =>
          --  state <= write1;
          when write0 =>
            state <= write1;
            status <= "1" & full & empty & "00" & rd_rdy & wr_rdy & tristate_en_n;
          when write1 =>
            state <= write2;
            tristate_en_n <= '0';
            status <= "1" & full & empty & "00" & rd_rdy & wr_rdy & tristate_en_n;
          when write2 =>
            state <= write3;
            op <= '1';
            status <= "1" & full & empty & "10" & rd_rdy & wr_rdy & tristate_en_n ;
          when write3 =>
            state <= write4;
            op <= '0';
            tristate_en_n <= '1';
            status <= "1" & full & empty & "00" & rd_rdy & wr_rdy & tristate_en_n ;
          when write4 =>
            state <= idle;
            status <= "1" & full & empty & "00" & rd_rdy & wr_rdy & tristate_en_n ;
          when others =>
            state <= idle;
            tristate_en_n <= '1';
            op <= '0';
            oe <= '0';
            addr <= "00";
            status <= "0" & full & empty &"00" & rd_rdy & wr_rdy & tristate_en_n ;
        end case;
      end if;
    end if;
  end process gpif_master_fsm_proc;

end architecture beh;


