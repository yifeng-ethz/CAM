-- File name: cam_top.vhd 
-- Author: Yifeng Wang
-- =======================================
-- Revision: 1.0 (file created)
--		Date: Sept 20, 2023
-- =========
-- Description:	Top level file of CAM, including control-logic and cam_rtl 
--	
-- ================ synthsizer configuration =================== 		
-- altera vhdl_input_version vhdl_2008
-- ============================================================= 
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use IEEE.math_real.log2;
use IEEE.math_real.ceil;

entity cam_top is
	generic(
		CAM_SIZE			: natural := 128; 
		CAM_WIDTH			: natural := 16;
		MATCH_MODE			: string := "Multiple-Match"; -- "Single-Match"
		ERASE_SPEED			: string := "fast"; -- "slow", determines the RAM_TYPE and erasing algorithm 
		OCCUPANCY_CHECK		: boolean := True; -- check if match before write, always true for Single-Match mode
		ENCODE_ADDRESS_OUT	: boolean := True);
	port(
		i_clk					: in std_logic;
		i_rst					: in std_logic;
		i_wr_en					: in std_logic;
		i_init_en				: in std_logic;
		o_wr_rd					: out std_logic;
		i_wr_data				: in std_logic_vector(79 downto 0);
		i_wr_addr				: in std_logic_vector(15 downto 0);
		i_cmp_din				: in std_logic_vector(79 downto 0);
		o_match_flag			: out std_logic;
		o_match_count			: out std_logic_vector(15 downto 0);
		o_match_addr			: out std_logic_vector(15 downto 0)
	);

end entity cam_top;


architecture rtl of cam_top is 

	constant CAM_DATA_BITS			: natural := integer(ceil(real(CAM_WIDTH)/8.0)*8.0); -- 16, round up to 8's multiple
	constant CAM_ADDR_BITS			: natural := integer(ceil(log2(real(CAM_SIZE)))); -- 7, for 128, round up

	signal clk,rst					: std_logic := '1';
	signal wr_en, init_en			: std_logic := '0';
	signal wr_data 					: std_logic_vector(CAM_DATA_BITS-1 downto 0);
	signal wr_addr					: std_logic_vector(CAM_ADDR_BITS-1 downto 0);
	signal cmp_din					: std_logic_vector(CAM_DATA_BITS-1 downto 0);
	
	signal match_count			: std_logic_vector(CAM_ADDR_BITS-1 downto 0);
	signal match_addr			: std_logic_vector(CAM_ADDR_BITS-1 downto 0);
	signal match_flag			: std_logic := '0';
	signal wr_rd				: std_logic := '0';

begin

	clk <= i_clk;
	rst <= i_rst;
	
	-- trimming IO width (not necessary if not in the top level)
	wr_en 		<= i_wr_en;
	init_en		<= i_init_en;
	wr_data 	<= i_wr_data(CAM_DATA_BITS-1 downto 0); -- 16
	wr_addr 	<= i_wr_addr(CAM_ADDR_BITS-1 downto 0); -- 7
	cmp_din 	<= i_cmp_din(CAM_DATA_BITS-1 downto 0); -- 16
	o_match_flag 	<= match_flag; -- 1
	o_match_count(CAM_ADDR_BITS-1 downto 0) 	<= match_count; -- 7
	o_match_addr(CAM_ADDR_BITS-1 downto 0)		<= match_addr;
	o_wr_rd <= wr_rd;
	
	e_cam_rtl : entity work.cam_rtl
	generic map(
		CAM_SIZE			=> CAM_SIZE,
		CAM_WIDTH			=> CAM_DATA_BITS,
		ADDR_WIDTH			=> CAM_ADDR_BITS,
		OCCUPANCY_CHECK		=> OCCUPANCY_CHECK,
		ENCODE_ADDRESS_OUT	=> ENCODE_ADDRESS_OUT)
	port map(
		i_clk					=> clk,
		i_rst					=> rst,
		i_wr_en					=> wr_en,
		i_init_en				=> init_en,
		i_wr_data				=> wr_data,
		i_wr_addr				=> wr_addr,
		i_cmp_din				=> cmp_din,
		o_match_flag			=> match_flag,
		o_cam_match_count		=> match_count,
		o_cam_match_addr		=> match_addr,
		o_cam_wr_rd				=> wr_rd);
		
	
	
	




end architecture rtl;