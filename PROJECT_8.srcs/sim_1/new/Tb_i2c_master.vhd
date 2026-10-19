----------------------------------------------------------------------------------
-- Jobsheet 8  : Tb_I2c_master.vhd
-- Fungsi      : Menguji i2c_master dengan model slave perilaku (alamat 0x48).
--   Tes 1 : TULIS  alamat register 0x00 ke slave  -> slave menyimpan di slv_reg
--   Tes 2 : BACA   1 byte dari slave (data 0xA5)  -> rdata harus 0xA5
--   Tes 3 : TULIS ke alamat salah (0x55)          -> ack_error harus '1'
-- Amati pada waveform: scl, sda, state internal (uut/state), ack_error, done.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tb_i2c_master is
end tb_i2c_master;

architecture sim of tb_i2c_master is
    constant SLAVE_ADDR : std_logic_vector(6 downto 0) := "1001000";  -- 0x48
    constant TX_DATA    : std_logic_vector(7 downto 0) := x"A5";      -- data yang dikirim slave saat dibaca

    signal clk        : std_logic := '0';
    signal rst        : std_logic := '1';
    signal start      : std_logic := '0';
    signal rw         : std_logic := '0';
    signal s_addr     : std_logic_vector(6 downto 0) := (others => '0');
    signal wdata      : std_logic_vector(7 downto 0) := (others => '0');
    signal rdata      : std_logic_vector(7 downto 0);
    signal busy, done, ack_error : std_logic;

    signal scl, sda   : std_logic;                       -- jalur bus I2C (resolved)
    signal slv_reg    : std_logic_vector(7 downto 0) := (others => '0');
    signal sim_done   : boolean := false;
begin
    -- Resistor pull-up pada bus
    scl <= 'H';
    sda <= 'H';

    uut : entity work.i2c_master
        generic map (CLK_DIV => 250)                     -- SCL = 100 kHz
        port map (clk => clk, rst => rst, start => start, rw => rw,
                  slave_addr => s_addr, wdata => wdata, rdata => rdata,
                  busy => busy, done => done, ack_error => ack_error,
                  scl => scl, sda => sda);

    -- Clock 100 MHz
    clk_proc : process
    begin
        while not sim_done loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
        wait;
    end process;

    ----------------------------------------------------------------------
    -- Model slave I2C sederhana (open-drain)
    ----------------------------------------------------------------------
    slave : process
        variable b : std_logic_vector(7 downto 0);
    begin
        sda <= 'Z';
        loop
            -- Tunggu kondisi START (SDA turun saat SCL tinggi)
            wait until falling_edge(sda) and to_x01(scl) = '1';

            -- Terima byte alamat + R/W
            for i in 7 downto 0 loop
                wait until rising_edge(scl);
                b(i) := to_x01(sda);
            end loop;
            wait until falling_edge(scl);

            if b(7 downto 1) = SLAVE_ADDR then
                sda <= '0';                              -- ACK alamat
                wait until rising_edge(scl);
                wait until falling_edge(scl);

                if b(0) = '0' then
                    -- Master TULIS: terima 1 byte
                    sda <= 'Z';
                    for i in 7 downto 0 loop
                        wait until rising_edge(scl);
                        b(i) := to_x01(sda);
                    end loop;
                    slv_reg <= b;
                    wait until falling_edge(scl);
                    sda <= '0';                          -- ACK data
                    wait until rising_edge(scl);
                    wait until falling_edge(scl);
                    sda <= 'Z';
                else
                    -- Master BACA: kirim TX_DATA bit demi bit
                    for i in 7 downto 0 loop
                        if TX_DATA(i) = '0' then
                            sda <= '0';
                        else
                            sda <= 'Z';
                        end if;
                        wait until falling_edge(scl);
                    end loop;
                    sda <= 'Z';                          -- lepas SDA untuk NACK master
                end if;
            end if;
            -- (alamat salah: slave tidak memberi ACK -> SDA tetap tinggi = NACK)

            -- Tunggu kondisi STOP (SDA naik saat SCL tinggi)
            wait until rising_edge(sda) and to_x01(scl) = '1';
        end loop;
    end process;

    ----------------------------------------------------------------------
    -- Stimulus
    ----------------------------------------------------------------------
    stim : process
    begin
        rst <= '1';
        wait for 200 ns;
        rst <= '0';
        wait for 200 ns;

        ------------------------------------------------------------------
        -- Tes 1: TULIS alamat register 0x00
        ------------------------------------------------------------------
        s_addr <= SLAVE_ADDR;
        rw     <= '0';
        wdata  <= x"00";
        wait until rising_edge(clk);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        wait until done = '1';
        wait for 1 us;
        assert ack_error = '0' report "Tes 1: ack_error seharusnya '0'" severity error;
        assert slv_reg = x"00" report "Tes 1: data yang diterima slave salah" severity error;
        report "Tes 1 (tulis register) selesai" severity note;
        wait for 20 us;

        ------------------------------------------------------------------
        -- Tes 2: BACA 1 byte
        ------------------------------------------------------------------
        rw <= '1';
        wait until rising_edge(clk);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        wait until done = '1';
        wait for 1 us;
        assert ack_error = '0' report "Tes 2: ack_error seharusnya '0'" severity error;
        assert rdata = TX_DATA report "Tes 2: data baca tidak sama dengan 0xA5" severity error;
        report "Tes 2 (baca 1 byte) selesai" severity note;
        wait for 20 us;

        ------------------------------------------------------------------
        -- Tes 3: alamat slave salah -> harus NACK
        ------------------------------------------------------------------
        s_addr <= "1010101";                             -- 0x55
        rw     <= '0';
        wdata  <= x"12";
        wait until rising_edge(clk);
        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        wait until done = '1';
        wait for 1 us;
        assert ack_error = '1' report "Tes 3: ack_error seharusnya '1' (NACK)" severity error;
        report "Tes 3 (alamat salah -> NACK) selesai" severity note;
        wait for 20 us;

        report "SEMUA TES I2C SELESAI. Periksa waveform & pesan assert." severity note;
        sim_done <= true;
        wait;
    end process;
end sim;