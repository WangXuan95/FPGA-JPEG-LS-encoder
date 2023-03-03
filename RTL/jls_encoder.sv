
//--------------------------------------------------------------------------------------------------------
// Module  : jls_encoder
// Type    : synthesizable, IP's top
// Standard: SystemVerilog 2005 (IEEE1800-2005)
// Function: JPEG-LS image compressor
//--------------------------------------------------------------------------------------------------------

module jls_encoder #(
    parameter [2:0] NEAR = 3'd1
) (
    input  wire        rstn,
    input  wire        clk,
    input  wire        i_sof,   // start of image
    input  wire [13:0] i_w,     // image_width-1 , range: 4~16383, that is, image_width range: 5~16384
    input  wire [13:0] i_h,     // image_height-1, range: 0~16382, that is, image_height range: 1~16383
    input  wire        i_e,     // input pixel enable
    input  wire [ 7:0] i_x,     // input pixel
    output wire        o_e,     // output data enable
    output wire [15:0] o_data,  // output data
    output wire        o_last   // indicate the last output data of a image
);

//---------------------------------------------------------------------------------------------------------------------------
// local parameters
//---------------------------------------------------------------------------------------------------------------------------
wire [3:0] P_QBPPS [8];
assign P_QBPPS[0] = 4'd8;
assign P_QBPPS[1] = 4'd7;
assign P_QBPPS[2] = 4'd6;
assign P_QBPPS[3] = 4'd6;
assign P_QBPPS[4] = 4'd5;
assign P_QBPPS[5] = 4'd5;
assign P_QBPPS[6] = 4'd5;
assign P_QBPPS[7] = 4'd5;

