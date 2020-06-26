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

entity Dispatcher is
  port(
    aclk       : in std_logic;                                -- clock
    aresetn    : in std_logic;                                -- synchronous, active low, reset

    status     : out std_logic_vector(7 downto 0);            -- status

    -- FIFO READ
    empty      : in std_logic;
    dout       : in std_logic_vector(63 downto 0);
    rd_en      : out std_logic;

    -- FIFO WRITE
    full       : in std_logic;
    din        : out std_logic_vector(31 downto 0);
    wr_en      : out std_logic;

    data                : out std_logic_vector(31 downto 0);
    addr                : out std_logic_vector(31 downto 0);
    target_res          : in std_logic_vector(31 downto 0);
    target_busy         : in std_logic;
    target_start_read   : out std_logic;
    target_start_write  : out std_logic
  );
end entity Dispatcher;

architecture beh of Dispatcher is

  component MemAP is
    port (
      aclk       : in std_logic;
      aresetn    : in std_logic;
      wr         : out std_logic;
      data       : out std_logic_vector(31 downto 0);
      addr       : out std_logic_vector(31 downto 0);
      res        : out std_logic_vector(31 downto 0);
      busy       : in std_logic
    );
  end component;

  type state_t is (idle,do,pre_load,done,wait_completion,readback);
  signal state: state_t;

  --signal target_res: std_logic;
  --signal target_busy: std_logic;
  --signal target_start_read: std_logic;
  --signal target_start_write: std_logic;

begin

  data <= dout( 63 downto 32);
  addr <= dout( 31 downto 1) & "0";
  din  <= target_res;

  -- state machine
  dispatcher_fsm_proc: process(aclk)
  begin
    if(aclk'event and aclk='1')then
      if(aresetn='0')then
        state <= idle;
        rd_en <= '0'; 
        wr_en <= '0'; 
        target_start_read  <= '0';
        target_start_write <= '0';
      else
        case state is
          when idle =>
            rd_en <= '0';
            wr_en <= '0'; 
            target_start_read  <= '0';
            target_start_write <= '0';
            if (empty = '0' and target_busy='0') then
              state <= pre_load;
              rd_en <= '1';
            end if;
          when pre_load =>
            state <= do;
            rd_en <= '0'; 
            wr_en <= '0'; 
            target_start_read  <= '0';
            target_start_write <= '0';
          when do =>
            rd_en <= '0';
            wr_en <= '0';
            if (dout(0) = '1') then
              state <= wait_completion;
              target_start_read  <= '1';
              target_start_write <= '0';
            else
              state <= done;
              target_start_read  <= '0';
              target_start_write <= '1';
            end if;
          when done =>
            state <= idle;
            rd_en <= '0'; 
            wr_en <= '0'; 
            target_start_read  <= '0';
            target_start_write <= '0';
          when wait_completion  =>
            rd_en <= '0'; 
            wr_en <= '0'; 
            target_start_read  <= '0';
            target_start_write <= '0';
            if (target_busy = '0') then
              state <= readback;
            end if;
          when readback =>
              state <= idle;
              rd_en <= '0';
              wr_en <= '1';
              target_start_read  <= '0';
              target_start_write <= '0';
        end case;
      end if;
    end if;
  end process dispatcher_fsm_proc;

end architecture beh;
