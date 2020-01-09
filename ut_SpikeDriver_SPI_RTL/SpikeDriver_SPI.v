/* ----------------------------------------------------------------------------
MODULO "Driver Codificador de Spike Train" == SpikeDriver_SPI ==
autor:   João Ranhel
versão:  1.1           data: 2019_05_01   (SPI com 24 bits de comando)
--
Este módulo recebe NÚMEROS por meio de porta serial, e converte em SPIKES.
o circuito gera spikes para até 256 neurônios pulsantes (nrds) com código:
(a)"rate coding": taxa de disparo proporcional ao valor enviado (0=silente)
(b)"phase coding": tempo de retardo com relação a 1 nrd base dentre 16 grupos
(c)"popularion coding": disparo ± em torno de um limiar dentre 16 grupos. 
ENTRADAS: 
- via mod "SPI_slv_dpRAM" escreve-se a DPRAM#1, 
um circ. externo escreve até 256 valores de 16 bits pela "port-b",
cada Word(16) tem:    tipoNrd=5bits | ValIN=11bits |
tipoNrd: 
• 00000=nrd "rate code" (RC): valIN é delay p/ freqs (1 Hz ... ~666 Hz)
valIN = int((2000-freq*2)/freq);  onde "freq" é a frequência desejada.
• 01bbbb=nrd "phase coding" (PH) e bbbb tem o indx da LUT c/ nrd que faz sync
(valIN = delay com relação ao nrd indexado na LUT da base do grupo bbb)
• 10bbbb=nrd "pop code" (PP), bbbb=indx do grupo na LUT c/ val limiar
PPR:if(ValIN<(limiar<<2)){disparo=ValIN}else{zero}
ValLIM = int( ((2000-freq*2)/freq)<<2 ). O valor é multiplicado p/ 4.
ValIN: 11 bits que controlam delay ou limiar p/ disparo.

- via "SPI_slv_dpRAM" escreve-se na DPRAM#2 (64W x 8bits) 
(a) escreve-se 16 vars 8 bits (add 0x00 até 0x0F), forma LUT com 16 indxs
de nrds cujos disparos são usados para "phase coding";
ex: se nrd 7 é ref, depois que nrd 7 dispara, nrd X conta delay valIN(X)ms;
se nrd 7 dispara em alta freq (delay menor que valIN(X), nrd X não dispara.
(b) escreve-se 16 vars 8 bits (add 0x10 até 0x1F), com uma LUT C/ vals de
limiares (delaysX4) p/ 16 grupos de nrds codificados em 'population code'
ex: ValLIM=250, quaQuer delay menor que (250x4) gera freq saída, ou seja,
se valIN < 1000 começa a disparar. F=1/T; 1/(999)ms => acima de ~1 Hz.
ex: ValLIM=1, quaQuer delay menor que (1x4) gera saída = F=1/(3ms)=333Hz
(c) escreve-se 32 indxs de nrds (add 0x20 até 0x3F), que terão as saídas
ligadas diretamente aos fios em paralelo de saída Firin_Out (FiredOut).

- via "SPI_slv_dpRAM" lê-se de uma DPRAM#3 (32W x 8bits = 256 bits).
O LSB do end 0x00 da DPRAM3 tem 1 bit(=1) se nrd #0 disparou; (=0) se não, 
O MSB do end 0x1F da DPRAM3 tem 1 bit(=1) se nrd #255 disparou; (=0) se não, 

- TODOS os "Adds" das DPRAMs devem estar entre 0x0300 até 0x3FFF (maior).

SAÍDA:
32 fios geram saída em paralelo de até 32 nrds, chamada FiredOut. Os indxs
dos nrds que disparam está nos ends (add 0x20 até 0x3F) da DPRAM2.
O módulo (SLAVE) usa SPI de 4 fios (CPOL=0 CPHA=0 OU 1,1) p/ enviar resultados
sck  ==> clock da interface que vem do MESTRE que controla barramento
mosi ==> dado de entrada (1 bit serial) do mestre para este escravo
miso ==> dado de saída (1 bit serial) daqui p/ mestre 
nss  ==> chip select (em NÍVEL LOW enquanto há comunicação M<=>S)
OBS: o sinal sck é enviado como clk da memória no "port b"
--
Módulo SPI SLAVE memória DUAL-PORT RAM (port "b" carregada por SPI)
O modulo endereça até (2^22)-1 pos mem, (Addx vem no SRcmd, de 24 bits)
NÃO USAR Addx = 22'b00_0000_0000_0000_0000_0000 (reservado).
O módulo usa padrão SPI de 4 fios (CPOL=1 CPHA=1 ou CPOL=0 CPHA=0)
sck  ==> clock da interface que vem do MESTRE que controla barramento
mosi ==> dado de entrada (1 bit serial) do mestre para este escravo
miso ==> dado de saída (1 bit serial) daqui p/ mestre 
nss  ==> chip select (em NÍVEL LOW enquanto há comunicação M<=>S)
OBS: o sinal sck é enviado como clk da memória no "port b"
--
Funcionamento:
1. o mestre baixa=↓nss (nss=0 ativo; nss=1 final)
2. mestre coloca bit de dado (para SRcmd)
3. mestre pulsa "sck" (↓sck e ↑sck)ou(↑sck e ↓sck) - strCapture ↑sck
4. depois de 22 pulsos, SRcmd = |Add22| ... |Add0| ? | ? |
   4.1 o circ copia SRcmd[21:0] p/ "Radd_b"
5. No 23o. pulso o sinal SRcmd[1] é copiado (ler=1; escrever=0)
6. se SRCmd[1]=0, (memory write)
  6.1 até 23o ↑sck o circ copia MOSI e desloca SRin,
  6.2 na ↓sck qdo (SZW-1), o circ gera wen_b;
  6.3 prox ↑sck, copia {SRin[SZWD-2:0], mosi} p/ mem pelo port-b
  6.4 prox ↓sck baixa wen_b;
  6.5 O valor do Radd_b (= Add_b) é inc 2 sck após wen_b (++Radd_b)
  6.5 se SRcmd[0]=1 (modo contínuo), repete de 6.1 (até que item 8 ocorra)
7. se SRCmd[1]=1, (memory read)
  7.1 na ↑do 16o. ↑sck o circ lê memória (retém em Q_b)
  7.2 na prox ↓sck copia Q_b p/ SRout
  7.3 O valor do Radd_b (= Add_b) é inc (++Radd_b)
  7.3 a cada ↓sck desloca SRout 1 bit p/ esquerda até SZW-1, 
  7.4 se SRcmd[0]=1, em (SZW-1), prox ↑sck, lê mem p/ Q_b e repete 7.2
8. quando ↑nss volta para reset

obs1: ** este módulo grava PORT_B da memória via dados que vem do SPI.
OBS2: ** alterar o módulo DPRAM (IP da Intel) "dpRAM_01" e ajustar:
        SZWD(A/B) = para o tamanho da palavra (8/16/32 bits) de memória
        SZADD(A/B) = tamanho do bus add da memória (e.g. p/ 1K, SZADDA=10)
Params do IP DPRAM: clk_a, clk_b, wen_a, wen_b separados, o resto default
ADD0 é end inicial desse módulo de RAM; e ADDF = ADD0+((2**SZADDB)-1).
-----------------------------------------------------------------------------*/
module SpikeDriver_SPI                 // este modulo 256 nrds
  (
  input clk10M, clk2K, nreset,         // ↑clk_10_MHz, ↑clk_2_KHz e ↓reset
  input lsck, lmosi, lnss,             // input do SPI
  output lmiso,                        // saída SPI
  output reg [SZPFIRED-1:0] FiredOut,  // saída Parallel Firing OUt
  output [31:0] TestPoint,            // test points 7 bits
  output [7:0] LED,
  output reg trg
  );
  
  // ** para testes !!!
  reg [7:0] estado;
  assign TestPoint = {WQ_4a,2'b0,AddLST,estado};
  assign LED[0] = rd_3a;
  //assign TestPoint = {WQ_4a,WQ_1a};
  

  // parametros desse módulo no sistema
  parameter SZCMD = 24;                // ** SPI: comando com 24 bits !!!
  parameter ADD0 = 22'h20_3800;        // end ini da DPRAM#1 no sistema
  parameter ADD1 = 22'h20_3900;        // end da DPRAM#2 no sistema
  parameter ADD2 = 22'h20_3940;        // end da DPRAM#3 no sistema
  // parametros internos do módulo
  localparam SZWD1=16;                 // tam WRD da DPRAM#1 ports a/b
  localparam SZADD1 = 8;               // tam do BUS de end da DPRAM#1
  localparam SZWD2=SZADD1;             // tam WRD da DPRAM#2 (idx p/ #1)
  localparam SZADD2 = 6;               // tam do BUS de end da DPRAM#2 
  localparam SZWD3A = 1;               // larg word port-a (1...1024 bits)
  localparam SZADD3A = 8;              // larg bus Add mem port-a (256 bits)
  localparam SZWD3B = 16;              // larg word port-b:SPI (32,16,8 bits)
  localparam SZADD3B = 4;              // larg bus add mem port-b (16 wrds)
  localparam SZPFIRED=32;              // tam saídas paralelas FiredOut 
  // constantes para zerar ou setar regs internamente
  localparam [SZWD1-6:0] ZEROWD1 = {{(SZWD1-6){1'b0}},1'b0}; // 11 bits
  localparam [SZWD1-1:0] FIREDSTT1 = {4'b1100,{(SZWD1-8){1'b0}},4'b0001};
  localparam [SZWD1-1:0] FIREDSTT2 = {4'b1100,{(SZWD1-8){1'b0}},4'b0010};
  localparam [SZWD1-1:0] FIREDSTT3 = {4'b1100,{(SZWD1-8){1'b0}},4'b0100};
  localparam [SZWD1-1:0] FIREDSTT4 = {4'b1100,{(SZWD1-8){1'b0}},4'b1000};
  localparam [SZADD1-1:0] RESADDN = {{(SZADD1-1){1'b0}},1'b0};
  localparam [SZADD1-1:0] ULTADDN = {{(SZADD1-1){1'b1}},1'b1};
  localparam [SZADD3A-1:0] RESADDFRD = {{(SZADD3A-1){1'b0}},1'b0};
  localparam [SZADD3A-1:0] ULTADDFRD = {{(SZADD3A-1){1'b1}},1'b1};
  localparam [SZADD2-1:0] RESADDLST = {{(SZADD2-1){1'b0}}, 1'b0};
  localparam [SZADD2-1:0] FIRADDLST = {1'b1,{(SZADD2-2){1'b0}},1'b0};
  localparam [SZADD2-1:0] ULTADDLST = {{(SZADD2-1){1'b1}},1'b1};
// regs, flags e fios do sistema
  reg [SZWD1-1:0] RD_4a;               // reg rasc guarda Resultado 1o. mod
  reg [SZWD1-1:0] Rasc;                // reg rasc p/ PH e PP coding
  reg [SZADD1-1:0] AddN;               // Add do nrd under test
  reg [SZADD2-1:0] AddLST;             // add da mem dpRAM#2
  reg [SZADD2-1:0] Radd_2a;            // add rasc da mem dpRAM#2
  reg [(2**SZWD2)-1:0] Rfired;         // reg 255 bits c/ disparos (*t-1)
  reg wen_3a;                          // hab gravar port_a mem#3 (ctrl FSM)
  reg wen_4a;                          // hab gravar port_a mem#4 (ctrl FSM)
// sel ADD (mux): p/ Add_2a (0=Q_1a, 1=AddLST); p/ Add_3a(0=AddN, 1=Q_2a)
  reg selmxAdd_2a;                     // selmux Add_2a control na FSM
  reg selmxAdd_3a;                     // selmux Add_3a control na FSM
// lógica para geração do sinal de saída lmiso
  wire lmiso1, lmiso2, lmiso3;
  assign lmiso = lmiso1 | lmiso2 | lmiso3;

// ** para testes
  reg [15:0] val_16;
  
// ↑↑ FSM principal - controle de todo o processo

  reg [6:0] stt;                       // vetor p/ controlar estado da máq
  parameter SRES=0, CPMM_01=1, CPMM_02=2, CPMM_03=3, CPMM_04=4, CPMM_05=5, 
            LOOP_INI=6, TEST_FIRED=7, AFT_FIRE_TST=8, LOOP_PH1=9, LOOP_PH2=10,
            LOOP_PP1=11, LOOP_PP2=12, LOOP_FIM=13,
            FOUT_01=14, FOUT_02=15, FOUT_03=16, FOUT_04=17, FOUT_SAI=18,
            CPFIR_01=19, CPFIR_02=20, CPFIR_03=21, CPFIR_04=22, CPFIR_SAI=23,
            WAIT_LOW=24, WAIT_HIGH=25,
            S1X=26, S2X=27, S3X=28, S4X=29, S5X=30, S6X=31, S4Y=32;
always @(posedge clk10M or negedge nreset)  // ↑clk10M ou ↓nreset
  begin
    if (nreset=='b0)                   // se nreset = '0'
      begin
        stt <= SRES;
trg <= 'b0;
      end
    else
      begin
        case(stt)
        SRES:                          //SRES: sai do reset... 
          begin
            stt <= S1X;
            //stt<=S1;                   // vai p/ S1 iniciar varredura AddN 
          end

// ** para testes - preencher as mems #1 e #2 internamente
S1X:     //  ini
  begin
    stt <= S2X;
  end
S2X:     // ↑clk10M, grava #4 : muda val_16
  begin
    if (AddN == ULTADDN)       // se gravou no último AddN
      begin
        stt <= S3X;             // vai para S3X (preencheu tudo)
      end
    else                       // se AddN < 0xFF (último AddN)
      begin
        stt <= S2X;            // volta p/ estado S2X
      end
  end
S3X:
  begin
    stt <= S4X;
  end
S4X:     //  ini
  begin
    if (AddN == ULTADDN)       // se gravou no último AddN
      begin
        stt <= S5X;             // vai para S5 (preencheu tudo)
      end
    else                       // se AddN < 0xFF (último AddN)
      begin
        stt <= S4X;            // volta p/ estado S4X
      end
  end
S5X:
  begin
    stt <= S6X;                // volta p/ estado S5X
  end
S6X:       // ↑clk10M, muda val D2 e Add#2
  begin
    if (Radd_2a == 6'b11_1111)    // se gravou no último AddN
      begin
        stt <= CPMM_01;         //nxtEV: CPMM_01'
      end
    else
      begin
        stt <= S6X;             // vai para S6X
      end
  end
// ** para testes - preencher as mems #1 e #2 internamente

// preencher a memória #4 copiando valores iniciais da mem #1 p/ mem #4
        CPMM_01:                       // CPMM_01: ↑clk10M, leu Q1
          begin                        // nxtEV: CPMM_02' (copy D4<=Q1)
            stt <= CPMM_02;            // prox stt CPMM_02
          end
        CPMM_02:                       // ↑clk10M, salvou D4
          begin                        // nxtEV: CPMM_03' (++AddN, WE4=0)
            stt <= CPMM_03;            // prx CPMM_03
          end
        CPMM_03:                       // ↑clk10M, leu Q1
          begin                        // nxtEV: CPMM_04' (copy D4<=Q1)
            stt <= CPMM_04;            // prx CPMM_04
          end
        CPMM_04:                       // ↑clk10M, salvou D4
          begin                        // nxtEV: CPMM_03' ou CPMM_05'
            if (AddN == ULTADDN)       // se salvou no último AddN
              begin                    // nxtEV: CPMM_05' (AddN=0, WE4=0)
                stt <= CPMM_05;        // vai para CPMM_05 (preencheu mem)
              end
            else                       // se AddN<0xFF (< último AddN)
              begin                    // nxtEV: CPMM_03' (++AddN, WE4=0)
                stt <= CPMM_03;        // volta p/ estado CPMM_03
              end
          end
        CPMM_05:                       // ↑clk10M, fim da cópia da mem
          begin                        // nxtEV: LOOP_INI'
            stt <= S4Y;           // prox stt
          end
S4Y:     //  ini
  begin
trg <= 'b1;
    if (AddN == ULTADDN)       // se gravou no último AddN
      begin
        stt <= LOOP_INI;             // vai para LOOP_INI (verificou)
      end
    else                       // se AddN < 0xFF (último AddN)
      begin
        stt <= S4Y;            // volta p/ estado S4X
      end
  end
// mem #4 preenchida - pode iniciar operação
        LOOP_INI:                      // ↑clk10M, lêu Q4[AddN] e Q1[AddN]
          begin                        // nxtEV: TEST_FIRED'
            stt <= TEST_FIRED;         // prox stt
          end
        // equivale à função CPMM_04 acima (salvar e teste ultimo AddN
        TEST_FIRED:                    // ↑clk10M, salvar D4 e D3 
          begin
            if (AddN == ULTADDN)       // se salvou o último AddN
              begin                    // nxtEV: LOOP_FIM'
                stt <= LOOP_FIM;       // vai para CPMM_05 (fim loop)
              end
            else                       // se AddN<0xFF (< último AddN)
              begin
              case (WQ_4a[SZWD1-1:SZWD1-2]) // testa 2 MSB de Q4
        // tipo fire-rate coding: Q4 p/ ver se disparou
              (2'b00):
                begin
                  stt<=AFT_FIRE_TST;   // volta p/ AFT_FIRE_TST
                end
        // tipo phase-coding: testa Q4 p/ firing ou vai p/ teste de fase
              (2'b01):                 // PH: gerar codigo "phase coding"
                begin
                  if (WQ_4a[10:0]==ZEROWD1)// WQ_4a[10:0] = zero? fired!
                    begin
                      stt <= AFT_FIRE_TST; // volta p/ AFT_FIRE_TST
                    end
                  else                 // se não zero, testa phase
                    begin              // nxtEV: LOOP_PH1' (ajst ler Fired)
                      stt <= LOOP_PH1; // cont Phase-Coding em LOOP_PH1
                    end
                end 
        // tipo population-coding: lê (Q_2a<<2) p/ comparar com Q4_a
              (2'b10):                 // PP: gerar cod "population coding"
                begin                  // nxtEV: LOOP_PP1' (ajst Radd_2a)
                  stt <= LOOP_PP1;     // cont Phase-Coding em LOOP_PP'
                end
        // todos os tipos passam por estes estágios pós-disparo
              (2'b11):                 // ↑clk10M, estágios do disparado
                begin 
                  stt <= AFT_FIRE_TST; // cont Phase-Coding em S7
                end
              endcase
              end
          end
      // depois do teste fired, grava novo RD_4a na mem #4 e "fired" em rd_3a
        AFT_FIRE_TST:                  // (AFT_FIRE_TST)↓ WE4=0, ++AddN
          begin 
            stt <= TEST_FIRED;         // prox stt
          end

      // caso especial 1: Phase code (se Rfired[Q2]=1 na iteração anterior)
        LOOP_PH1:                      // ↑clk10M, lê Q_2a[Radd_2a] (são 8bits)
          begin                        // nxtEV: LOOP_PH2' ajst p/ ler Rfired
            stt <= LOOP_PH2;           // prox stt
          end
        LOOP_PH2:                      // ↑clk10M, faz nada
          begin                        // nxtEV: AFT_FIRE_TST' (volta loop)
            stt <= AFT_FIRE_TST;       // prox stt AFT_FIRE_TST
          end

      // caso especial 2: Population code (testa se WQ_4a <= (Q_2a << 2))
        LOOP_PP1:                      // ↑clk10M, lê Q_2a[Radd_2a]
          begin                        // nxtEV: LOOP_PP2' (testa disp)
            stt <= LOOP_PP2;           // vai para estado LOOP_PP2
          end
        LOOP_PP2:                      // ↑clk10M, muda stt apenas
          begin                        // nxtEV: AFT_FIRE_TST' (volta loop)
            stt <= AFT_FIRE_TST;       // vai para estado AFT_FIRE_TST
          end
        LOOP_FIM:                      // ↑clk10M, vai p/ 
          begin                        //nxtEV: FIRE_OUT1' ajst add mem #3
            stt <= FOUT_01;            // prox stt
          end

      // varredura da lista (32 elementos em Q2) p/ set do FiredOut[AddLST]
        FOUT_01:                       // FOUT_01: ↑clk10M, leu Q2
          begin                        // nxtEV: FOUT_02' (copy D4<=Q1)
            stt <= FOUT_02;            // prox stt FOUT_02
          end
        FOUT_02:                       // ↑clk10M, ler Q3
          begin                        // nxtEV: FOUT_03' (salva, ++Add)
            stt <= FOUT_03;            // prx FOUT_03
          end
        FOUT_03:                       // ↑clk10M, leu Q3[Q2]
          begin                        // nxtEV: FOUT_04' 
            stt <= FOUT_04;            // prx FOUT_04
          end
        FOUT_04:                       // ↑clk10M, salvou D4
          begin                        // nxtEV: FOUT_03' ou FOUT_SAI'
            if (AddLST == ULTADDLST)   // se salvou no último ULTADDLST
              begin                    // nxtEV: FOUT_SAI'
                stt <= FOUT_SAI;        // vai para FOUT_05 (preencheu mem)
              end
            else                       // se AddN<0xFF (< último AddN)
              begin                    // nxtEV: FOUT_03' (++AddN, WE4=0)
                stt <= FOUT_03;        // volta p/ estado FOUT_03
              end
          end
        FOUT_SAI:
          begin
            stt <= CPFIR_01;           // prx CPFIR_01
          end
          
      // loop copiar estado disparos em Rfired
        CPFIR_01:                      // CPFIR_01: ↑clk10M, leu Q3[0]
          begin                        // nxtEV: CPFIR_02' (Rfired<=Q3)
            stt <= CPFIR_02;           // prox stt CPFIR_02
          end
        CPFIR_02:                      // ↑clk10M, salvou Rfired
          begin                        // nxtEV: CPFIR_03' (++AddN)
            stt <= CPFIR_03;           // prx CPFIR_03
          end
        CPFIR_03:                      // ↑clk10M, leu Q3
          begin                        // nxtEV: CPFIR_04' (Rfired<=Q3)
            stt <= CPFIR_04;           // prx CPFIR_04
          end
        CPFIR_04:                      // ↑clk10M, salvou D4
          begin                        // nxtEV: CPFIR_03' ou CPFIR_05'
            if (AddN == ULTADDN)       // se salvou no último AddN
              begin                    // nxtEV: CPFIR_05' (AddN=0, WE4=0)
                stt <= CPFIR_SAI;      // vai para CPFIR_SAI (preencheu mem)
              end
            else                       // se AddN<0xFF (< último AddN)
              begin                    // nxtEV: CPFIR_03' (++AddN, WE4=0)
                stt <= CPFIR_03;       // volta p/ estado CPFIR_03
              end
          end
        CPFIR_SAI:                     // ↑clk10M, fim da cópia Rfired
          begin
            stt <= WAIT_LOW;           // prox stt
          end

      // terminou varredura Fireout[k], espera nova subida de ↑clk2K...
        WAIT_LOW:                      //se clk2K='1' espera descer 
          begin
            if (clk2K=='b1) begin stt<=WAIT_LOW; end 
            else begin stt<=WAIT_HIGH; end
          end
        WAIT_HIGH:                     //clk2K está em '0' e sobe
          begin
            if (clk2K=='b0)            // se clk2K == zero, repete S16
              begin
                stt<=WAIT_HIGH; 
              end 
            else                       // ↑clk2K, recomeçar LOOP
              begin                    // nxtEV: LOOP_INI'
                stt <= LOOP_INI;       // repete ciclo a partir de S4 
              end // p/ S4 reiniciar varredura AddN 
          end
        endcase
      end
end // -- final da FSM


// ↓↓ FSM: responde na descida do clodk 10MHz
always @(negedge clk10M or negedge nreset)  // ↓clk10M ou ↓nreset
  begin
    if (nreset=='b0)                   // se nreset = '0'
      begin
        AddN <= RESADDN;               // reset do indx de nrd
wen_1a <= 'b0;                 // reset wen_1a
        val_16 <= 16'd8;
        RD_1a <= 16'd7;
        wen_4a <= 'b0;                 // reset wen_4a
        wen_3a <= 'b0;                 // reset wen_3a
        selmxAdd_2a <= 'b0;            // ctrl mux sel Add_2a
        selmxAdd_3a <= 'b0;            // ctrl mux sel Add_3a
      end
    else
      begin
        case(stt)
        SRES:                          //SRES: sai do reset... 
          begin
          end
// ** para testes - preencher as mems #1 e #2 internamente
S1X:     //  ini
  begin
    wen_1a <= 'b1;              // para escrever em wen_1a
  end
S2X:     // ↑clk10M, grava #4 : muda val_16
  begin
    RD_1a <= val_16;
    if (val_16 == 12) val_16 <= 16'd7; else val_16 <= val_16 + 'b1;
    AddN <= AddN + 'b1;    // inc AddN
  end
S3X:
  begin
    wen_1a <= 'b0;         // parar de escrever em wen_1a
    AddN <= RESADDN;       // restart AddN
  end
S4X:     //  ini
  begin
    AddN <= AddN + 'b1;    // inc AddN
  end
S5X:        // ↑clk10M, grava #2 [32...] : muda val_16
  begin
    Radd_2a <= 6'b000000;
    RD_2a <= 8'd2;              // input Da DPRAM#2
    wen_2a <= 'b1;              // para escrever em wen_4a
  end
S6X:       // ↑clk10M, muda val D2 e Add#2
  begin
    Radd_2a <= Radd_2a + 'b1;    // inc Radd_2a
    if (Radd_2a < 6'b100000)   // se gravou no último AddN
      begin
        RD_2a <= 8'b0;
      end
    else
      begin
        RD_2a <= RD_2a + 'b1;
      end
  end
// ** para testes - preencher as mems #1 e #2 internamente

      // preencher a memória #4 copiando valores iniciais da mem #1
        CPMM_01:                       //(CPMM_01')↓clk10M: inicia AddN=0
          begin                        // nxtEV: ↑CPMM_01
            wen_2a <= 'b0;             // parar de escrever em wen_2a
            AddN <= RESADDN;           // restart AddN p/ zero
          end
        CPMM_02:                       //(CPMM_02')↓ leu Q1[0]: D4<=Q1, WE4=1
          begin                        // nxtEV: ↑CPMM_02 (salvar D4)
            wen_4a <= 'b1;             // hab memWR #4
            RD_4a <= WQ_1a;            // D4[0] <= Q1[0]
          end
        CPMM_03:                       // (CPMM_03') ↓clk10M, WE4=0, ++AddN
          begin                        // nxtEV: ↑CPMM_03
            wen_4a <= 'b0;             // desabilita memWR #4
            AddN <= AddN + 'b1;        // inc AddN
          end
        CPMM_04:                       // (CPMM_04')↓ leu Q1[0]: D4<=Q1, WE4=1
          begin                        // nxtEV: ↑CPMM_04 (save D4, test AddN)
            wen_4a <= 'b1;             // hab memWR #4
            RD_4a <= WQ_1a;            // RD_4a copia WQ_1a da mem #1
          end
        CPMM_05:                       // (CPMM_05')↓ fim da cópia
          begin                        // nxtEV: ↑CPMM_05 (vai p/ LOOP_INI)
            wen_4a <= 'b0;             // desabilita memWR #4
            AddN <= RESADDN;           // restart AddN p/ zero
          end
S4Y:     //  ini
  begin
    AddN <= AddN + 'b1;    // inc AddN
  end
      // mem #4 preenchida - pode iniciar operação
        LOOP_INI:                      // (LOOP_INI')↓: muda muxes
          begin                        // nxtEV: ↑LOOP_INI (ler Q1 e Q4)
estado <= 8'b0000_0001;
            AddN <= RESADDN;           // restart AddN p/ zero
            selmxAdd_2a <= 'b0;        // ctrl mux sel Add_2a
            selmxAdd_3a <= 'b0;        // ctrl mux sel Add_3a
          end
        TEST_FIRED:                    // (TEST_FIRED)↓: leu Q1[0] e Q4[0]
          begin                        // nxtEV: ↑TEST_FIRED (save M#3 M#4)
            case (WQ_4a[SZWD1-1:SZWD1-2]) // testa 2 MSB da var contd do nrd
              // tipo fire-rate coding: testa Q4 p/ ver se disparou
            (2'b00):
              begin
estado <= 8'b0001_0000;
                wen_4a <= 'b1;         // hab memWR #4 (salvar novo RD_4a)
                wen_3a <= 'b1;         // hab memWR #3 (salvar "fired")
                if (WQ_4a[10:0]==ZEROWD1) // WQ_4a[10:0] = zero? fired!
                  begin
                    rd_3a<='b1;        // dispara o nrd
                    RD_4a<=FIREDSTT1;  // disparo está no estágio 1
                  end
                else                   // se não zero, só decrementa
                  begin
                    rd_3a<='b0;        // não dispara o nrd
                    RD_4a<=WQ_4a-'b1;  // dec 1 de WQ_4a
                  end
              end
      // tipo phase-coding: testa Q4 p/ firing ou vai p/ teste de fase
            (2'b01):                   // PH: gerar codigo "phase coding"
              begin
estado <= 8'b0001_0001;
                if (WQ_4a[10:0]==ZEROWD1) // WQ_4a[10:0] = zero? fired!
                  begin                // nxtEV: 
                    wen_4a <= 'b1;     // hab memWR #4 (salvar novo RD_4a)
                    wen_3a <= 'b1;     // hab memWR #3 (salvar "fired")
                    rd_3a<='b1;        // dispara o nrd
                    RD_4a<=FIREDSTT1;  // disparo está no estágio 1
                  end
                else                   // se não zero, testa phase em S6
                  begin                // nxtEV: LOOP_PH1' (ajst ler Q2)
                    rd_3a <= 'b0;      // NÃO dispara o nrd
                  end
              end 
      // tipo population-coding: lê (Q_2a<<2) p/ comparar com Q4_a
            (2'b10):                   // PP: gerar cod "population coding"
              begin 
estado <= 8'b0001_0010;
                Rasc<=WQ_4a;           // salva valor de WQ_4a p/ comparar
              end
      // todos os tipos passam por estes estágios pós-disparo
            (2'b11):                   // ↑clk10M, estágios do disparado
              begin 
estado <= 8'b0001_0011;
                wen_4a <= 'b1;         // hab memWR #4 (salvar novo RD_4a)
                wen_3a <= 'b1;         // hab memWR #3 (salvar "fired")
                case (WQ_4a)           // testar estado de Q4[AddN]
                FIREDSTT1:             // 1o. clk10M depois do disparo
                  begin
                    rd_3a<='b1;        // dispara o nrd
                    RD_4a<=FIREDSTT2;  // disparou e está no estágio 2
                  end
                FIREDSTT2:             // 2o. clk10M depois do disparo
                  begin
                    rd_3a<='b0;        // dispara o nrd ?
                    RD_4a<=FIREDSTT3;  // está no estágio 3
                  end
                FIREDSTT3:             // 3o. clk10M depois do disparo
                  begin
                    rd_3a<='b0;        // dispara o nrd ?
                    RD_4a<=FIREDSTT4;  // está no estágio 4
                  end
                FIREDSTT4:             // 4o. clk10M depois do disparo
                  begin
                    rd_3a<='b0;        // dispara o nrd
                    RD_4a<=WQ_1a;      // copia dado de Q1[AddN] => D4[AddN]
                  end
                default:               // 5o. clk10M depois do disparo
                  begin
                    RD_4a<=WQ_1a;      // copia dado de Q1[AddN] => D4[AddN]
                  end
                endcase
              end
            endcase
          end
      // equivale em função ao CPMM_03
        AFT_FIRE_TST:                  // (AFT_FIRE_TST)↓ WE4=0, ++AddN
          begin                        // nxtEV: AFT_FIRE_TST
estado <= 8'b0010_0000;
            wen_4a <= 'b0;             // ↓desab memWR #4
            wen_3a <= 'b0;             // ↓desab memWR #3 (rd_3a)
            rd_3a <= 'b0;              // sem disparo o nrd
            RD_4a <= 16'd0;            // disparo está no estágio 1
            AddN <= AddN + 'b1;        // inc AddN
          end

      // caso especial 1: Phase code (se Rfired[Q2]=1 na iteração anterior)
        LOOP_PH1:                      // (LOOP_PH1') ajst Add p/ ler Q2
          begin                        // nxtEV: ↑LOOP_PH1 (lê Q2)
            Radd_2a<={2'b00,WQ_1a[SZWD1-3:SZWD1-6]};//add_2a:0x00..0F
          end
        LOOP_PH2:                      // (LOOP_PH2') c/ RFired[Q2], calc D3 e D4
          begin                        // nxtEV: ↑LOOP_PH3 (faz nada )
            wen_4a <= 'b1;             // hab memWR #4 (salvar novo RD_4a)
            wen_3a <= 'b1;             // hab memWR #3 (salvar "fired")
            if (Rfired[WQ_2a] == 'b1)  // se Rfired[Q2], nrd base =1 em *t-1
              begin                    // assim, reseta o nrd p/ Q_1a[AddN]
                RD_4a <= FIREDSTT4;    // coloca o nrd no estágio FIREDSTT4
              end
            else                       // este nrd não disp, nem o nrd base
              begin                    // assim, apenas decrementa este nrd
                RD_4a <= WQ_4a - 'b1;  // decrementa 1 unidade
              end
          end

      // caso especial 2: Population code (testa se WQ_4a <= (Q_2a << 2))
        LOOP_PP1:                      // (LOOP_PP1') ajst Add p/ ler #2
          begin                        // nxtEV: ↑LOOP_PP1 (lê Q2)
            Radd_2a<={2'b01,WQ_1a[SZWD1-3:SZWD1-6]}; //add_2a:0x10..0x1F
          end
        LOOP_PP2:                      // (LOOP_PP2') tem Q2, calc D3 e D4
          begin                        // nxtEV: ↑LOOP_PP2 (faz nada)
            wen_4a <= 'b1;             // hab memWR #4 (salvar novo RD_4a)
            wen_3a <= 'b1;             // hab memWR #3 (salvar "fired")
            if (Rasc <= (WQ_2a << 2))  // se Rasc (WQ_4a) <= Q_2a<<2 (limiar)
              begin
                rd_3a <= 'b1;          // dispara o nrd
                RD_4a <= FIREDSTT1;    // disparou e está no estágio 1
              end
            else                       // não está no limiar, decrementa
              begin
                rd_3a <= 'b0;          // NÃO dispara o nrd
                RD_4a <= WQ_4a - 'b1;  // decrementa 1 unidade
              end
          end
        LOOP_FIM:                      // (LOOP_FIM') lê idxnrd Q2[AddLST]
          begin
estado <= 8'b0011_0000;
            wen_4a <= 'b0;             // ↓desab memWR #4
            wen_3a <= 'b0;             // ↓desab memWR #3 (rd_3a)
            AddN <= RESADDN;           // restart AddN p/ zero
          end

      // varredura da lista (32 elementos em Q2) p/ set do FiredOut[AddLST]
        FOUT_01:                       //(FOUT_01')↓clk10M: inicia AddN=0
          begin                        // nxtEV: ↑FOUT_01 (ler Q2[0])
            AddLST <= FIRADDLST;       // 1o. end lista fired (addLST=0)
            selmxAdd_2a <= 'b1;        // sel Add_2a p/ AddLST
            selmxAdd_3a <= 'b1;        // sel Add_3a p/ WQ_2a
          end
        FOUT_02:                       //(FOUT_02')↓ leu Q2[AddLST]
          begin                        // nxtEV: ↑FOUT_02 (ler Q3[Q2])
                                       // faz nada
          end
        FOUT_03:                       // (FOUT_03')↓:leu Q3[], salva, ++Add 
          begin                        // nxtEV: ↑FOUT_03 (ler Q2[AddLST])
            FiredOut[AddLST-6'd32]<=wQ_3a;   // salva bit wQ_3a em FiredOut[AddLST]
            AddLST<=AddLST+'b1;        // inc indx da lista (p/ ler Q2)
          end
        FOUT_04:                       // (FOUT_04')↓ leu Q2[AddLST]
          begin                        // nxtEV: ↑FOUT_04 (ler Q3[Q2])
                                       // faz nada
          end
        FOUT_SAI:
          begin
            FiredOut[AddLST-6'd32]<=wQ_3a;   // salva wQ_3a[MSB] em FiredOut[MSB]
            selmxAdd_2a <= 'b0;        // sel Add_2a p/ Radd_2a
            selmxAdd_3a <= 'b0;        // sel Add_3a p/ AddN
          end

      // loop copiar estado disparos em Rfired
        CPFIR_01:                      //(CPFIR_01')↓clk10M: inicia AddN=0
          begin                        // nxtEV: ↑CPFIR__01 (ler Q3[0])
            AddN <= RESADDN;           // restart AddN p/ zero
          end
        CPFIR_02:                      //(CPFIR_02')↓ leu Q3[0]
          begin                        // nxtEV: ↑CPFIR__02
            Rfired[AddN] <= wQ_3a;     // salva WQ_3a[0] em Rfired
          end
        CPFIR_03:                      // (CPFIR_03') ↓clk10M ++AddN
          begin                        // nxtEV: ↑CPFIR__03 (ler Q3[AddN])
            AddN <= AddN + 'b1;        // inc AddN
          end
        CPFIR_04:                      // (CPFIR_04')↓ leu Q3[AddN]
          begin                        // nxtEV: ↑CPFIR_04 testa AddN
            Rfired[AddN] <= wQ_3a;     // salva WQ_3a[0] em Rfired
          end
        CPFIR_SAI:                     // (CPFIR_SAI')↓ fim da cópia
          begin                        // nxtEV: ↑CPFIR__05 (vai p/ LOOP_INI)
            AddN <= RESADDN;           // restart AddN p/ zero
            wen_4a <= 'b0;             // reset wen_4a
            wen_3a <= 'b0;             // reset wen_3a
            selmxAdd_2a <= 'b0;        // reset mux sel Add_2a p/ Radd_2a
            selmxAdd_3a <= 'b0;        // reset mux sel Add_3a p/ AddN
          end
      // terminou varredura Fireout[k], espera nova subida de ↑clk2K...
        endcase
      end
end // -- final da FSM 

// DPRAM#1: mestre escreve tipo/vals que controlam a conversão/geração spikes
//  wire wen_1a;                         // wen locais p/ port_a DPRAM#1
reg wen_1a;
//  assign wen_1a = 'b0;                 // nunca escreve pela port_a
  wire [SZWD1-1:0] WQ_1a;              // saída Qb DPRAM#1
reg [SZWD1-1:0] RD_1a;              // saída Qb DPRAM#1
//  wire [SZWD1-1:0] WD_1a;              // saída Qb DPRAM#1
SPI_slv_dpRAM_256x16 #                 // mód SPI_slv_dpRAM_256x16 (params)
  (
  .SZWDA  ( SZWD1 ),                   // larg word port-a (1...1024 bits)
  .SZADDA ( SZADD1 ),                  // larg bus Address mem port-a
  .SZWDB  ( SZWD1 ),                   // larg word port-b:SPI (32,16,8 bits)
  .SZADDB ( SZADD1 ),                  // larg bus Address SPI port-b
  .SZCMD  ( SZCMD ),                   // tamanho do reg. de comando "SRcmd"
  .ADD0   ( ADD0 )                     // end inicial da memória
  )
  slv_U1                               // nome do componente/instancia
  (
  .sck    ( lsck ),                    // ligar local sck no "sck" do SPI
  .mosi   ( lmosi ),                   // ligar local mosi no "mosi" do SPI 
  .nss    ( lnss ),                    // ligar local nss no "nss" do SPI 
  .miso   ( lmiso1 ),                  // ligar local miso no "miso" do SPI 
  .Add_a  ( AddN ),                    // bus_Add port_a #1 (=AddN)
  .clk_a  ( clk10M ),                  // clk mem#1 port_a (FSM)
  .wen_a  ( wen_1a ),                  // Write_Enable mem#1 port_a (=0)
  .D_a    ( RD_1a ),                   // dado p/ mem #1 port_a (sem uso)
  .Q_a    ( WQ_1a )                    // dado vem da mem #1 port_a
  );

// DPRAM#2 (LUT): 16 idx "PH", 16 lim "PP"<<2, 32 idxs nrds "fired" paralelo
//  wire wen_2a;                         // wen locais p/ port_a DPRAM#2
reg wen_2a;                         // wen locais p/ port_a DPRAM#2
//  assign wen_2a = 'b0;                 // nunca escreve pela port a
  wire [SZADD2-1:0] Add_2a;            // endereço port 'a' da DPRAM#2
  assign Add_2a = selmxAdd_2a? AddLST: Radd_2a; // mux sel Add_2a
//  wire [SZWD2-1:0] WD_2a;              // input Da DPRAM#2
reg [SZWD2-1:0] RD_2a;              // input Da DPRAM#2
  wire [SZWD2-1:0] WQ_2a;              // saída Qb DPRAM#2
SPI_slv_dpRAM_64x8 #                   // mód SPI_slv_dpRAM_64x8 (params)
  (
  .SZWDA  ( SZWD2 ),                   // larg word port-a (1...1024 bits)
  .SZADDA ( SZADD2 ),                  // larg bus Address mem port-a
  .SZWDB  ( SZWD2 ),                   // larg word port-b:SPI (32,16,8 bits)
  .SZADDB ( SZADD2 ),                  // larg bus Address SPI port-b
  .SZCMD  ( SZCMD ),                   // tamanho do reg. de comando "SRcmd"
  .ADD0   ( ADD1 )                     // end inicial da memória
  ) 
  slv_U2                               // nome do componente/instancia
  (
  .sck    ( lsck ),                    // ligar local sck no "sck" do SPI
  .mosi   ( lmosi ),                    // ligar local mosi no "mosi" do SPI 
  .nss    ( lnss ),                    // ligar local nss no "nss" do SPI 
  .miso   ( lmiso2 ),                  // ligar local miso no "miso" do SPI 
  .Add_a  ( Add_2a ),                  // bus_Add port_a #2 (=after mux)
  .clk_a  ( clk10M ),                  // clk mem#2 port_a (FSM)
  .wen_a  ( wen_2a ),                  // Write_Enable mem#2 port_a (=0)
  .D_a    ( RD_2a ),                   // dado p/ mem #2 port_a (sem uso)
  .Q_a    ( WQ_2a )                    // dado vem da mem #2 port_a
    );

// DPRAM#3 (mem FIRED) =1 nos nrds que dispararam agora!
  reg rd_3a;                           // ff-d fired =1 qdo nrd disparou;
  wire [SZADD1-1:0] Add_3a;            // Add da port_a mem 3 (fired)
  assign Add_3a = selmxAdd_3a? WQ_2a: AddN;  // mux quem endereça Add_3a
  wire wQ_3a;                          // fio conectado ao bit Qa, não usado
SPI_slv_dpRAM_256x1_16x16 #            // mód SPI_slv_dpRAM_64x8 (params)
  (
  .SZWDA  ( SZWD3A ),                  // larg word port-a (1...1024 bits)
  .SZADDA ( SZADD3A ),                 // larg bus Address mem port-a
  .SZWDB  ( SZWD3B ),                  // larg word port-b:SPI (32,16,8 bits)
  .SZADDB ( SZADD3B ),                 // larg bus Address SPI port-b
  .SZCMD  ( SZCMD ),                   // tamanho do reg. de comando "SRcmd"
  .ADD0   ( ADD2 )                     // end inicial da memória
  )
  slv_U3                               // nome do componente/instancia
  (
  .sck    ( lsck ),                    // ligar local sck no "sck" do SPI
  .mosi   ( lmosi ),                   // ligar local mosi no "mosi" do SPI 
  .nss    ( lnss ),                    // ligar local nss no "nss" do SPI 
  .miso   ( lmiso3 ),                  // ligar local miso no "miso" do SPI 
  .Add_a  ( Add_3a ),                  // bus_Add port_a #3 (=after mux)
  .clk_a  ( clk10M ),                  // clk mem#3 port_a (FSM)
  .wen_a  ( wen_3a ),                  // Write_Enable mem#3 port_a (FSM)
  .D_a    ( rd_3a ),                   // dado p/ a mem via port a
  .Q_a    ( wQ_3a )                    // dado vem da mem #3 port_a
    );

// DPRAM#4 (contadores e controle maq de estados)
  wire wen_4b;                         // wen locais p/ port_b DPRAM#4
  assign wen_4b = 'b0;                 // nunca escreve pela port b
  wire [SZADD1-1:0] Add_4b;            // ends port B da DPRAM#4 (sem uso)
//  wire  clk_4b;                        // clks da DPRAM#4 (sem uso)
//  assign clk_4b = 'b0;                 // clk sempre =0
  wire [SZWD1-1:0] WD_4b;               // entrada Db DPRAM#4
  wire [SZWD1-1:0] WQ_4a, WQ_4b;       // saídas Qa e Qb DPRAM#4
dpRAM_256x16 DP_U04                    // inst IP DRPRAM (On Chip Memory)
  (
  .address_a ( AddN ),                 // bus_Add port_a #4 (=AddN)
  .address_b ( Add_4b ),               // Add_4b (sem uso)
  .clock_a   ( clk10M ),               // clk mem#4 port_a (FSM)
  .clock_b   ( clk10M ),               // clock_b (sem uso = 0)
  .data_a    ( RD_4a ),                // data4_a (inc conts e FIREDSTT_)
  .data_b    ( WD_4b ),                // data4_b (sem uso)
  .wren_a    ( wen_4a ),               // Write_Enable mem#4 port_a (FSM)
  .wren_b    ( wen_4b ),               // Write_Enable mem#4 port_b (=0)
  .q_a       ( WQ_4a ),                // WQ_4a (sai contadores e FIREDSTT_)
  .q_b       ( WQ_4b )                 // WQ_4b (sem uso)
  );

endmodule

/* --------------------------------------------------------------------------
                  ... Como instanciar este módulo ...

SpikeDriver_SPI                        // este modulo com 256 nrds
  SpkDrv_U1                            // nome do componente/instance
  (
  .clk10M      ( clk_10M ),            // clock 10MHz do PLL
  .clk2K       ( clk_2K ),             // clock 2KHz preciso (do PLL)
  .nreset      ( n_reset),             // ↓reset ativo na descida p/ "0"
  .lsck        ( l_sck ),              // clk vem do mestre SPI
  .lmosi       ( l_mosi ),             // dado in "mosi" vem do mestre SPI
  .lnss        ( l_nss ),              // sel ativo em "0" vem do mestre SPI
  .lmiso       ( l_miso ),             // saída p/ SPI "miso". Passa p/ OR
  .FiredOut    ( l_FiredWire )         // fios saída 32 canais FiredOut
  );
  
OBS: este módulo deve ter os endereços das RAMs ajustados antes de sintetizar
     os endereços são de 22 bits: 00_0001 até 22'h3F_FFFF ( ~4 MBytes )
     NÃO usar o endereço 0x00_0000 porque é reservado do sistema/Avalon
----------------------------------------------------------------------------*/