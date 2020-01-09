/* ----------------------------------------------------------------------------
MODULO de interface serial     == SPI_slv_dpRAM_ ==  (CMD = 24 bits)
autor:   João Ranhel
versão:  1.1                   data: 2019_04_23
--
Módulo SPI SLAVE memória DUAL-PORT RAM (port "b" carregada por SPI)
O modulo endereça até (2^14)-1 pos mem, (Addx vem no SRcmd, de 16 bits)
NÃO USAR o endereço Addx = 14'b00_0000_0000_0000 (reservado).
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
4. depois de 14 pulsos, SRcmd = |Add14| ... |Add0| ? | ? |
   4.1 o circ copia SRcmd[13:0] p/ "Radd_b"
5. No 15o. pulso o sinal SRcmd[1] é copiado (ler=1; escrever=0)
6. se SRCmd[1]=0, (memory write)
  6.1 até 15o ↑sck o circ copia MOSI e desloca SRin,
  6.2 na ↓sck qdo (SZW-1), o circ gera wen_b;
  6.3 prox ↑sck, copia {SRin[SZWD-2:0], mosi} p/ mem pelo port-b
  6.4 prox ↓sck baixa wen_b;
  6.5 O valor do Radd_b (= Add_b) é inc 2 sck após wen_b (++Radd_b)
  6.5 se SRcmd[0]=1 (modo contínuo), repete de 6.1 (até que item 8 ocorra)
7. se SRCmd[1]=1, (memory read)
  7.1 na do 16o. pulso ↑sck o circ lê memória (retido em Q_b)
  7.2 na prox ↓sck copia Q_b p/ SRout
  7.3 O valor do Radd_b (= Add_b) é inc (++Radd_b)
  7.3 a cada ↓sck desloca SRout 1 bit p/ esquerda até SZW-1, 
  7.4 se SRcmd[0]=1, em (SZW-1), prox ↑sck, lê mem p/ Q_b e repete 7.2
8. quando ↑nss volta para reset

OBS: ** alterar o módulo DPRAM (IP da Intel) "dpRAM_01" e ajustar:
        SZWD(A/B) = para o tamanho da palavra (8/16/32 bits) de memória
        SZADD(A/B) = tamanho do bus add da memória (e.g. p/ 1K, SZADD=10)
Params do IP DPRAM: clk_a, clk_b, wen_a, wen_b separados, o resto default
ADD0 é end inicial desse módulo de RAM; e ADDF = ADD0+((2**SZADD)-1).
-----------------------------------------------------------------------------*/
module SPI_slv_dpRAM_256x16
  ( 
    input sck, mosi, nss,              // inputs SPI
    output miso,                       // serial OUT (usar OR em >1 interface)
    input [SZADDA-1:0] Add_a,          // end porta "a"
    input clk_a, wen_a,                // clk_a e write enable de 'a'
    input [SZWDA-1:0] D_a,             // dado entrada p/ mem p/ port 'a'
    output [SZWDA-1:0] Q_a             // dado saída p/ mem p/ port 'a'
  );
  
// pars *passados: larg WORD mem, larg Add_bus mem, faixa ends dessa interface
  parameter SZWDA = 1;                 // larg word port_a (ex 1 bits)
  parameter SZADDA = 8;                // larg Add_a: (ex 8 bits=256 adds)
  parameter SZWDB = 16;                // larg word port_b (ex 16 bits)
  parameter SZADDB = 4;                // larg Add_b: (ex 4 bits=16 adds)
  parameter SZCMD = 24;                // tam reg de comando: SRcmd
  parameter ADD0 = 22'h3F_0000;        // end inic RAM (ex:3F_0000...3F_FFFF)
// parametros locais
  localparam SZADD = SZCMD-2;          // tam reg end desse dispositivo SPI
  localparam SZCMDcnt = 5;             // num bits do contador de comando
  localparam SZBITcnt = 6;             // num bits do contador de BITs
  localparam ADDF=ADD0+((2**SZADDB)-1);// end final desse bloco de RAM
