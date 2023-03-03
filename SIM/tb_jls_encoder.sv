
//--------------------------------------------------------------------------------------------------------
// Module  : tb_jls_encoder
// Type    : simulation, top
// Standard: SystemVerilog 2005 (IEEE1800-2005)
// Function: testbench for jls_encoder,
//           load some .pgm files (uncompressed image file), and push them to jls_encoder.
//           get output JPEG-LS stream from jls_encoder, and write them to .jls files (JPEG-LS image file)
//--------------------------------------------------------------------------------------------------------

`timescale 1ps/1ps

`define NEAR 1     // NEAR can be 0~7

`define FILE_NO_FIRST 1   // first input file name is test000.pgm
`define FILE_NO_FINAL 8   // final input file name is test000.pgm


// bubble numbers that insert between pixels
//    when = 0, do not insert bubble
//    when > 0, insert BUBBLE_CONTROL bubbles
//    when < 0, insert random 0~(-BUBBLE_CONTROL) bubbles
`define BUBBLE_CONTROL -2




// the input and output file names' format
`define FILE_NAME_FORMAT  "test%03d"

// input file (uncompressed .pgm file) directory
`define INPUT_PGM_DIR     "./images"

// output file (compressed .jls file) directory
`define OUTPUT_JLS_DIR    "./"


module tb_jls_encoder ();

initial $dumpvars(1, tb_jls_encoder);

// -------------------------------------------------------------------------------------------------------------------
//   generate clock and reset
// -------------------------------------------------------------------------------------------------------------------
reg      rstn = 1'b0;
reg       clk = 1'b0;
always #50000 clk = ~clk;  // 10MHz
initial begin repeat(4) @(posedge clk); rstn<=1'b1; end


// -------------------------------------------------------------------------------------------------------------------
//   signals for jls_encoder_i module
// -------------------------------------------------------------------------------------------------------------------
reg        i_sof = '0;
reg [13:0] i_w = '0;
reg [13:0] i_h = '0;
reg        i_e = '0;
reg [ 7:0] i_x = '0;
wire       o_e;
wire[15:0] o_data;
wire       o_last;



logic [7:0] img [4096*4096];
int w = 0, h = 0;

task automatic load_img(input logic [256*8:1] fname);
    int linelen, depth=0, scanf_num;
    logic [256*8-1:0] line;
    int fp = $fopen(fname, "rb");
    if(fp==0) begin
        $display("*** error: could not open file %s", fname);
        $finish;
    end
    linelen = $fgets(line, fp);
    if(line[8*(linelen-2)+:16] != 16'h5035) begin
        $display("*** error: the first line must be P5");
        $fclose(fp);
        $finish;
    end
    scanf_num = $fgets(line, fp);
    scanf_num = $sscanf(line, "%d%d", w, h);
    if(scanf_num == 1) begin
        scanf_num = $fgets(line, fp);
        scanf_num = $sscanf(line, "%d", h);
    end
    scanf_num = $fgets(line, fp);
    scanf_num = $sscanf(line, "%d", depth);
    if(depth!=255) begin
        $display("*** error: images depth must be 255");
        $fclose(fp);
        $finish;
    end
    for(int i=0; i<h*w; i++)
        img[i] = $fgetc(fp);
    $fclose(fp);
endtask


// -------------------------------------------------------------------------------------------------------------------
//   task: feed image pixels to jls_encoder_i module
//   arguments:
//         w   : image width
//         h   : image height
//         bubble_control : bubble numbers that insert between pixels
//              when = 0, do not insert bubble
//              when > 0, insert bubble_control bubbles
//              when < 0, insert random 0~bubble_control bubbles
// -------------------------------------------------------------------------------------------------------------------
task automatic feed_img(input int bubble_control);
    int num_bubble;
    
    // start feeding a image by assert i_sof for 368 cycles
    repeat(368) begin
        @(posedge clk)
        i_sof <= 1'b1;
        i_w <= w - 1;
        i_h <= h - 1;
        {i_e, i_x} <= '0;
    end
    
    // for all pixels of the image
    for(int i=0; i<h*w; i++) begin
        
        // calculate how many bubbles to insert
        if(bubble_control<0) begin
            num_bubble = $random % (1-bubble_control);
            if(num_bubble<0)
                num_bubble = -num_bubble;
        end else begin
            num_bubble = bubble_control;
        end
        
        // insert bubbles
        repeat(num_bubble) @(posedge clk) {i_sof, i_w, i_h, i_e, i_x} <= '0;
        
        // assert i_e to input a pixel
        @(posedge clk)
        {i_sof, i_w, i_h} <= '0;
        i_e <= 1'b1;
        i_x <= img[i];
    end
    
    // 16 cycles idle between images
    repeat(16) @(posedge clk) {i_sof, i_w, i_h, i_e, i_x} <= '0;
endtask


// -------------------------------------------------------------------------------------------------------------------
//   jls_encoder_i module
// -------------------------------------------------------------------------------------------------------------------
jls_encoder #(
    .NEAR     ( `NEAR     )
) jls_encoder_i (
    .rstn     ( rstn      ),
    .clk      ( clk       ),
    .i_sof    ( i_sof     ),
    .i_w      ( i_w       ),
    .i_h      ( i_h       ),
    .i_e      ( i_e       ),
    .i_x      ( i_x       ),
    .o_e      ( o_e       ),
    .o_data   ( o_data    ),
    .o_last   ( o_last    )
);



// -------------------------------------------------------------------------------------------------------------------
//  read images, feed them to jls_encoder_i module 
// -------------------------------------------------------------------------------------------------------------------
int file_no;    // file number
initial begin
    logic [256*8:1] input_file_name;
    logic [256*8:1] input_file_format;
    $sformat(input_file_format , "%s\\%s.pgm",  `INPUT_PGM_DIR, `FILE_NAME_FORMAT);
    
    while(~rstn) @ (posedge clk);

    for(file_no=`FILE_NO_FIRST; file_no<=`FILE_NO_FINAL; file_no=file_no+1) begin
        $sformat(input_file_name, input_file_format , file_no);

        load_img(input_file_name);
        $display("%s (%5dx%5d)", input_file_name, w, h);

        if( w < 5 || w > 16384 || h < 1 || h > 16383 )         // image size not supported
            $display("  *** image size not supported ***");
        else
            feed_img(`BUBBLE_CONTROL);
    end
    
    repeat(100) @(posedge clk);

    $finish;
end


// -------------------------------------------------------------------------------------------------------------------
//  write output stream to .jls files 
// -------------------------------------------------------------------------------------------------------------------
logic [256*8:1] output_file_format;
initial $sformat(output_file_format, "%s\\%s.jls", `OUTPUT_JLS_DIR, `FILE_NAME_FORMAT);
logic [256*8:1] output_file_name;
int opened = 0;
int jls_file = 0;

always @ (posedge clk)
    if(o_e) begin
        // the first data of an output stream, open a new file.
        if(opened == 0) begin
            opened = 1;
            $sformat(output_file_name, output_file_format, file_no);
            jls_file = $fopen(output_file_name , "wb");
        end
        
        // write data to file.
        if(opened != 0 && jls_file != 0)
            $fwrite(jls_file, "%c%c", o_data[15:8], o_data[7:0]);
        
        // if it is the last data of an output stream, close the file.
        if(o_last) begin
            opened = 0;
            $fclose(jls_file);
        end
    end

endmodule
