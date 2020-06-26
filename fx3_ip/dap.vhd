library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

USE std.textio.all;
use ieee.std_logic_textio.all;

entity dap is
  Port (
    aclk:       in std_logic;  -- Clock
    aresetn:    in std_logic;  -- Synchronous, active low, reset

    led:            out std_logic_vector(7 downto 0); -- LEDs

    --irq_in:         in std_logic;
    irq_bus:        in std_logic_vector(31 downto 0);

    mem_ap_busy      : in std_logic;
    mem_ap_done      : in std_logic;
    mem_ap_read_data : in std_logic_vector(31 downto 0);
    mem_ap_write_data: out std_logic_vector(31 downto 0);
    mem_ap_start     : out std_logic;
    mem_ap_address   : out std_logic_vector(31 downto 0);
    mem_ap_is_read   : out std_logic;

    -----------------------
    -- slave fifo master --
    -----------------------
    clk_out	   : out std_logic;                               ---output clk 100 Mhz and 180 phase shift
    fdata          : inout std_logic_vector(31 downto 0);
    sladdr         : out std_logic_vector(1 downto 0);
    sloe	   : out std_logic;                               ---output output enable select
    slop	   : out std_logic;                               ---output write select

    slwr_rdy	   : in std_logic;
    slwrirq_rdy	   : in std_logic;
    slrd_rdy	   : in std_logic

  );
end entity dap;

