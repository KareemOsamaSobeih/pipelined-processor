LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;
use work.arrays_pkg.ALL;

ENTITY Processor IS
    PORT(   clk         : IN std_logic;
            int         : IN std_logic;
            rst         : IN std_logic;
            in_port     : IN std_logic_vector (31 DOWNTO 0);
            out_port    : OUT std_logic_vector (31 DOWNTO 0)
        );
END ENTITY Processor;



ARCHITECTURE arch OF Processor IS

    SIGNAL reg_file_enables : std_logic_vector (7 DOWNTO 0);
    SIGNAL reg_file_D       : reg_array;
    SIGNAL reg_file_Q       : reg_array;
    
    SIGNAL SP_enable    : std_logic;
    SIGNAL SP_D         : std_logic_vector (31 DOWNTO 0);
    SIGNAL SP_Q         : std_logic_vector (31 DOWNTO 0);
    
    SIGNAL FR_enable    : std_logic;
    SIGNAL FR_D         : std_logic_vector (3 DOWNTO 0);    -- Z : <0> | N : <1> | C : <2>
    SIGNAL FR_Q         : std_logic_vector (3 DOWNTO 0);


    SIGNAL jz_sig           : std_logic;
    SIGNAL jz_correction    : std_logic;
    SIGNAL jz_pc            : std_logic_vector (31 DOWNTO 0);
    

    SIGNAL IF_ID_D    : std_logic_vector (48 DOWNTO 0);
    SIGNAL IF_ID_Q    : std_logic_vector (48 DOWNTO 0);
    
    SIGNAL ID_EX_D    : std_logic_vector (136 DOWNTO 0);
    SIGNAL ID_EX_Q    : std_logic_vector (136 DOWNTO 0);
    
    SIGNAL EX_MEM_D   : std_logic_vector (111 DOWNTO 0);
    SIGNAL EX_MEM_Q   : std_logic_vector (111 DOWNTO 0);
    
    SIGNAL MEM_WB_D   : std_logic_vector (77 DOWNTO 0);
    SIGNAL MEM_WB_Q   : std_logic_vector (77 DOWNTO 0);

    
    -- Normal operation, Finishing instructions in the pipeline, Pushing PC, Saving FR, Updating PC, Reset
    TYPE state_machine IS (i0, i1, i2, i3, i4, r);
    SIGNAL state : state_machine;
    -- VARIABLE cnt : INTEGER RANGE 0 TO 5;

    SIGNAL IF_ID_INT    : std_logic_vector (48 DOWNTO 0);
    SIGNAL IF_ID_RST    : std_logic_vector (48 DOWNTO 0);

    SIGNAL ID_OUTPUT    : std_logic_vector (136 DOWNTO 0);

    SIGNAL ID_INPUT     : std_logic_vector (48 DOWNTO 0);
    
