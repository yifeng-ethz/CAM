-- File name: addr_encoding_logic.vhd 
-- Author: Yifeng Wang
-- =======================================
-- Revision: 1.0 (file created)
--		Date: September 20, 2023
-- ================ synthsizer configuration =================== 		
-- altera vhdl_input_version vhdl_2008
-- ============================================================= 
-- Description: encoding the output of CAM. turning the found array (one-hot) into match-address (binary)  

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity addr_enc_logic is
	generic(
		CAM_SIZE			: natural := 128;
		CAM_ADDR_BITS		: natural := 7
		);
	port(
		i_cam_address_onehot	: in std_logic_vector(CAM_SIZE-1 downto 0);
		o_cam_address_binary	: out std_logic_vector(CAM_ADDR_BITS-1 downto 0);
		o_cam_match_flag		: out std_logic;
		o_cam_match_count		: out std_logic_vector(CAM_ADDR_BITS-1 downto 0)
		);
	
end addr_enc_logic;

architecture rtl of addr_enc_logic is 
	
	signal cam_address_onehot	: std_logic_vector(CAM_SIZE-1 downto 0);
	signal cam_address_binary, cam_match_count	: std_logic_vector(CAM_ADDR_BITS-1 downto 0);
	signal cam_match_flag		: std_logic;

	begin

	cam_address_onehot		<= i_cam_address_onehot;
	o_cam_address_binary	<= cam_address_binary;
	o_cam_match_flag		<= cam_match_flag;
	o_cam_match_count		<= cam_match_count;
	
	process(cam_address_onehot)
		variable code: std_logic_vector(CAM_ADDR_BITS-1 downto 0); -- find leading '1' position in binary
		variable count: integer range 0 to CAM_SIZE; 
	begin
		code := (others => '0');
		count := 0;
		for i in 0 to CAM_SIZE-1 loop
			if (cam_address_onehot(i)='1') then 
				code := code OR std_logic_vector(to_unsigned(i, code'LENGTH));
				count := count + 1;
			end if;
		end loop;
		if (count>0) then
			cam_match_flag <= '1';
		else
			cam_match_flag <= '0';
		end if;
		cam_match_count <= std_logic_vector(to_unsigned(count, cam_match_count'LENGTH)) ;
		cam_address_binary <= code;
	end process;



end architecture rtl;