localparam logic               P_LOSSY     = NEAR != '0;
localparam logic  signed [8:0] P_NEAR      = $signed({6'd0, NEAR});
localparam logic  signed [8:0] P_T1        = $signed(9'd3) + $signed(9'd3) * P_NEAR;
localparam logic  signed [8:0] P_T2        = $signed(9'd7) + $signed(9'd5) * P_NEAR;
localparam logic  signed [8:0] P_T3        = $signed(9'd21)+ $signed(9'd7) * P_NEAR;
localparam logic  signed [9:0] P_QUANT     = {P_NEAR, 1'b1};
localparam logic  signed [9:0] P_QBETA     = $signed(10'd256 + {5'd0,NEAR,2'd0}) / P_QUANT;
localparam logic  signed [9:0] P_QBETAHALF = (P_QBETA+$signed(10'd1)) / $signed(10'd2);
wire        [3:0] P_QBPP      = P_QBPPS[NEAR];
wire        [4:0] P_LIMIT     = 5'd31 - {1'b0, P_QBPP};
localparam logic        [12:0] P_AINIT     = (NEAR=='0) ? 13'd4 : 13'd2;

wire [3:0] J [32];
assign J[ 0] = 4'd0;
assign J[ 1] = 4'd0;
assign J[ 2] = 4'd0;
assign J[ 3] = 4'd0;
assign J[ 4] = 4'd1;
assign J[ 5] = 4'd1;
assign J[ 6] = 4'd1;
assign J[ 7] = 4'd1;
assign J[ 8] = 4'd2;
assign J[ 9] = 4'd2;
assign J[10] = 4'd2;
assign J[11] = 4'd2;
assign J[12] = 4'd3;
assign J[13] = 4'd3;
assign J[14] = 4'd3;
assign J[15] = 4'd3;
assign J[16] = 4'd4;
assign J[17] = 4'd4;
assign J[18] = 4'd5;
assign J[19] = 4'd5;
assign J[20] = 4'd6;
assign J[21] = 4'd6;
assign J[22] = 4'd7;
assign J[23] = 4'd7;
assign J[24] = 4'd8;
assign J[25] = 4'd9;
assign J[26] = 4'd10;
assign J[27] = 4'd11;
assign J[28] = 4'd12;
assign J[29] = 4'd13;
assign J[30] = 4'd14;
assign J[31] = 4'd15;



//---------------------------------------------------------------------------------------------------------------------------
// function: is_near
//---------------------------------------------------------------------------------------------------------------------------
function automatic logic func_is_near(input [7:0] x1, input [7:0] x2);
    logic signed [8:0] ex1, ex2;
    ex1 = $signed({1'b0,x1});
    ex2 = $signed({1'b0,x2});
    return ex1 - ex2 <= P_NEAR && ex2 - ex1 <= P_NEAR;
endfunction


//---------------------------------------------------------------------------------------------------------------------------
// function: predictor (get_px)
//---------------------------------------------------------------------------------------------------------------------------
function automatic logic [7:0] func_predictor(input [7:0] a, input [7:0] b, input [7:0] c);
    if( c>=a && c>=b )
        return a>b ? b : a;
    else if( c<=a && c<=b )
        return a>b ? a : b;
    else
        return a - c + b;
endfunction


//---------------------------------------------------------------------------------------------------------------------------
// function: q_quantize
//---------------------------------------------------------------------------------------------------------------------------
function automatic logic signed [3:0] func_q_quantize(input [7:0] x1, input [7:0] x2);
    logic signed [8:0] delta;
    delta = $signed({1'b0,x1}) - $signed({1'b0,x2});
    if     (delta <= -P_T3 )
        return -$signed(4'd4);
    else if(delta <= -P_T2 )
        return -$signed(4'd3);
    else if(delta <= -P_T1 )
        return -$signed(4'd2);
    else if(delta <  -P_NEAR )
        return -$signed(4'd1);
    else if(delta <=  P_NEAR )
        return  $signed(4'd0);
    else if(delta <   P_T1 )
        return  $signed(4'd1);
    else if(delta <   P_T2 )
        return  $signed(4'd2);
    else if(delta <   P_T3 )
        return  $signed(4'd3);
    else
        return  $signed(4'd4);
endfunction


//---------------------------------------------------------------------------------------------------------------------------
// function: get_q (part 1), qp1 = 81*Q(d-b) + 9*Q(b-c)
//---------------------------------------------------------------------------------------------------------------------------
function automatic logic signed [9:0] func_get_qp1(input [7:0] c, input [7:0] b, input [7:0] d);
    return $signed(10'd81) * func_q_quantize(d,b) + $signed(10'd9) * func_q_quantize(b,c);
endfunction


//---------------------------------------------------------------------------------------------------------------------------
// function: get_q (part 2), get sign(qs) and abs(qs), where qs = qp1 + Q(c-a)
//---------------------------------------------------------------------------------------------------------------------------
function automatic logic [9:0] func_get_q(input signed [9:0] qp1, input [7:0] c, input [7:0] a);
    logic signed [9:0] qs;
    logic              s;
    logic        [8:0] q;
    qs = qp1 + func_q_quantize(c,a);
    s = qs[9];
    q = s ? (~qs[8:0]+9'd1) : qs[8:0];
    return {s, q};
endfunction


//---------------------------------------------------------------------------------------------------------------------------
// function: clip
//---------------------------------------------------------------------------------------------------------------------------
function automatic logic [7:0] func_clip(input signed [9:0] val);
    if( val > $signed(10'd255) )
        return 8'd255;
    else if( val < $signed(10'd0) )
        return 8'd0;
    else
        return val[7:0];
endfunction


//---------------------------------------------------------------------------------------------------------------------------
// function: errval_quantize
//---------------------------------------------------------------------------------------------------------------------------
function automatic logic signed [9:0] func_errval_quantize(input signed [9:0] err);
    if(err[9])
        return -( (P_NEAR - err) / P_QUANT );
    else
        return    (P_NEAR + err) / P_QUANT;
endfunction


//---------------------------------------------------------------------------------------------------------------------------
// function: modrange
//---------------------------------------------------------------------------------------------------------------------------
function automatic logic signed [9:0] func_modrange(input signed [9:0] val);
    logic signed [9:0] new_val;
    new_val = val;
    if( new_val[9] )
        new_val += P_QBETA;
    if( new_val >= P_QBETAHALF )
        new_val -= P_QBETA;
    return new_val;
endfunction


//---------------------------------------------------------------------------------------------------------------------------
// function: get k
//---------------------------------------------------------------------------------------------------------------------------
function automatic logic [3:0] func_get_k(input [12:0] A, input [6:0] N, input rt);
    logic [18:0] Nt, At;
    logic [ 3:0] k;
    Nt = {12'h0, N};
    At = { 6'h0, A};
    k = 4'd0;
    if(rt)
        At += {13'd0, N[6:1]};
    for(int ii=0; ii<13; ii++)
        if((Nt<<ii) < At)
            k++;
    return k;
endfunction


//---------------------------------------------------------------------------------------------------------------------------
// function: B update for run mode
//---------------------------------------------------------------------------------------------------------------------------
function automatic logic [6:0] B_update(input reset, input [6:0] B, input errm0);
    B_update = B;
    if(errm0)
        B_update ++;
    if(reset)
        B_update >>>= 1;
endfunction


//---------------------------------------------------------------------------------------------------------------------------
// function: C, B update for regular mode
//---------------------------------------------------------------------------------------------------------------------------
function automatic logic [14:0] C_B_update(input reset, input [6:0] N, input signed [7:0] C, input signed [6:0] B, input signed [9:0] err);
    logic signed [9:0] Bt;
    logic signed [7:0] Ct;
    Bt = B;
    Ct = C;
    Bt += err * P_QUANT;
    if(reset)
        Bt >>>= 1;
    if( Bt <= -$signed({3'd0,N}) ) begin
        Bt += $signed({3'd0,N});
        if( Bt <= -$signed({3'd0,N}) )
            Bt = -$signed({3'd0,N}-10'd1);
        if( Ct != $signed(8'd128) )
            Ct--;
    end else if( Bt > $signed(10'd0) ) begin
        Bt -= $signed({3'd0,N});
        if( Bt > $signed(10'd0) )
            Bt = $signed(10'd0);
        if( Ct != $signed(8'd127) )
            Ct++;
    end
    return {Ct, Bt[6:0]};
endfunction


//---------------------------------------------------------------------------------------------------------------------------
// function: A update
//---------------------------------------------------------------------------------------------------------------------------
function automatic logic [12:0] A_update(input reset, input [12:0] A, input [9:0] inc);
    A_update = A + {3'd0, inc};
    if(reset)
        A_update >>>= 1;
endfunction


//-------------------------------------------------------------------------------------------------------------------
// context memorys
//-------------------------------------------------------------------------------------------------------------------
reg        [ 5:0] Nram [366];
reg        [12:0] Aram [366];
reg signed [ 6:0] Bram [366];
reg signed [ 7:0] Cram [1:364];


//-------------------------------------------------------------------------------------------------------------------
// pipeline stage a: generate ii, jj
//-------------------------------------------------------------------------------------------------------------------
reg        a_sof;
reg        a_e;
reg [ 7:0] a_x;
reg [13:0] a_w;
reg [13:0] a_h;
reg [13:0] a_wl;
reg [13:0] a_hl;
reg [13:0] a_ii;
reg [14:0] a_jj;

always @ (posedge clk)
    if(~rstn) begin
        {a_sof, a_e, a_x, a_w, a_h, a_wl, a_hl, a_ii, a_jj} <= '0;
    end else begin
        a_sof <= i_sof;
        a_e <= i_e;
        a_x <= i_x;
        a_w <= i_w;
        a_h <= i_h;
        if(a_sof) begin
            a_wl <= (a_w<14'd4 ? 14'd4 : a_w);
            a_hl <= a_h;
            a_ii <= '0;
            a_jj <= '0;
        end else if(a_e) begin
            if(a_ii < a_wl)
                a_ii <= a_ii + 14'd1;
            else begin
                a_ii <= '0;
                if(a_jj <= {1'b0,a_hl})
                    a_jj <= a_jj + 15'd1;
            end
        end
    end


//-------------------------------------------------------------------------------------------------------------------
// pipeline stage b: generate fc, lc, nfr
//-------------------------------------------------------------------------------------------------------------------
reg        b_sof;
reg        b_e;
reg        b_fc;
reg        b_lc;
reg        b_fr;
reg        b_eof;
reg [13:0] b_ii;
reg [ 7:0] b_x;

always @ (posedge clk) begin
    b_sof <= a_sof & rstn;
    if(~rstn | a_sof) begin
        {b_e, b_fc, b_lc, b_fr, b_eof, b_ii, b_x} <= '0;
    end else begin
        b_e <= a_e & (a_jj <= {1'b0,a_hl});
        b_fc <= a_e & (a_ii == '0);
        b_lc <= a_e & (a_ii == a_wl);
        b_fr <= a_e & (a_jj == '0);
        b_eof <= a_jj > {1'b0,a_hl};
        b_ii <= a_ii;
        b_x <= a_x;
    end
end


//-------------------------------------------------------------------------------------------------------------------
// pipeline stage c: maintain linebuffer, generate context pixels: b, c, d , where d is not valid in case of fr and lc
//-------------------------------------------------------------------------------------------------------------------
reg        c_sof;
reg        c_e;
reg        c_fc;
reg        c_lc;
reg        c_fr;
reg        c_eof;
reg [13:0] c_ii;
reg [ 7:0] c_x;
reg [ 7:0] c_b;
reg [ 7:0] c_bt;
reg [ 7:0] c_c;
reg [ 7:0] c_d;

always @ (posedge clk) begin
    c_sof <= b_sof & rstn;
    if(~rstn | b_sof) begin
        {c_e,c_fc,c_lc,c_fr,c_eof,c_ii,c_x,c_b,c_bt,c_c} <= '0;
    end else begin
        c_e <= b_e;
        c_fc <= b_fc;
        c_lc <= b_lc;
        c_fr <= b_fr;
        c_eof <= b_eof;
        c_ii <= b_ii;
        if(b_e) begin
            c_x <= b_x;
            c_b <= b_fr ? '0 : c_d;
            if(b_fr) begin
                c_bt <= '0;
                c_c <= '0;
            end else if(b_fc) begin
                c_bt <= c_d;
                c_c <= c_bt;
            end else
                c_c <= c_b;
        end
    end
end


//-------------------------------------------------------------------------------------------------------------------
// pipeline stage d: fix context pixel d (locally) in case fr and lc, get q part-1 (qp1)
//-------------------------------------------------------------------------------------------------------------------
reg        d_sof;
reg        d_e;
reg        d_fc;
reg        d_lc;
reg        d_eof;
reg [13:0] d_ii;
reg [ 7:0] d_x;
reg [ 7:0] d_b;
reg [ 7:0] d_c;
reg signed [9:0] d_qp1;

always @ (posedge clk) begin
    d_sof <= c_sof & rstn;
    if(~rstn | c_sof) begin
        {d_e, d_fc, d_lc, d_eof, d_ii, d_x, d_b, d_c, d_qp1} <= '0;
    end else begin
        logic [7:0] d;
        d_e <= c_e;
        d_fc <= c_fc;
        d_lc <= c_lc;
        d_eof <= c_eof;
        d_ii <= c_ii;
        d_x <= c_x;
        d_b <= c_b;
        d_c <= c_c;
        d = c_fr ? '0 : (c_lc ? c_b : c_d);
        d_qp1 <= func_get_qp1(c_c, c_b, d);
    end
end


//-------------------------------------------------------------------------------------------------------------------
// pipeline stage e: get errval, Rx reconstruct loop, N, B, C update
//-------------------------------------------------------------------------------------------------------------------
reg              e_sof;
reg              e_e;
reg              e_fc;
reg              e_lc;
reg              e_eof;
reg       [13:0] e_ii;
reg              e_runi;
reg              e_rune;
reg              e_2BleN;
reg        [7:0] e_x;
reg        [8:0] e_q;
reg              e_rt;
reg signed [9:0] e_err;
reg        [6:0] e_No;
reg              e_write_C, e_write_en;
reg        [5:0] e_Nn;
reg signed [7:0] e_Cn;
reg signed [6:0] e_Bn;

always @ (posedge clk) begin
    e_sof <= d_sof & rstn;
    e_2BleN <= 1'b0;
    {e_write_C, e_Cn, e_write_en, e_Bn, e_Nn} <= '0;
    if(~rstn | d_sof) begin
        {e_e, e_fc, e_lc, e_eof, e_ii, e_runi, e_rune, e_x, e_q, e_rt, e_err, e_No} <= '0;
    end else begin
        logic        [7:0] a;
        logic              s;
        logic        [8:0] q;
        logic              rt;
        logic              runi;
        logic              rune;
        logic signed [7:0] Co;
        logic        [6:0] No, Nn;
        logic signed [6:0] Bo;
        logic signed [9:0] px;
        logic signed [9:0] err;
        a = d_fc ? d_b : e_x;
        rt = 1'b0;
        rune = 1'b0;
        No = '0;
        err = '0;
        {s, q} = func_get_q(d_qp1, d_c, a);
        Co = (e_write_C & e_q==q) ? e_Cn : Cram[q];
        runi = ~d_fc & e_runi | (q == 9'd0);
        if(runi) begin
            runi = func_is_near(d_x, a);
            rune = ~runi;
        end
        if(d_e) begin
            if(runi) begin
                e_x <= P_LOSSY ? a : d_x;
            end else begin
                if(rune) begin
                    rt = func_is_near(d_b, a);
                    s = {1'b0,a} > ({1'b0,d_b} + {6'd0,NEAR}) ? 1'b1 : 1'b0;
                    q = rt ? 9'd365 : 9'd0;
                    px = rt ? a : d_b;
                end else begin
                    px[9:8] = 2'b00;
                    px[7:0] = func_clip( $signed({2'h0, func_predictor(a,d_b,d_c)}) + ( s ? -$signed({Co[7],Co[7],Co}) : $signed({Co[7],Co[7],Co}) ) );
                end
                err = s ? px - $signed({2'd0, d_x}) : $signed({2'd0, d_x}) - px;
                err = func_errval_quantize(err);
                e_x <= P_LOSSY ? func_clip( px + ( s ? -(P_QUANT*err) : P_QUANT*err ) ) : d_x;
                err = func_modrange(err);
                No = ((e_write_en & e_q==q) ? e_Nn : Nram[q]) + 7'd1;
                Nn = No;
                if(No[6]) Nn >>>= 1;
                e_Nn <= Nn[5:0];
                Bo = (e_write_en & e_q==q) ? e_Bn : Bram[q];
                e_write_en <= 1'b1;
                if(rune) begin
                    e_Bn <= B_update(No[6], Bo, err<$signed(10'd0));
                    e_2BleN <= $signed({Bo,1'b0}) < $signed({1'b0,No});
                end else begin
                    e_write_C <= 1'b1;
                    {e_Cn, e_Bn} <= C_B_update(No[6], Nn+7'd1, Co, Bo, err);
                    e_2BleN <= $signed({Bo,1'b0}) <= -$signed({1'b0,No});
                end
            end
            e_runi <= runi;
        end
        e_e <= d_e;
        e_fc <= d_fc;
        e_lc <= d_lc;
        e_eof <= d_eof;
        e_ii <= d_ii;
        e_rune <= d_e & rune;
        e_q <= q;
        e_rt <= rt;
        e_err <= err;
        e_No <= No;
    end
end


//-------------------------------------------------------------------------------------------------------------------
// pipeline stage f: write Cram, Bram, Nram
//-------------------------------------------------------------------------------------------------------------------
reg [8:0] NBC_init_addr;
always @ (posedge clk)
    NBC_init_addr <= e_sof ? NBC_init_addr + (NBC_init_addr < 9'd366 ? 9'd1 : 9'd0) : 9'd0;

always @ (posedge clk)
    if(e_sof | e_write_en) begin
        Nram[e_write_en ? e_q : NBC_init_addr] <= e_Nn;
        Bram[e_write_en ? e_q : NBC_init_addr] <= e_Bn;
    end

always @ (posedge clk)
    if(e_sof | e_write_C) begin
        Cram[e_write_C ? e_q : NBC_init_addr] <= e_Cn;
    end




//-------------------------------------------------------------------------------------------------------------------
// pipeline stage ef: read Aram, buffer registers
//-------------------------------------------------------------------------------------------------------------------
reg              ef_sof;
reg              ef_e;
reg              ef_fc;
reg              ef_lc;
reg              ef_eof;
reg              ef_runi;
reg              ef_rune;
reg              ef_2BleN;
reg        [8:0] ef_q;
reg              ef_rt;
reg signed [9:0] ef_err;
reg        [6:0] ef_No;
reg       [12:0] ef_Ao;
reg              ef_write_en;

always @ (posedge clk) begin
    ef_sof <= e_sof & rstn;
    if(~rstn | e_sof) begin
        {ef_e, ef_fc, ef_lc, ef_eof, ef_runi, ef_rune, ef_2BleN, ef_q, ef_rt, ef_err, ef_No, ef_write_en} <= '0;
    end else begin
        ef_e <= e_e;
        ef_fc <= e_fc;
        ef_lc <= e_lc;
        ef_eof <= e_eof;
        ef_runi <= e_runi & e_e;
        ef_rune <= e_rune;
        ef_2BleN <= e_2BleN;
        ef_q <= e_q;
        ef_rt <= e_rt;
        ef_err <= e_err;
        ef_No <= e_No;
        ef_write_en <= e_write_en;
    end
end

always @ (posedge clk)
    ef_Ao <= Aram[e_q];



//-------------------------------------------------------------------------------------------------------------------
// pipeline stage f: process run, calcuate merrval and k, A update
//-------------------------------------------------------------------------------------------------------------------
reg               f_sof;
reg               f_e;
reg               f_eof;
reg               f_runi;
reg               f_rune;
reg        [ 9:0] f_merr;
reg        [ 3:0] f_k;
reg        [15:0] f_rc;
reg        [ 4:0] f_ri;
reg        [ 1:0] f_on;
reg        [15:0] f_cb;
reg        [ 4:0] f_cn;    // in range of 0~16
reg        [ 4:0] f_limit;
reg  [8:0] f_q;
reg        f_write_en;
reg [12:0] f_An;

reg  [8:0] g_q;
reg        g_write_en;
reg [12:0] g_An;
always @ (posedge clk)
    if(~rstn | f_sof)
        {g_q, g_write_en, g_An} <= '0;
    else
        {g_q, g_write_en, g_An} <= {f_q, f_write_en, f_An};


always @ (posedge clk) begin
    f_sof <= ef_sof & rstn;
    f_limit <= P_LIMIT;
    f_An <= P_AINIT;
    if(~rstn | ef_sof) begin
        {f_e, f_eof, f_runi, f_rune, f_merr, f_k, f_rc, f_ri, f_on, f_cb, f_cn, f_q, f_write_en} <= '0;
    end else begin
        logic [ 1:0] on;
        logic [15:0] rc;
        logic [ 4:0] ri;
        logic [12:0] Ao;
        logic [ 3:0] k;
        logic [ 9:0] abserr;
        logic [ 9:0] merr, Ainc;
        logic        map;
        on = '0;
        rc = (ef_fc|~ef_runi) ? '0 : f_rc;
        ri = f_ri;
        Ao = (f_write_en & f_q==ef_q) ? f_An : (g_write_en & g_q==ef_q) ? g_An : ef_Ao;
        abserr = ef_err<$signed(10'd0) ? $unsigned(-ef_err) : $unsigned(ef_err);
        merr='0;
        Ainc='0;
        f_write_en <= ef_write_en;
        k = func_get_k(Ao, ef_No, ef_rt);
        f_cb <= ef_fc ? '0 : f_rc;
        f_cn <= {1'b0,J[ri]} + 5'd1;
        if(ef_runi) begin
            rc ++;
            if(rc >= (16'd1<<J[ri])) begin
                on++;
                rc -= (16'd1<<J[ri]);
                if(ri < 5'd31) ri ++;
            end
            if(ef_lc & (rc > 16'd0))
                on++;
        end else if(ef_rune) begin
            f_limit <= P_LIMIT - 5'd1 - {1'b0,J[ri]};
            if(ri > '0) ri --;
            map = ~( (ef_err=='0) | ( (ef_err>$signed(10'd0)) ^ (k==4'd0 & ef_2BleN) ) );
            merr = (abserr<<1) - {9'd0,ef_rt} - {9'd0,map};
            Ainc = ((merr + {9'd0,~ef_rt}) >> 1);
        end else begin
            map = (~P_LOSSY) & (k==4'd0) & ef_2BleN;
            if(ef_err < $signed(10'd0))
                merr = (abserr<<1) - 10'd1 - {9'd0,map};
            else
                merr = (abserr<<1) + {9'd0,map};
            Ainc = (ef_err < $signed(10'd0)) ? $unsigned(-ef_err) : $unsigned(ef_err);
        end
        if(ef_e) begin
            f_rc <= rc;
            f_ri <= ri;
        end
        f_An <= A_update(ef_No[6], Ao, Ainc);
        f_e <= ef_e;
        f_eof <= ef_eof;
        f_runi <= ef_runi;
        f_rune <= ef_rune;
        f_merr <= merr;
        f_k <= k;
        f_on <= on;
        f_q <= ef_q;
    end
end


//-------------------------------------------------------------------------------------------------------------------
// pipeline stage g: write Aram
//-------------------------------------------------------------------------------------------------------------------
reg [8:0] A_init_addr;
always @ (posedge clk)
    A_init_addr <= f_sof ? A_init_addr + (A_init_addr < 9'd366 ? 9'd1 : 9'd0) : 9'd0;
    
always @ (posedge clk)
    if(f_sof | f_write_en)
        Aram[f_write_en ? f_q : A_init_addr] <= f_An;


//-------------------------------------------------------------------------------------------------------------------
// pipeline stage g: golomb coding parser
//-------------------------------------------------------------------------------------------------------------------
reg         g_sof;
reg         g_e;
reg         g_eof;
reg         g_runi;
reg  [ 1:0] g_on;   // in range of 0~2
reg  [15:0] g_cb;   
reg  [ 4:0] g_cn;   // in range of 0~16
reg  [ 4:0] g_zn;   // in range of 0~27
reg  [ 9:0] g_db;
reg  [ 3:0] g_dn;   // in range of 0~13

always @ (posedge clk) begin
    g_sof <= f_sof & rstn;
    if(~rstn | f_sof) begin
        {g_e, g_eof, g_runi, g_on, g_cb, g_cn, g_zn, g_db, g_dn} <= '0;
    end else begin
        logic [9:0] merr_sk;
        merr_sk = f_merr >> f_k;
        g_e <= f_e;
        g_eof <= f_eof;
        g_runi <= f_runi;
        g_on <= f_on;
        g_cb <= f_rune ? f_cb : '0;
        g_cn <= f_rune ? f_cn : '0;
        if(merr_sk < f_limit) begin 
            g_zn <= merr_sk[4:0];
            g_db <= f_merr & ~(10'h3ff<<f_k);
            g_dn <= f_k;
        end else begin
            g_zn <= f_limit[4:0];
            g_db <= (f_merr-10'd1) & ~(10'h3ff<<P_QBPP);
            g_dn <= P_QBPP;
        end
    end
end


//-------------------------------------------------------------------------------------------------------------------
// pipeline stage h: golomb coding bits merge
//-------------------------------------------------------------------------------------------------------------------
reg        h_sof;
reg        h_eof;
reg [56:0] h_bb;  // max 57 bits
reg [ 5:0] h_bn;  // in range of 0~57

always @ (posedge clk) begin
    h_sof <= g_sof & rstn;
    {h_bb, h_bn} <= '0;
    if(~rstn | g_sof) begin
        h_eof <= 1'b0;
    end else begin
        h_eof <= g_eof;
        if(g_e) begin
            if(g_runi) begin
                if(g_on==2'd1)
                    h_bb[56] <= 1'b1;
                else if(g_on==2'd2)
                    h_bb[56:55] <= 2'b11;
                h_bn <= {4'h0, g_on};
            end else begin
                h_bb <= ( {41'h0,g_cb} << (6'd57-g_cn) ) | ( 57'd1 << (6'd56-g_cn-g_zn) ) | ( {47'h0,g_db} << (6'd56-g_cn-g_zn-g_dn) );
                h_bn <= {1'b0,g_cn} + {1'b0,g_zn} + 6'd1 + {2'b0,g_dn};
            end
        end
    end
end


//-------------------------------------------------------------------------------------------------------------------
// pipeline stage j: jls stream generate
//-------------------------------------------------------------------------------------------------------------------
reg        j_sof;
reg        j_eof;
reg        j_e;
reg [15:0] j_data;
reg[247:0] j_bbuf;
reg [ 7:0] j_bcnt;

always @ (posedge clk) begin
    j_sof <= h_sof & rstn;
    {j_e, j_data} <= '0;
    if(~rstn | h_sof) begin
        {j_eof, j_bbuf, j_bcnt} <= '0;
    end else begin
        logic [247:0] bbuf;
        logic [  7:0] bcnt;
        bbuf = j_bbuf | ({h_bb,191'h0} >> j_bcnt);
        bcnt = j_bcnt + {2'd0,h_bn};
        if(bcnt >= 8'd16) begin
            j_e <= 1'b1;
            j_data[15:8] <= bbuf[247:240];
            if(bbuf[247:240] == '1) begin
                bbuf = {1'h0, bbuf[239:0], 7'h0};
                bcnt -= 8'd7;
            end else begin
                bbuf = {      bbuf[239:0], 8'h0};
                bcnt -= 8'd8;
            end
            j_data[ 7:0] <= bbuf[247:240];
            if(bbuf[247:240] == '1) begin
                bbuf = {1'h0, bbuf[239:0], 7'h0};
                bcnt -= 8'd7;
            end else begin
                bbuf = {      bbuf[239:0], 8'h0};
                bcnt -= 8'd8;
            end
        end else if(h_eof && bcnt > 8'd0) begin
            j_e <= 1'b1;
            j_data[15:8] <= bbuf[247:240];
            if(bbuf[247:240] == '1)
                j_data[ 7:0] <= {1'b0,bbuf[239:233]};
            else
                j_data[ 7:0] <= bbuf[239:232];
            bbuf = '0;
            bcnt = 8'd0;
        end
        j_bbuf <= bbuf;
        j_bcnt <= bcnt;
        j_eof <= h_eof;
    end
end


//-------------------------------------------------------------------------------------------------------------------
// make .jls file header and footer
//-------------------------------------------------------------------------------------------------------------------
reg [15:0] jls_wl, jls_hl;
wire[15:0] jls_header [13];
assign jls_header[0] = 16'hFFD8;
assign jls_header[1] = 16'h00FF;
assign jls_header[2] = 16'hF700;
assign jls_header[3] = 16'h0B08;
assign jls_header[4] = jls_hl;
assign jls_header[5] = jls_wl;
assign jls_header[6] = 16'h0101;
assign jls_header[7] = 16'h1100;
assign jls_header[8] = 16'hFFDA;
assign jls_header[9] = 16'h0008;
assign jls_header[10]= 16'h0101;
assign jls_header[11]= {13'b0,NEAR};
assign jls_header[12]= 16'h0000;
wire[15:0] jls_footer = 16'hFFD9;
always @ (posedge clk)
    if(~rstn) begin
        jls_wl <= '0;
        jls_hl <= '0;
    end else begin
        jls_wl <= {2'd0,a_wl} + 16'd1;
        jls_hl <= {2'd0,a_hl} + 16'd1;
    end


//-------------------------------------------------------------------------------------------------------------------
// pipeline stage k: add .jls file header and footer
//-------------------------------------------------------------------------------------------------------------------
reg  [3:0] k_header_i;
reg        k_footer_i;
reg        k_last;
reg        k_e;
reg [15:0] k_data;

always @ (posedge clk) begin
    k_last <= 1'b0;
    k_e <= 1'b0;
    k_data <= '0;
    if(j_sof) begin
        k_footer_i <= '0;
        if(k_header_i < 4'd13) begin
            k_e <= 1'b1;
            k_data <= jls_header[k_header_i];
            k_header_i <= k_header_i + 4'd1;
        end
    end else if(j_e) begin
        k_header_i <= '0;
        k_footer_i <= '0;
        k_e <= 1'b1;
        k_data <= j_data;
    end else if(j_eof) begin
        k_header_i <= '0;
        k_footer_i <= 1'b1;
        if(~k_footer_i) begin
            k_last <= 1'b1;
            k_e <= 1'b1;
            k_data <= jls_footer;
        end
    end else begin
        k_header_i <= '0;
        k_footer_i <= '0;
    end
end


//-------------------------------------------------------------------------------------------------------------------
// linebuffer for context pixels
//-------------------------------------------------------------------------------------------------------------------
reg [7:0] linebuffer [1<<14];
always @ (posedge clk)  // line buffer read
    c_d <= linebuffer[a_ii];
always @ (posedge clk)  // line buffer write
    if(e_e) linebuffer[e_ii] <= e_x;


//-------------------------------------------------------------------------------------------------------------------
// output signal
//-------------------------------------------------------------------------------------------------------------------
assign o_last = k_last;
assign o_e = k_e;
assign o_data = k_data;


endmodule

