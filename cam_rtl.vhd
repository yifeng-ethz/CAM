-- File name: cam_rtl.vhd 
-- Author: Yifeng Wang
-- =======================================
-- Revision: 1.0 (file created)
--		Date: August 29, 2023
-- Revision: 2.0 (port trimming)
--		Date: August 31, 2023
-- Revision: 3.0 (erase-ram added)
--		Date: September 4, 2023
-- Revision: 3.1 (debug and verified)
--		Date: September 14, 2023
-- Revision: 4.0 (encode match-address/count/flag)
--		Date: September 20, 2023
-- Revision: 5.0 (add init rom to initialize the CAM)
--		Date: September 27, 2023
-- =======================================
-- Description:	Controls cam_mem_a5, reg-out, and addressing.  
-- Description:	CAM := Input = search keyword, output = address. 
--	Init the Intel RAM IP for the CAM customized IP core. 
--	Control the erase and in/out signals to the ram block.
--	
-- ================ synthsizer configuration =================== 		
-- altera vhdl_input_version vhdl_2008
-- ============================================================= 
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_arith.conv_std_logic_vector;
use IEEE.math_real.log2;
use IEEE.math_real.ceil;

entity cam_rtl is
	generic(
		CAM_SIZE			: natural := 128; 
		CAM_WIDTH			: natural := 16;
		ADDR_WIDTH			: natural := 7; 
		OCCUPANCY_CHECK		: boolean := True; -- check if match before write, always true for Single-Match mode
		ENCODE_ADDRESS_OUT	: boolean := True);
	port(
		i_clk					: in std_logic;
		i_rst					: in std_logic;
		i_wr_en					: in std_logic;
		i_init_en				: in std_logic;
		i_wr_data				: in std_logic_vector(CAM_WIDTH-1 downto 0);
		i_wr_addr				: in std_logic_vector(ADDR_WIDTH-1 downto 0);
		i_cmp_din				: in std_logic_vector(CAM_WIDTH-1 downto 0);
		o_match_flag			: out std_logic;
		o_cam_match_count			: out std_logic_vector(ADDR_WIDTH-1 downto 0);
		o_cam_match_addr			: out std_logic_vector(ADDR_WIDTH-1 downto 0);
		o_cam_wr_rd				: out std_logic
	);
	
end cam_rtl;

architecture rtl of cam_rtl is 

	constant RAM_TYPE_0 			: string := "Simple Dual-Port RAM";
	constant RAM_TYPE_1 			: string := "True Dual-Port RAM";
	
	constant CAM_DATA_BITS			: natural := integer(ceil(real(CAM_WIDTH)/8.0)*8.0); -- 16, round up to 8's multiple
	constant CAM_ADDR_BITS			: natural := integer(ceil(log2(real(CAM_SIZE)))); -- 7, for 128, round up
	
	signal clk,rst					: std_logic := '1';
	signal wr_en, init_en			: std_logic := '0';
	signal wr_data 					: std_logic_vector(CAM_DATA_BITS-1 downto 0);
	signal wr_addr					: std_logic_vector(CAM_ADDR_BITS-1 downto 0);

	signal erase_ram_addr			: std_logic_vector(CAM_ADDR_BITS-1 downto 0);
	signal erase_ram_din			: std_logic_vector(CAM_DATA_BITS-1 downto 0);
	signal erase_ram_we				: std_logic := '0';
	signal erase_ram_dout			: std_logic_vector(CAM_DATA_BITS-1 downto 0);
	
	signal init_rom_addr			: std_logic_vector(CAM_ADDR_BITS-1 downto 0);
	signal init_rom_dout			: std_logic_vector(CAM_DATA_BITS-1 downto 0);
	signal init_inproc				: std_logic := '0';
	
	signal cam_erase_en				: std_logic := '0';
	signal cam_wr_en				: std_logic := '0';
	signal cam_wr_data				: std_logic_vector(CAM_DATA_BITS-1 downto 0);
	signal cam_wr_addr				: std_logic_vector(CAM_ADDR_BITS-1 downto 0);
	signal cam_CMP_DIN				: std_logic_vector(CAM_DATA_BITS-1 downto 0);
	signal cam_match_addr_raw		: std_logic_vector(CAM_SIZE-1 downto 0);
	signal cam_match_count			: std_logic_vector(CAM_ADDR_BITS-1 downto 0);
	signal cam_match_addr			: std_logic_vector(CAM_ADDR_BITS-1 downto 0);
	signal cam_MATCH_FLAG			: std_logic := '0';
	signal cam_wr_rd				: std_logic := '0';
	
	type cam_state_t is (CAM_ERASE,CAM_WRITE,CAM_INIT,CAM_IDLE);
	signal cam_state 				: cam_state_t;
	--signal curr_st,next_st			: cam_state_t;
	
