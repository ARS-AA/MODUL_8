----------------------------------------------------------------------------------
-- Jobsheet 8  : bram_async_read.vhd  (eksperimen Tugas Praktikum 2)
-- Fungsi      : Memori 256x8 dengan pembacaan KOMBINASIONAL (tanpa dout_reg).
-- Hasil yang diharapkan: Vivado TIDAK dapat memakai BRAM (BRAM hanya mendukung
--               baca sinkron), sehingga memori dipetakan ke Distributed RAM
--               (RAM LUT) - lihat laporan Utilization: LUT as Distributed RAM.
-- Catatan     : JANGAN beri atribut ram_style = "block" di sini, agar perilaku
--               asli sintesis terlihat.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity bram_async_read is
    Port ( clk  : in  STD_LOGIC;
           we   : in  STD_LOGIC;
           addr : in  STD_LOGIC_VECTOR (7 downto 0);
           din  : in  STD_LOGIC_VECTOR (7 downto 0);
           dout : out STD_LOGIC_VECTOR (7 downto 0) );
end bram_async_read;

architecture Behavioral of bram_async_read is
    type ram_type is array (0 to 255) of STD_LOGIC_VECTOR(7 downto 0);
    signal ram : ram_type := (others => (others => '0'));
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if we = '1' then
                ram(to_integer(unsigned(addr))) <= din;
            end if;
        end if;
    end process;

    -- Pembacaan kombinasional langsung dari array (tanpa register)
    dout <= ram(to_integer(unsigned(addr)));
end Behavioral;