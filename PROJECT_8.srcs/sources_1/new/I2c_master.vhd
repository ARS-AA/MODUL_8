----------------------------------------------------------------------------------
-- Jobsheet 8  : I2C_master.vhd
-- Fungsi      : Kerangka FSM I2C master (standard mode 100 kHz), 1 byte per transaksi.
--
-- State       : S_IDLE, S_START, S_ADDR, S_ADDR_ACK, S_DATA, S_DATA_ACK, S_STOP
--
-- Transaksi   : START -> [7-bit alamat + R/W] -> ACK -> [1 byte data] -> ACK/NACK -> STOP
--               rw = '0' : TULIS  (master mengirim wdata, slave memberi ACK)
--               rw = '1' : BACA   (slave mengirim data, master membalas NACK karena hanya 1 byte)
--
-- Contoh "tulis alamat register + baca 1 byte" = DUA transaksi berurutan:
--               (1) rw='0', wdata = alamat register (pointer)
--               (2) rw='1', hasil di rdata
--
-- Pewaktuan   : Setiap bit dibagi 4 fase (quarter period). SCL = f_clk / (4 * CLK_DIV)
--               CLK_DIV = 250 dan clk = 100 MHz  ->  SCL = 100 kHz
--
-- Fase per bit (SCL rendah di awal):
--               ph0 : atur SDA          ph1 : SCL naik
--               ph2 : sampling SDA      ph3 : SCL turun (SCL tinggi selama ph1..ph3 = 50% duty)
--
-- Batasan     : Tidak mendukung clock stretching, repeated start, dan multi-byte.
-- Open-drain  : SDA/SCL hanya di-drive '0' atau dilepas ('Z'); pull-up dari luar.
----------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity i2c_master is
    Generic ( CLK_DIV : integer := 250 );   -- jumlah clock per 1/4 periode SCL
    Port ( clk        : in    STD_LOGIC;
           rst        : in    STD_LOGIC;
           start      : in    STD_LOGIC;                        -- pulsa 1 clock untuk memulai
           rw         : in    STD_LOGIC;                        -- '0' = tulis, '1' = baca
           slave_addr : in    STD_LOGIC_VECTOR (6 downto 0);
           wdata      : in    STD_LOGIC_VECTOR (7 downto 0);
           rdata      : out   STD_LOGIC_VECTOR (7 downto 0);
           busy       : out   STD_LOGIC;
           done       : out   STD_LOGIC;                        -- pulsa 1 clock saat transaksi selesai
           ack_error  : out   STD_LOGIC;                        -- '1' bila slave mengirim NACK
           scl        : out   STD_LOGIC;                        -- open-drain
           sda        : inout STD_LOGIC );                      -- open-drain
end i2c_master;

architecture Behavioral of i2c_master is
    type i2c_state is (S_IDLE, S_START, S_ADDR, S_ADDR_ACK,
                       S_DATA, S_DATA_ACK, S_STOP);
    signal state : i2c_state := S_IDLE;

    signal cnt       : integer range 0 to CLK_DIV-1 := 0;   -- pembagi clock
    signal ph        : integer range 0 to 3 := 0;           -- fase 1/4 periode
    signal bitcnt    : integer range 0 to 7 := 7;
    signal shreg     : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal rx        : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal rw_l      : STD_LOGIC := '0';
    signal wdata_l   : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');

    signal scl_low   : STD_LOGIC := '0';    -- '1' = tarik SCL ke 0
    signal sda_low   : STD_LOGIC := '0';    -- '1' = tarik SDA ke 0
    signal sda_in    : STD_LOGIC;
    signal busy_i    : STD_LOGIC := '0';
    signal ack_err_i : STD_LOGIC := '0';