architecture beh of dap is

  component fifo_ram is
  generic(
    width: natural := 32;
    addr_size: natural := 4
  );
  port(
    aclk:  in  std_logic;
    aresetn: in std_logic;
    empty: out std_logic;
    full:  out std_logic;
    put:   in  std_logic;
    get:   in  std_logic;
    din:   in  std_logic_vector(width-1 downto 0);
    dout:  out std_logic_vector(width-1 downto 0)
  );
  end component;

  component fifo_ram_32_to_64 is
  generic(
    width: natural := 32;
    addr_size: natural := 4
  );
  port(
    aclk:  in  std_logic;
    aresetn: in std_logic;
    empty: out std_logic;
    full:  out std_logic;
    put:   in  std_logic;
    get:   in  std_logic;
    din:   in  std_logic_vector(width-1 downto 0);
    dout:  out std_logic_vector((width*2)-1 downto 0)
  );
  end component;

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

  type cmd_read_state_t is (IDLE,READ,START_MEMAP,WAIT_COMPLETION,SYNC,CHECK_FOR_READBACK,PREPARE_READBACK,DO_READBACK,PREPARE_SECOND_READBACK,DO_SECOND_READBACK);
  signal cmd_read_state : cmd_read_state_t;

  signal readback : std_logic;
  signal payload  : std_logic_vector(31 downto 0);
  signal address  : std_logic_vector(31 downto 0);
  signal sync_cnt : unsigned (3 downto 0);
  signal read_cnt : std_logic;

  signal cmd_empty,data_empty,irq_empty: std_logic;
  signal cmd_full,data_full,irq_full:   std_logic;
  signal cmd_put,data_put,irq_put:     std_logic;
  signal cmd_get,data_get,irq_get:     std_logic;
  signal cmd_din,data_din,irq_din:     std_logic_vector(31 downto 0);
  signal cmd_dout:                     std_logic_vector(63 downto 0);
  signal data_dout,irq_dout:           std_logic_vector(31 downto 0);

  -- fx3 interface
  signal tristate_en_n:                   std_logic;
  signal fdata_in,fdata_in_d,fdata_out_d: std_logic_vector(31 downto 0);
  signal slrd_rdy_d,slwr_rdy_d,slwrirq_rdy_d:           std_logic;

  type sl_state_t is (idle,prepare_read,prepare_write_irq,prepare_write_data,read1,read2,read3,read4,read5,write0,write1,write2);
  signal sl_state: sl_state_t;
  signal sl_is_irq: std_logic;

  -- irq
  signal irq_sync, irq_d1, irq_d2, irq_d3: std_logic;
  type irq_state_t is (idle,wait_fifo,forward_event,wait_fifo2,forward_event2,done);
  signal irq_state: irq_state_t;
  signal irq_id_addr: std_logic_vector(31 downto 0);

  signal irq_in: std_logic;
 begin

  -----------------------------
  -- irq address --------------
  -----------------------------
  --irq_id_addr_proc: process(aclk)
  --begin
  --  if(aclk'event and aclk='1')then
  --    if(aresetn='0')then
  --      if(daisy_normal_n='1')then
  --        irq_id_addr <= IRQ_ID_ADDR_DEFAULT_STM32L152RE;
	--else
  --        irq_id_addr <= IRQ_ID_ADDR_DEFAULT_LPC1850;
	--end if;
  --    elsif(btn1_re='1')then
  --      irq_id_addr <= std_logic_vector(r);
  --    end if;
  --  end if;
  --end process irq_id_addr_proc;

  -----------------------------
  -- synchronize irq_in line --
  -----------------------------
  --irq_sync <= irq_d1;
  ----irq_sync <= irq_d3;
  --irq_sync_proc: process(aclk)
  --begin
  --  if(aclk'event and aclk='1')then
  --    if(aresetn='0')then
  --      irq_d1 <= '0';
	--      --irq_d2 <= '0';
	--      --irq_d2 <= '0';
  --    else
  --      irq_d1 <= irq_in;
	--      --irq_d2 <= irq_d1;
	--      --irq_d3 <= irq_d2;
  --    end if;
  --  end if;
  --end process irq_sync_proc;

  -----------------------
  --irq_in state machine --
  -----------------------
  irq_in <= '0';
  irq_din <= irq_bus;
  irq_put <= '1' when (irq_state = forward_event or irq_state = forward_event2) else '0';
  irq_fsm_proc: process(aclk)
  begin
    if(aclk'event and aclk='1')then
      if(aresetn='0')then
        irq_state <= idle;
      else
        case irq_state is
          when idle =>
	          if(irq_in='1')then
              irq_state <= wait_fifo;
	          end if;
          when wait_fifo =>
            if(irq_full='0')then
              irq_state <= forward_event;
            end if;
          when forward_event =>
	          irq_state <= wait_fifo2;
          when wait_fifo2 =>
            if(irq_full='0')then
              irq_state <= forward_event2;
            end if;
          when forward_event2 =>
	          irq_state <= done;
          when done =>
	          irq_state <= idle;
	        when others =>
	          irq_state <= done;
	      end case;
      end if;
    end if;
  end process irq_fsm_proc;


  --------------------------------------------------------
  -- local fifo to store commands reveived from the fx3 --
  --------------------------------------------------------
  cmd_fifo_inst : fifo_ram_32_to_64
    generic map(
      width => 32,
      addr_size => 2
    )
    port map(
      aclk => aclk,
      aresetn => aresetn,
      empty => cmd_empty,
      full => cmd_full,
      put => cmd_put,
      get => cmd_get,
      din => cmd_din,
      dout => cmd_dout
    );

  -------------------------------------------------------------
  -- local fifo to store data received from the jtag machine --
  -------------------------------------------------------------
  data_fifo_inst: fifo_ram
    generic map(
      width => 32,
      addr_size => 2
    )
    port map(
      aclk     => aclk,
      aresetn  => aresetn,
      empty    => data_empty,
      full     => data_full,
      put      => data_put,
      get      => data_get,
      din      => data_din,
      dout     => data_dout
    );

  ------------------------------------------------------------------
  -- local fifo to store irq id data coming from the jtag machine --
  ------------------------------------------------------------------
  irq_fifo_inst: fifo_ram
    generic map(
      width => 32,
      addr_size => 2
    )
    port map(
      aclk     => aclk,
      aresetn  => aresetn,
      empty    => irq_empty,
      full     => irq_full,
      put      => irq_put,
      get      => irq_get,
      din      => irq_din,
      dout     => irq_dout
    );

  -------------------------------------
  -- logic to interface with the fx3 --
  -------------------------------------

  tristate_inst: tristate
  port map(
    fdata_in      => fdata_in,
    fdata         => fdata,
    fdata_out_d   => fdata_out_d,
    tristate_en_n => tristate_en_n 
  );

  -- io flops
  input_flops_proc: process(aclk)
  begin
    if(aclk'event and aclk='1')then
      if(aresetn='0')then
        slrd_rdy_d <= '0';
	slwr_rdy_d <= '0';
	slwrirq_rdy_d <= '0';
	fdata_in_d <= (others=>'0');
      else
        slrd_rdy_d <= slrd_rdy;
	slwr_rdy_d <= slwr_rdy;
	slwrirq_rdy_d <= slwrirq_rdy;
	fdata_in_d <= fdata_in;
     end if;
    end if;
  end process input_flops_proc;

  --led <= fdata_in_d(31 downto 24);

  -- state machine
  cmd_din <= fdata_in_d;
  cmd_put <= '1' when (sl_state=read5) else '0';
  fdata_out_d <= irq_dout when (sl_is_irq='1') else data_dout;
  data_get <= '1' when (sl_state=prepare_write_data) else '0';
  irq_get  <= '1' when (sl_state=prepare_write_irq ) else '0';
  --irq_din  <= (others => '0');
  --tristate_en_n <= '0' when (sl_state=write1) else '1';
  fx3_sl_master_fsm_proc: process(aclk)
  begin
    if(aclk'event and aclk='1')then
      if(aresetn='0')then
        sl_state <= idle;
	slop <= '0';
	sloe <= '0';
	tristate_en_n <= '1';
	sladdr <= "00";
	sl_is_irq <= '0';
      else
        case sl_state is
	  when idle =>
	    if(slwrirq_rdy_d='1' and irq_empty='0')then
              sl_state <= prepare_write_irq;
	      sladdr <= "01";
	      sl_is_irq <= '1';
	    elsif(slwr_rdy_d='1' and data_empty='0')then
	      sl_state <= prepare_write_data;
	      sladdr <= "00";
	      sl_is_irq <= '0';
	    elsif(slrd_rdy_d='1' and cmd_full='0')then
	      sl_state <= prepare_read;
	      sladdr <= "11";
	      sl_is_irq <= '0';
	    end if;
	  when prepare_read =>
            sl_state <= read1;
	    slop <= '1';
	    sloe <= '1';
          when prepare_write_data =>
	    sl_state <= write0;
	    tristate_en_n <= '0';
	  when prepare_write_irq =>
	    sl_state <= write0;
	    tristate_en_n <= '0';
	  when read1 =>
	    sl_state <= read2;
	    slop <= '0';
	  when read2 =>
	    sl_state <= read3;
	  when read3 =>
	    sl_state <= read4;
	  when read4 =>
	    sl_state <= read5;
	    sloe <= '0';
	  when read5 =>
	    sl_state <= idle;
	 -- when read6 =>
	 --   sl_state <= read7;
	 -- when read7 =>
	 --   sl_state <= read8;
	 -- when read8 =>
	 --   sl_state <= idle;
	  when write0 =>
	    sl_state <= write1;
	    slop <= '1';
	  when write1 =>
	    sl_state <= write2;
	    slop <= '0';
	    tristate_en_n <= '1';
          when write2 =>
	    sl_state <= idle;
	  when others =>
	    sl_state <= idle;
	    slop <= '0';
	    sloe <= '0';
	    tristate_en_n <= '1';
	    sladdr <= "00";
        end case;
      end if;
    end if;
  end process fx3_sl_master_fsm_proc;

  readback              <= cmd_dout(0);
  address               <= cmd_dout(31 downto 1)&'0';
  payload               <= cmd_dout(63 downto 32);

  cmd_read_state_logic: process(aclk)
  begin
    if( aclk'event and aclk = '1' ) then
      if( aresetn = '0' ) then
        cmd_read_state <= IDLE;
        --readback       <= '0';
        --payload        <= std_logic_vector(to_unsigned(0,32));
        --address        <= std_logic_vector(to_unsigned(0,32));
        sync_cnt       <= (others=>'0');
      else 
          case cmd_read_state is
            when IDLE =>
              if( cmd_empty = '0' and mem_ap_busy = '0' ) then
                cmd_read_state <= READ;
              end if;
            when READ =>
                cmd_read_state <= START_MEMAP;
            when START_MEMAP =>
              cmd_read_state        <= SYNC;
              sync_cnt              <= (others=>'0');
            when SYNC =>
              if( sync_cnt = 3) then
                cmd_read_state        <= WAIT_COMPLETION;
                sync_cnt              <= (others=>'0');
              else
                sync_cnt              <= sync_cnt + 1;
                cmd_read_state        <= SYNC;
              end if;
            when WAIT_COMPLETION =>
              if( mem_ap_busy = '0' and mem_ap_done = '1' ) then
                cmd_read_state <= CHECK_FOR_READBACK;
              end if;
            when CHECK_FOR_READBACK =>
              if( readback = '1' ) then
                  cmd_read_state      <= PREPARE_READBACK;
              else
                  cmd_read_state      <= IDLE;
              end if;
            when PREPARE_READBACK =>
              if( data_full = '1' ) then
                cmd_read_state        <= PREPARE_READBACK;
              else
                cmd_read_state        <= DO_READBACK;
              end if;
            when DO_READBACK         =>
                cmd_read_state          <= PREPARE_SECOND_READBACK;
            when PREPARE_SECOND_READBACK         =>
              if( data_full = '1' ) then
                cmd_read_state        <= PREPARE_SECOND_READBACK;
              else
                cmd_read_state        <= DO_SECOND_READBACK;
              end if;
            when DO_SECOND_READBACK         =>
                cmd_read_state          <= IDLE;
            when others =>
              cmd_read_state <= IDLE;
          end case;

      end if;
    end if;
  end process cmd_read_state_logic;
  
  mem_ap_write_data <= payload;
  mem_ap_address    <= address;
  mem_ap_is_read    <= readback;
  data_din          <= mem_ap_read_data;
  --led(4 downto 0)   <= cmd_empty&cmd_full&data_empty&data_full&readback;
  led(4 downto 0)   <= slrd_rdy_d&slwr_rdy_d&slwrirq_rdy_d&irq_in&irq_empty;

  -- cmd_read_out_logic set the outputs of the cmd_read_state_logic process
  cmd_read_out_logic: process(cmd_read_state, readback, data_full)
  begin
      case cmd_read_state is
        when IDLE =>
          led(7 downto 5)<= "111"; 
          cmd_get        <= '0';
          mem_ap_start   <= '0';
          data_put       <= '0';
        when READ =>
          led(7 downto 5)<= "001"; 
          cmd_get        <= '1';
          mem_ap_start   <= '0';
          data_put       <= '0';
        when START_MEMAP =>
          led(7 downto 5)<= "010"; 
          cmd_get        <= '0';
          mem_ap_start   <= '1';
          data_put       <= '0';
        when SYNC =>
          led(7 downto 5)<= "011"; 
          cmd_get        <= '0';
          mem_ap_start   <= '0';
          data_put       <= '0';
        when WAIT_COMPLETION =>
          led(7 downto 5)<= "100"; 
          cmd_get        <= '0';
          mem_ap_start   <= '0';
          data_put       <= '0';
        when CHECK_FOR_READBACK =>
          led(7 downto 5)<= "101"; 
          cmd_get        <= '0';
          mem_ap_start   <= '0';
          data_put       <= '0';
        when PREPARE_READBACK =>
          led(7 downto 5)<= "110"; 
          cmd_get        <= '0';
          mem_ap_start   <= '0';
          data_put       <= '0';
        when DO_READBACK =>
          led(7 downto 5)<= "110"; 
          cmd_get        <= '0';
          mem_ap_start   <= '0';
          data_put       <= '1';
        when PREPARE_SECOND_READBACK =>
          led(7 downto 5)<= "110"; 
          cmd_get        <= '0';
          mem_ap_start   <= '0';
          data_put       <= '0';
        when DO_SECOND_READBACK =>
          led(7 downto 5)<= "110"; 
          cmd_get        <= '0';
          mem_ap_start   <= '0';
          data_put       <= '1';
        when others => 
          led(7 downto 5)<= "000"; 
          cmd_get        <= '0';
          mem_ap_start   <= '0';
          data_put       <= '0';
      end case;
  end process cmd_read_out_logic; 

  ODDR2_inst: P_ODDR2
  port map(
    aclk      => aclk, 
    clk_out   => clk_out,
    aresetn   => aresetn
  );

  -- LED outputs
  --led <= cmd_empty&cmd_full&data_empty&data_full&irq_empty&irq_full&readback&'0';

end architecture beh;