--	type temp_address_t is array(0 to CAM_SIZE) of std_logic_vector(6 downto 0);-- range 0 to CAM_SIZE;
--	signal temp_address 			: temp_address_t;
	
	component cam_init_rom is 
		generic(
			DATA_WIDTH : natural;
			ADDR_WIDTH : natural);
		port(	
			addr	: in std_logic_vector(CAM_ADDR_BITS-1 downto 0);
			q		: out std_logic_vector(CAM_DATA_BITS-1 downto 0)
			);
	end component cam_init_rom;

begin 
	
	clk <= i_clk;
	rst <= i_rst;
	
	-- trimming IO width (not necessary if not in the top level)
	wr_en 		<= i_wr_en;
	init_en		<= i_init_en;
	wr_data 	<= i_wr_data(CAM_DATA_BITS-1 downto 0); -- 16
	wr_addr 	<= i_wr_addr(CAM_ADDR_BITS-1 downto 0); -- 7
	cam_CMP_DIN 	<= i_cmp_din(CAM_DATA_BITS-1 downto 0); -- 16
	o_match_flag 	<= cam_MATCH_FLAG; -- 1
	o_cam_match_count(CAM_ADDR_BITS-1 downto 0) 	<= cam_match_count; -- 7
	o_cam_match_addr(CAM_ADDR_BITS-1 downto 0)		<= cam_match_addr;
	o_cam_wr_rd <= cam_wr_rd;
	
	-- detect the edge of write-enable