// p/ zerar SRdata E SRcmd - independente do comprimento em bits deles
  localparam [SZWDB-1:0] RESSR = {{(SZWDB-1){1'b0}}, 1'b0};
  localparam [SZCMD-1:0] RESCMD = {{(SZCMD-1){1'b0}}, 1'b0};
  localparam [SZCMDcnt-1:0] REScntCMD = {{(SZCMDcnt-1){1'b0}}, 1'b0};
  localparam [SZCMDcnt-1:0] LOCKcntCMD = {{(SZCMDcnt-1){1'b1}}, 1'b1};
  localparam [SZBITcnt-1:0] REScntBIT = {{(SZBITcnt-1){1'b0}}, 1'b0};
  localparam [SZBITcnt-1:0] LOCKcntBIT = {{(SZBITcnt-1){1'b1}}, 1'b1};
  localparam [SZADDB-1:0] RESADDB = {{(SZADDB-1){1'b0}}, 1'b0};
  localparam [SZADDB-1:0] RESADDSPI = {{(SZADD-1){1'b0}}, 1'b0};  
// esses registradores tem a ver com a interface serial de config
  reg [SZWDB-1:0] SRin, SRout;         // shiftReg entrada e saída
  reg [SZCMD-1:0] SRcmd;               // ShiftReg in comando
  reg [SZADD-1:0] RaddSPI;             // reg com end do disp SPI
  reg [SZADDB-1:0] Radd_b;             // reg end mem port-b (via SPI)
  reg [SZCMDcnt-1:0] CntCMD;           // conta bits de COMANDO
  reg [SZBITcnt-1:0] CntBIT;           // conta bits de DADOS 
  reg nxtWD;                           // flag new WD na ↓sck
  reg fWRDok;                          // flag chegou word
  wire mCS;                            // mem ChipSelect dessa DPRAM

// lógica combinacional deste módulo
  assign miso = mCS ? SRout[SZWDB-1]: 1'b0;
  assign mCS = ((RaddSPI>=ADD0) && (RaddSPI<=ADDF))? 'b1: 'b0;
  
// SUBIDA de sck: controla contadores de bits CMD ou DATA
always @(posedge sck or posedge nss)
  begin
    if(nss=='b1)                       // ... em reset
      begin 
        SRcmd <= RESCMD;               // zera o registrador de COMANDO
        SRin <= RESSR;                 // zera o reg desloc de entrada RESSR     
        CntCMD <= REScntCMD;           // zera contador de bits COMANDO
        CntBIT <= REScntBIT;           // zera contador de bits DADOS       
        nxtWD <= 'b0;                  // indicador prox palavra
        fWRDok <= 'b0;                 // não chegou comando...
      end   
    else if (CntCMD < LOCKcntCMD)
      begin
        case (CntCMD)
          (SZCMD-1):
            begin
              CntCMD <= CntCMD + 'b1;  // inc contador de bits
              SRcmd <= SRcmd << 1;     // desloca
              SRcmd[0] <= mosi;        // copia MOSI
              CntBIT <= REScntBIT;     // zera contador de bits DADOS        
            end
          SZCMD:
            begin
              nxtWD <= 'b0;            // indicador prox palavra      
              SRin <= SRin << 1;       // e deslocar dados
              SRin[0] <= mosi;         // entrada MOSI gravada em SRin[0] 
              CntCMD <= LOCKcntCMD;    // trava contador de bits COMANDO        
              CntBIT <= CntBIT + 'b1;  // continua contar bits         
            end
          default:
            begin
              CntCMD <= CntCMD + 'b1;  // inc contador de bits
              SRcmd <= SRcmd << 1;     // desloca
              SRcmd[0] <= mosi;        // copia MOSI        
            end
        endcase  
      end
    else if(CntBIT < LOCKcntBIT)
      begin
        case (CntBIT)
          (SZWDB-1):
            begin                      // tem que gravar na RAM
              fWRDok <= 'b1;           // liga fWRDok (chegou ao menos 1 WRD)
              SRin <= SRin << 1;       // e deslocar dados
              SRin[0] <= mosi;         // entrada MOSI gravada em SRin[0]
              nxtWD <= 'b1;            // indica nxt WORD p/ 
              if (SRcmd[0]=='b1)       // e flag SRcmd[0]=1 (continuar operação)
                CntBIT <= REScntBIT;   // volta CntBIT para zero
              else
                CntBIT <= LOCKcntBIT;  // se não, carrega CntBIT com 3F
            end
          default:
            begin
              nxtWD <= 'b0;            // indica que não é next word
              CntBIT <= CntBIT + 'b1;  // continua contar bits
              SRin <= SRin << 1;       // e deslocar dados
              SRin[0] <= mosi;         // entrada MOSI gravada em SRin[0] 
            end
        endcase 
      end
  end

// DESCIDA de sck: controla se carrega e qdo desloca o SRout
always @(negedge sck or posedge nss)
  begin
    if(nss=='b1)                       // ... em reset
      begin   
        SRout <= RESSR;                // zera o reg desloc de saída RESSR   
      end
    else if (CntCMD<LOCKcntCMD)        // se ainda recebe CMD
      begin
        if (CntCMD == SZCMD)           // se contadora bits cmd = SZCMD
          begin
            SRout <= Q_b;              // copia o valor da mem Q_b p/ SRout
          end
      end
    else                               // se não recebe mais bits de CMD
      begin 
        if (nxtWD=='b1)                // se flag next word=1
          begin
            SRout <= Q_b;              // copia o valor da mem Q_b p/ SRout
          end
        else                           // se nxt word =0, desloca SRout
          begin
            SRout <= SRout << 1;       // deslocar dados
          end
      end
  end

 // DESCIDA de sck: controla quando grava WRD na RAM
always @(negedge sck or posedge nss)
  begin
    if(nss=='b1)                       // ... em reset
      begin
        wen_b <= 'b0;                  // começa wen_b com zero
      end
    else if(CntBIT<LOCKcntBIT)         // se recebe palavras...
      begin
        case (CntBIT)
          (SZWDB-1):
            begin
              wen_b <= mCS & ~SRcmd[1];// gera write enable 
            end
          default:
            begin
              wen_b <= 'b0;            // volta wen_b p/ zero
            end
        endcase
      end
  end

// DESCIDA: controla o gerador de ENDEREÇO LOCAL (Radd_b) de memória 
always @(negedge sck or posedge nss)
  begin
    if(nss == 'b1)                     // ... em reset
      begin
        Radd_b <= RESADDB;             // inicializa Radd_b com zero
        RaddSPI <= RESADDSPI;          // inicializa RaddSPI com zero
      end
    else if (CntCMD == (SZCMD-2))      // se vieram SZCMD-2 bits cmd
      begin
        RaddSPI <= SRcmd[SZCMD-3:0];   // carrega RaddSPI c/ bits do SRcmd
        Radd_b <= SRcmd[SZADDB-1:0];   // carrega Radd_b c/ end ini da mem
      end
    else if (CntBIT == 2)              // no 2o. bit do CntBIT
      begin
      if (SRcmd[1] || fWRDok)          // é LER mem ou chegou nova word? 
        begin
          Radd_b <= Radd_b + 'b1;      // inc add Radd_b (loop 0xFF-->0x00)
        end
      end
  end

// --- para instanciar o IP de Dual-port RAM ---
  wire [SZWDB-1:0] D_b, Q_b;           // Data in B e data out B
  reg  wen_b;                          // write ena port b - daqui, do SPI
  assign D_b = {SRin[SZWDB-2:0],mosi}; // concatena dado que vai p/ memoria

dpRAM_256x16                           // inst IP DRPRAM (On Chip Memory)
  DP_U01 (
	.address_a ( Add_a ),                // add_a gerado p/ circ ext ao mod SPI
	.address_b ( Radd_b ),               // Radd_b gerado aqui, pela SPI
	.clock_a   ( clk_a ),                // clock_a p/ uso do circ externo 
	.clock_b   ( sck ),                  // clock_b é o próprio SCK
	.data_a    ( D_a ),                  // data_a do circ ext p/ gravar na RAM
	.data_b    ( D_b ),                  // data_b vem do SPI (aqui SRin)
	.wren_a    ( wen_a ),                // vem do circ externo p/ gravar na RAM
	.wren_b    ( wen_b ),                // gerado aqui, após cada WRD do SPI
	.q_a       ( Q_a ),                  // lido da RAM vai p/ circ ext - s/ uso
	.q_b       ( Q_b ));                 // lido da RAM p/ SPI (sai em SRout) 
  
endmodule

/*  Como instanciar este bloco passando parâmetros:
   
SPI_slv_dpRAM_256x16 #                 // mód SPI_slv_dpRAM_ (params)
  (
  .SZWDA    ( SZWDA ),                 // larg word port-a (1...1024 bits)
  .SZADDA   ( SZADDA ),                // larg bus Address mem port-a
  .SZWDB    ( SZWDB ),                 // larg word port-b:SPI (32,16,8 bits)
  .SZADDB   ( SZADDB ),                // larg bus Address SPI port-b
  .SZCMD    ( SZCMD ),                 // tamanho do reg. de comando "SRcmd"
  .ADD0     ( ADD0 )                   // end inicial da memória
  ) 
  xS_U1                                // nome do componente/instancia   
  (
  .sck      ( lsck ),                  // ligar local sck no "sck" do SPI
  .mosi     ( lmosi ),                 // ligar local mosi no "mosi" do SPI 
  .nss      ( lnss ),                  // ligar local nss no "nss" do SPI 
  .miso     ( lmiso ),                 // ligar local miso no "miso" do SPI 
  .Add_a    ( LAdd_a ),                // bus address da port a
  .clk_a    ( lclk_a ),                // clk da memória na port a 
  .wen_a    ( lwen_a ),                // write enable da mem na port a
  .D_a      ( LD_a ),                  // dado p/ a mem via port a
  .Q_a      ( LQ_a )                   // dado vindo da memória via port a
  );

Atenção ao atribuir endereços! Este módulo tem até 22 bits de endereçamento
*/