BEGIN

    GEN_REG : FOR i IN 0 TO 7 GENERATE
        REGX : ENTITY work.reg_fall PORT MAP (reg_file_enables (i), clk, rst, reg_file_D (i), reg_file_Q (i));
    END GENERATE GEN_REG;
    GEN_SP : ENTITY work.reg_fall PORT MAP (SP_enable, clk, '0', SP_D, SP_Q);
    GEN_FR : ENTITY work.reg_fall GENERIC MAP (4) 
                                PORT MAP (FR_enable, clk, rst, FR_D, FR_Q);

    IF_stage : ENTITY work.Fetch PORT MAP (
                                            clk => clk,
                                            rst => rst,
                                            reg_arr => reg_file_Q,
                                            mem_signal => MEM_WB_Q (74),
                                            mem_val => MEM_WB_Q (31 DOWNTO 0),
                                            jz_signal => jz_sig,
                                            force_pc => jz_correction,
                                            correct_pc => jz_pc,
                                            zero_flag => FR_Q (0),
                                            jz_address => ID_EX_Q (23 DOWNTO 16),
                                            skip_instruc => NOT ID_EX_Q (121),
                                            out_instruc => IF_ID_D (15 DOWNTO 0),
                                            out_address => IF_ID_D (47 DOWNTO 16),
                                            branch_status => IF_ID_D (48)
                                        );

    GEN_IF_ID : ENTITY work.reg_rise  GENERIC MAP (49)
                                    PORT MAP ('1', clk, '0', IF_ID_D, IF_ID_Q);
                                    
    ID_INPUT    <=      IF_ID_RST                                   WHEN state = r
                ELSE    IF_ID_Q (48 DOWNTO 16) & "1110000000000000" WHEN NOT ((state = i2) OR (state = i3) OR (state = i4)) AND (ID_EX_Q (121) = '0')
                ELSE    IF_ID_Q                                     WHEN NOT ((state = i2) OR (state = i3) OR (state = i4))
                ELSE    IF_ID_INT;

    -- OR jz_correction = '1'
    

    ID_stage : ENTITY work.Decode PORT MAP (   
                                            clk => clk,
                                            reg_arr => reg_file_Q,
                                            spReg => SP_Q,
                                            inPort => in_port,
                                            instruction => ID_INPUT (15 DOWNTO 0),
                                            zflag => FR_Q (0),
                                            decision => ID_INPUT (48),
                                            incrementedPcIn => ID_INPUT (47 DOWNTO 16),
                                            curinstruction => ID_OUTPUT (3 DOWNTO 0),
                                            incrementedPcOut => ID_OUTPUT (47 DOWNTO 16),
                                            src1 => ID_OUTPUT (79 DOWNTO 48),
                                            src2 => ID_OUTPUT (111 DOWNTO 80),
                                            Rsrc1 => ID_OUTPUT (114 DOWNTO 112),
                                            Rsrc2 => ID_OUTPUT (117 DOWNTO 115),
                                            Rsrc1E => ID_OUTPUT (118),
                                            Rsrc2E => ID_OUTPUT (119),
                                            aluSrc2 => ID_OUTPUT (121 DOWNTO 120),
                                            Rdst => ID_OUTPUT (124 DOWNTO 122),
                                            aluCode => ID_OUTPUT (128 DOWNTO 125),
                                            memRead => ID_OUTPUT (129),
                                            memWrite => ID_OUTPUT (130),
                                            operation => ID_OUTPUT (132 DOWNTO 131),
                                            memPCWB => ID_OUTPUT (133),
                                            registerWB => ID_OUTPUT (134),
                                            isJz => jz_sig,
                                            chdecision => jz_correction,
                                            rightPc => jz_pc
                                            -- TODO: ALUop and MEMop
                                        );
    ID_OUTPUT (15 DOWNTO 4) <= (OTHERS => '0');
    -- TODO: ALUop and MEMop
    ID_OUTPUT (136 DOWNTO 135)  <= "00";

    ID_EX_D <=      ID_OUTPUT;   -- TODO: Rst data forwarding unit (bits 136-135, 119-118)

    GEN_ID_EX : ENTITY work.reg_rise  GENERIC MAP (137)
                                    PORT MAP ('1', clk, '0', ID_EX_D, ID_EX_Q);

    EX_stage : ENTITY work.execute_stage PORT MAP (
                                                    src1 => ID_EX_Q (79 DOWNTO 48),
                                                    src2 => ID_EX_Q (111 DOWNTO 80),
                                                    code => ID_EX_Q (128 DOWNTO 125),
                                                    EA1 => ID_EX_Q (15 DOWNTO 0),
                                                    secWord => IF_ID_Q (15 DOWNTO 0),
                                                    src2Type => ID_EX_Q (121 DOWNTO 120),
                                                    opType => ID_EX_Q (132 DOWNTO 131),
                                                    dst1 => EX_MEM_D (31 DOWNTO 0),
                                                    dst2 => EX_MEM_D (63 DOWNTO 32),
                                                    FR => FR_D,
                                                    FRen => FR_enable
                                                );
    EX_MEM_D (95 DOWNTO 64) <= ID_EX_Q (47 DOWNTO 16);
    EX_MEM_D (98 DOWNTO 96) <= ID_EX_Q (124 DOWNTO 122);
    EX_MEM_D (101 DOWNTO 99) <= ID_EX_Q (114 DOWNTO 112);
    EX_MEM_D (102) <= ID_EX_Q (118); -- TODO: Rst data forwarding unit
    EX_MEM_D (103) <= ID_EX_Q (119); -- ``
    EX_MEM_D (104) <= ID_EX_Q (129);
    EX_MEM_D (105) <= ID_EX_Q (130);
    EX_MEM_D (107  DOWNTO 106)  <=      ID_EX_Q (132 DOWNTO 131) WHEN rst = '0'
                                ELSE    "00";
    EX_MEM_D (108)  <=      ID_EX_Q (133) WHEN rst = '0'
                    ELSE    '0';
    EX_MEM_D (109)  <=      ID_EX_Q (134) WHEN rst = '0'
                    ELSE    '0';
    EX_MEM_D (110) <= ID_EX_Q (135);
    EX_MEM_D (111) <= ID_EX_Q (136);

    GEN_EX_MEM : ENTITY work.reg_rise GENERIC MAP (112)
                                    PORT MAP ('1', clk, '0', EX_MEM_D, EX_MEM_Q);

    MEM_stage :ENTITY  work.memory_stage PORT MAP (    
                                                    clk => clk,
                                                    memRead => EX_MEM_Q (104),
                                                    memWrite => EX_MEM_Q (105),
                                                    opType => EX_MEM_Q (107 DOWNTO 106),
                                                    oldSP => SP_Q,
                                                    datain => EX_MEM_Q (31 DOWNTO 0),
                                                    address => EX_MEM_Q (63 DOWNTO 32),
                                                    dataout => MEM_WB_D (31 DOWNTO 0)
                                                );
    MEM_WB_D (63 DOWNTO 32) <= EX_MEM_Q (63 DOWNTO 32);
    MEM_WB_D (66 DOWNTO 64) <= EX_MEM_Q (98 DOWNTO 96);
    MEM_WB_D (69 DOWNTO 67) <= EX_MEM_Q (101 DOWNTO 99);
    MEM_WB_D (70) <= EX_MEM_Q (102);    -- TODO: Rst data forwarding unit
    MEM_WB_D (71) <= EX_MEM_Q (103);    -- ``
    MEM_WB_D (73 DOWNTO 72) <=      EX_MEM_Q (107 DOWNTO 106) WHEN rst = '0'
                            ELSE    "00";
    MEM_WB_D (74)   <=      EX_MEM_Q (108) WHEN rst = '0'
                    ELSE    '0';
    MEM_WB_D (75)   <=      EX_MEM_Q (109) WHEN rst = '0'
                    ELSE    '0';
    MEM_WB_D (76) <= EX_MEM_Q (110);
    MEM_WB_D (77) <= EX_MEM_Q (111);

    GEN_MEM_WB : ENTITY work.reg_rise GENERIC MAP (78)
                                    PORT MAP ('1', clk, rst, MEM_WB_D, MEM_WB_Q);

    -- Write Back Stage
    -- BEGIN
    SP_D <= MEM_WB_Q(63 DOWNTO 32) WHEN rst = '0'
        ELSE std_logic_vector(to_unsigned(2046, SP_D'length));
    SP_enable <= '1' WHEN MEM_WB_Q(73 DOWNTO 72) = "10" OR rst = '1'
                ELSE '0';

    out_port    <=      MEM_WB_Q(31 DOWNTO 0)    WHEN    MEM_WB_Q(73 DOWNTO 72) = "11"
                ELSE    (OTHERS => 'Z');

    PROCESS (MEM_WB_Q)
    BEGIN
        FOR i IN 0 TO 7 LOOP
            reg_file_enables (i) <= '1' WHEN (((i = (to_integer(unsigned(MEM_WB_Q(66 DOWNTO 64))))) AND (MEM_WB_Q(75) = '1')) 
                                            OR ((i = (to_integer(unsigned(MEM_WB_Q(69 DOWNTO 67))))) AND (MEM_WB_Q(73 DOWNTO 72) = "01")))
                                            
                                ELSE '0';
            reg_file_D (i) <= MEM_WB_Q(31 DOWNTO 0) WHEN (i = (to_integer(unsigned(MEM_WB_Q(66 DOWNTO 64)))))
                            ELSE MEM_WB_Q(63 DOWNTO 32) WHEN (i = (to_integer(unsigned(MEM_WB_Q(69 DOWNTO 67)))))
                            ELSE (OTHERS => 'Z');
        END LOOP;
    END PROCESS;
    -- END

    PROCESS (rst, int, clk)
    BEGIN
            IF rst = '1' THEN
                state <= r;
            ELSIF (state = r) THEN
                state <= i0;
            ELSIF state = i0 THEN
                IF int = '1' THEN
                    state <= i1;
                    -- cnt <= 5;
                END IF;
            ELSIF (state = i1) THEN
                IF rising_edge(clk) THEN
                    state <= i2;
                END IF;
            ELSIF rising_edge(clk) THEN
                CASE state IS
                    WHEN i2 =>
                        state <= i3;
                    WHEN i3 =>
                        state <= i4;
                    WHEN i4 =>
                        state <= i0;
                    WHEN OTHERS =>
                        NULL;
                END CASE;
            END IF;
    END PROCESS;

    PROCESS (state)
    BEGIN
        CASE state IS
            WHEN i2 =>
                IF_ID_INT (15 DOWNTO 0) <= "1100001000000000";
                IF_ID_INT (47 DOWNTO 16) <= ID_EX_Q (47 DOWNTO 16);
                IF_ID_INT (48) <= '0';
            WHEN i3 =>
                IF_ID_INT (15 DOWNTO 0) <= "1100001000000000";
                IF_ID_INT (47 DOWNTO 20) <= (OTHERS => '0');
                IF_ID_INT (19 DOWNTO 16) <= FR_Q (3 DOWNTO 0);
                IF_ID_INT (48) <= '0';
            WHEN i4 =>
                IF_ID_INT (15 DOWNTO 0) <= "1111000000000000";
                IF_ID_INT (47 DOWNTO 16) <= (47 DOWNTO 18 => '0', 17 DOWNTO 16 => "10");
                IF_ID_INT (48) <= '0';
            WHEN r =>
                IF_ID_RST (15 DOWNTO 0) <= "1111000000000000";
                IF_ID_RST (47 DOWNTO 16) <= (47 DOWNTO 18 => '0', 17 DOWNTO 16 => "00");
                IF_ID_RST (48) <= '0';
            WHEN OTHERS =>
                IF_ID_INT (48 DOWNTO 0) <= (OTHERS => '0');
        END CASE;
    END PROCESS;

END arch;