begin
    -- Keluaran open-drain: tarik ke '0' atau lepas ('Z')
    scl <= '0' when scl_low = '1' else 'Z';
    sda <= '0' when sda_low = '1' else 'Z';

    -- Pembacaan SDA (resistor pull-up membuat 'Z' terbaca '1'; 'H' juga dianggap '1')
    sda_in <= '0' when sda = '0' else '1';

    busy      <= busy_i;
    ack_error <= ack_err_i;
    rdata     <= rx;

    process(clk)
        variable tick : boolean;
    begin
        if rising_edge(clk) then
            done <= '0';
            tick := false;

            if rst = '1' then
                state     <= S_IDLE;
                cnt       <= 0;
                ph        <= 0;
                scl_low   <= '0';
                sda_low   <= '0';
                busy_i    <= '0';
                ack_err_i <= '0';
            else
                -- Pembangkit tick tiap 1/4 periode SCL
                if state = S_IDLE then
                    cnt <= 0;
                elsif cnt = CLK_DIV - 1 then
                    cnt  <= 0;
                    tick := true;
                else
                    cnt <= cnt + 1;
                end if;

                case state is

                    ------------------------------------------------------------
                    when S_IDLE =>
                        scl_low <= '0';          -- bus bebas: SCL & SDA tinggi
                        sda_low <= '0';
                        if start = '1' then
                            shreg     <= slave_addr & rw;
                            rw_l      <= rw;
                            wdata_l   <= wdata;
                            ack_err_i <= '0';
                            busy_i    <= '1';
                            ph        <= 0;
                            bitcnt    <= 7;
                            state     <= S_START;
                        end if;

                    ------------------------------------------------------------
                    -- START: SDA turun saat SCL tinggi, lalu SCL turun
                    when S_START =>
                        if tick then
                            case ph is
                                when 1 => sda_low <= '1';            -- kondisi START
                                when 3 => scl_low <= '1';            -- SCL turun
                                          bitcnt  <= 7;
                                          state   <= S_ADDR;
                                when others => null;
                            end case;
                            ph <= (ph + 1) mod 4;
                        end if;

                    ------------------------------------------------------------
                    -- Kirim byte alamat (S_ADDR) atau kirim/terima byte data (S_DATA)
                    when S_ADDR | S_DATA =>
                        if tick then
                            case ph is
                                when 0 =>
                                    if state = S_ADDR or rw_l = '0' then
                                        sda_low <= not shreg(7);     -- kirim bit (MSB dulu)
                                    else
                                        sda_low <= '0';              -- baca: lepas SDA
                                    end if;
                                when 1 =>
                                    scl_low <= '0';                  -- SCL naik
                                when 2 =>
                                    if state = S_DATA and rw_l = '1' then
                                        rx <= rx(6 downto 0) & sda_in;  -- sampling tengah SCL tinggi
                                    end if;
                                when 3 =>
                                    scl_low <= '1';                  -- SCL turun
                                    shreg   <= shreg(6 downto 0) & '0';
                                    if bitcnt = 0 then
                                        bitcnt <= 7;
                                        if state = S_ADDR then
                                            state <= S_ADDR_ACK;
                                        else
                                            state <= S_DATA_ACK;
                                        end if;
                                    else
                                        bitcnt <= bitcnt - 1;
                                    end if;
                                when others => null;
                            end case;
                            ph <= (ph + 1) mod 4;
                        end if;

                    ------------------------------------------------------------
                    -- ACK setelah alamat: master melepas SDA, slave menarik SDA ke 0 jika ACK
                    when S_ADDR_ACK =>
                        if tick then
                            case ph is
                                when 0 => sda_low <= '0';            -- lepas SDA (SDA = 'Z')
                                when 1 => scl_low <= '0';            -- SCL naik
                                when 2 => if sda_in = '1' then       -- '1' = NACK
                                              ack_err_i <= '1';
                                          end if;
                                when 3 => scl_low <= '1';
                                          if ack_err_i = '1' then
                                              state <= S_STOP;       -- alamat tidak dikenali
                                          else
                                              shreg  <= wdata_l;
                                              bitcnt <= 7;
                                              state  <= S_DATA;
                                          end if;
                                when others => null;
                            end case;
                            ph <= (ph + 1) mod 4;
                        end if;

                    ------------------------------------------------------------
                    -- ACK/NACK setelah data
                    --   Tulis : slave memberi ACK (diperiksa master)
                    --   Baca  : master membalas NACK (SDA dilepas = '1') karena hanya 1 byte
                    when S_DATA_ACK =>
                        if tick then
                            case ph is
                                when 0 => sda_low <= '0';            -- lepas SDA
                                when 1 => scl_low <= '0';
                                when 2 => if rw_l = '0' and sda_in = '1' then
                                              ack_err_i <= '1';
                                          end if;
                                when 3 => scl_low <= '1';
                                          state   <= S_STOP;
                                when others => null;
                            end case;
                            ph <= (ph + 1) mod 4;
                        end if;

                    ------------------------------------------------------------
                    -- STOP: SDA = 0 -> SCL naik -> SDA naik saat SCL tinggi
                    when S_STOP =>
                        if tick then
                            case ph is
                                when 0 => sda_low <= '1';            -- SDA ke 0 (SCL masih rendah)
                                when 1 => scl_low <= '0';            -- SCL naik
                                when 3 => sda_low <= '0';            -- SDA naik saat SCL tinggi = STOP
                                          busy_i  <= '0';
                                          done    <= '1';
                                          state   <= S_IDLE;
                                when others => null;
                            end case;
                            ph <= (ph + 1) mod 4;
                        end if;

                end case;
            end if;
        end if;
    end process;
end Behavioral;