--	e_edge_we	: entity work.edge_det
--	port map(
--		i_clk		=> clk,
--		i_rst		=> rst,
--		i_trig		=> wr_en,
--		o_pulse		=> wr_en_pulse
--	);
--	
	-- encode cam_match_addr/count/flag (validated up to depth of 128)
	e_enc_logic	: entity work.addr_enc_logic 
	generic map(
		CAM_SIZE 		=> CAM_SIZE,
		CAM_ADDR_BITS 	=> CAM_ADDR_BITS
	)
	port map(
		i_cam_address_onehot	=> cam_match_addr_raw,
		o_cam_address_binary	=> cam_match_addr,
		o_cam_match_flag		=> cam_MATCH_FLAG,
		o_cam_match_count		=> cam_match_count
	);
	
	
	
	-- control logic (reg) for state machine next state
	process(clk, rst)
	begin
		if (rst = '1') then
			cam_state <= CAM_IDLE;
		elsif rising_edge(clk) then
			if (init_en = '1' or init_inproc = '1') then
				cam_state <= CAM_INIT;
			else
				case cam_state is 
					when CAM_ERASE =>
						if (wr_en = '1') then
							cam_state <= CAM_WRITE;
						else 
							cam_state <= CAM_ERASE;
						end if;
					when CAM_WRITE =>
						cam_state <= CAM_ERASE;
					when others =>
						cam_state <= CAM_ERASE;
				end case;
			end if;
		end if;
	end process;
	
	-- control logic (reg) of init process
	process(clk, rst)
	begin
		if (rst = '1') then
			init_rom_addr 	<= (others=>'0');
		elsif rising_edge(clk) then
			if (init_inproc = '1') then
				init_rom_addr 	<= conv_std_logic_vector((to_integer(unsigned(init_rom_addr)) + 1), init_rom_addr'length); 
			else
				init_rom_addr 	<= (others=>'0');
			end if;
		end if;
	end process;
	
	-- comb out of cam state machine 
	process (cam_state, wr_en)
	begin
		
		case cam_state is
			when CAM_ERASE => -- idle state to start with
			-- If write, check current data at the targeted cam location.
			-- Use the current data and address to clear the cam with 1-bit port (write '0'). It might be redundant, because if the data is 0, 
			-- the cam will unset with its 1-bit port, resulting clear the data 0 store at this location. 
			-- TO NOTE: for uninitialized CAM, the data is at a specific location is invalid, meaning nothing is stored at this location. When look-up is performed,
			-- the result is null/not-found. Therefore, clearing the data 0 store at each location is rather meaningful. 
				if (wr_en = '1') then
				-- check if some data is occupying this location of cam
				-- if the location is empty, the readdata should be the 0s or random. CAM will be erased at that address
				-- for data 0 or data random, which is not harmful, because anyways there is no data in the CAM location
				-- the location should be all 0s in that case. So, not need to add a occupancy_flag to indicate the CAM
				-- location needs to be erase or not. Just erase it randomly is fine. 
				-- retrieve the data at the intended write address from erase ram
					erase_ram_addr	<= wr_addr;
					cam_wr_data 	<= erase_ram_dout; -- data is the last data stored in the cam
					-- turn cam into erase mode, with address of intended write address, 
					cam_wr_addr 	<= wr_addr; 
					cam_erase_en	<= '1';
					-- the above should clear the location of cam 
					-- indicate cam is busy  
					cam_wr_rd 		<= '0';
				else
					cam_erase_en	<= '0';
					cam_wr_rd		<= '1'; -- indicate cam is idle
				end if;
				cam_wr_en 		<= '0';
				erase_ram_we	<= '0';					
			when CAM_WRITE =>
				-- now we can write normally to cam
				cam_wr_en		<= '1';
				cam_erase_en	<= '0';
				cam_wr_data		<= wr_data;
				cam_wr_addr		<= wr_addr;
				-- remember to update the erase ram
				erase_ram_din	<= wr_data;
				erase_ram_addr	<= wr_addr;
				erase_ram_we	<= '1';		
				-- indicate the cam is busy  
				cam_wr_rd		<= '0';
			when CAM_INIT =>
				-- initialize the cam with init rom content
				cam_wr_en		<= '1';
				cam_erase_en	<= '0';
				cam_wr_data		<= init_rom_dout;
				cam_wr_addr		<= init_rom_addr;
				-- update the erase ram
				erase_ram_din	<= init_rom_dout;
				erase_ram_addr	<= init_rom_addr;
				erase_ram_we	<= '1';		
				-- indicate the cam is busy
				cam_wr_rd		<= '0';		
				if ((to_integer(unsigned(init_rom_addr))) < CAM_SIZE-1) then -- last addr is 127
					init_inproc		<= '1';
				else
					init_inproc		<= '0';
				end if;
			when others =>
			
			
		end case;
	end process;
	
	-- The user must be careful not to write new data to an occupied address, because unlike RAM the CAM
	-- will not erase the old data in that address. User must first clear that address first.
	-- So, the user must look up in the "erase ram" to find the data in the targeted address.
	-- Then, the user can use the data to know which bit to write at Port A. 
	-- /// Otherwise, user can also use ring-buffer shape CAM, such that the new data will only be store after
	-- the last address. Such address pointer must be update when write action is performed. But, this 
	-- idea is not generic ///
	e_cam_erase_ram : entity work.cam_erase_ram
		generic map(
			DATA_WIDTH => CAM_DATA_BITS,
			ADDR_WIDTH => CAM_ADDR_BITS)
		port map(
			clk		=> clk,
			addr	=> to_integer(unsigned(erase_ram_addr)),
			data	=> erase_ram_din,
			we		=> erase_ram_we,
			q		=> erase_ram_dout
		);
		
	u_cam_init_rom : component cam_init_rom
		generic map(
			DATA_WIDTH 	=> CAM_DATA_BITS,
			ADDR_WIDTH 	=> CAM_ADDR_BITS)
		port map(
			addr		=> init_rom_addr,
			q			=> init_rom_dout
		);
	
	e_cam_mem : entity work.cam_mem_a5
		generic map(
			CAM_SIZE 	=> CAM_SIZE,
			CAM_WIDTH 	=> CAM_WIDTH,
			RAM_TYPE 	=> RAM_TYPE_0)
		port map(
			i_clk			=> clk,
			i_rst			=> rst,
			i_erase_en		=> cam_erase_en,
			i_wr_en			=> cam_wr_en,
			i_wr_data		=> cam_wr_data,
			i_wr_addr		=> cam_wr_addr,
			i_cmp_din		=> cam_CMP_DIN,
			o_match_addr	=> cam_match_addr_raw
		);


end architecture rtl;