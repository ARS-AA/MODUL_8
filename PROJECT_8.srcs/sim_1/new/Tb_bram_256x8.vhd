----------------------------------------------------------------------------------
-- Jobsheet 8  : tb_bram_256x8.vhd
-- Fungsi      : Menulis 16 data ke alamat berbeda, membaca kembali, lalu
--               memverifikasi dengan assert. Latensi baca BRAM = 1 clock.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_bram_256x8 is
end tb_bram_256x8;

architecture sim of tb_bram_256x8 is
    signal clk      : std_logic := '0';
    signal we       : std_logic := '0';
    signal addr     : std_logic_vector(7 downto 0) := (others => '0');
    signal din      : std_logic_vector(7 downto 0) := (others => '0');
    signal dout     : std_logic_vector(7 downto 0);
    signal sim_done : boolean := false;
begin
    uut : entity work.bram_256x8
        port map (clk => clk, we => we, addr => addr, din => din, dout => dout);

    -- Pembangkit clock 100 MHz
    clk_proc : process
    begin
        while not sim_done loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
        wait;
    end process;

    stim : process
        variable expected : std_logic_vector(7 downto 0);
        variable errors   : integer := 0;
    begin
        wait for 20 ns;

        -- 1) TULIS: 16 data ke alamat 0, 16, 32, ... 240
        for i in 0 to 15 loop
            wait until falling_edge(clk);
            we   <= '1';
            addr <= std_logic_vector(to_unsigned(i * 16, 8));
            din  <= std_logic_vector(to_unsigned((i * 37 + 5) mod 256, 8));
        end loop;

        wait until falling_edge(clk);
        we <= '0';

        -- 2) BACA + VERIFIKASI
        for i in 0 to 15 loop
            addr <= std_logic_vector(to_unsigned(i * 16, 8));
            wait until falling_edge(clk);          -- tunggu 1 siklus (registered output)
            expected := std_logic_vector(to_unsigned((i * 37 + 5) mod 256, 8));
            if dout /= expected then
                errors := errors + 1;
            end if;
            assert dout = expected
                report "GAGAL di alamat " & integer'image(i * 16) &
                       " : data baca tidak sama dengan data tulis"
                severity error;
        end loop;

        -- 3) Alamat yang tidak pernah ditulis harus bernilai 0 (nilai inisialisasi)
        addr <= std_logic_vector(to_unsigned(5, 8));
        wait until falling_edge(clk);
        assert dout = x"00"
            report "Alamat 5 (tidak ditulis) seharusnya 0x00" severity error;

        if errors = 0 then
            report "TEST BRAM LULUS: semua data cocok." severity note;
        else
            report "TEST BRAM GAGAL: " & integer'image(errors) & " data tidak cocok." severity error;
        end if;

        sim_done <= true;
        wait;
    end process;
end sim;