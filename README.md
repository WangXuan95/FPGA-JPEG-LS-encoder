![语言](https://img.shields.io/badge/语言-verilog_(IEEE1364_2001)-9A90FD.svg) ![仿真](https://img.shields.io/badge/仿真-iverilog-green.svg) ![部署](https://img.shields.io/badge/部署-quartus-blue.svg) ![部署](https://img.shields.io/badge/部署-vivado-FF1010.svg)

[English](#en) | [中文](#cn)

　

<span id="en">FPGA JPEG-LS image compressor</span>
===========================

**FPGA** based streaming **JPEG-LS** image compressor, features:

* Pure Verilog design, compatible with various FPGA platforms.
* For compressing **8bit** grayscale images.
* Support **lossless mode**, i.e. NEAR=0 .
* Support **lossy mode**, NEAR=1~7 adjustable.
* The value range of image width is [5,16384], and the value range of height is [1,16384].
* Simple streaming input and output.

　

# Background

**JPEG-LS** (**JLS**) is a lossless/lossy image compression algorithm which has the best lossless compression ratio compared to PNG, Lossless-JPEG2000, Lossless-WEBP, Lossless-HEIF, etc. **JPEG-LS** uses the maximum difference between the pixels before and after compression (**NEAR** value) to control distortion, **NEAR=0** is the lossless mode; **NEAR>0** is the lossy mode, the larger the **NEAR**, the greater the distortion and the greater the compression ratio. The file suffix name for **JPEG-LS** compressed image is .**jls** .

JPEG-LS has two generations:

- JPEG-LS baseline (ITU-T T.87): JPEG-LS refers to the JPEG-LS baseline by default. **This repo implements the encoder of JPEG-LS baseline**. If you are interested in the software version of JPEG-LS baseline encoder, see https://github.com/WangXuan95/JPEG-LS (C language)
- JPEG-LS extension (ITU-T T.870): Its compression ratio is higher than JPEG-LS baseline, but it is very rarely (even no code can be found online). **This repo is not about JPEG-LS extension**. However, I have a C implemented of JPEG-LS extension, see https://github.com/WangXuan95/JPEG-LS_extension

　

# Module Usage

[**jls_encoder.sv**](./RTL/jls_encoder.sv) in the [RTL](./RTL) directory is a JPEG-LS compression module that can be call by the FPGA users, which inputs image raw pixels and outputs a JPEG-LS compressed stream.

## Module parameter

**jls_encoder** has a parameter:

```verilog
parameter logic [2:0] NEAR
```

which determines the NEAR value of JPEG-LS algorithm. When the value is 3'd0, it works in lossless mode; when the value is 3'd1~3'd7, it works in lossy mode.

## Module Interface

The input and output signals of **jls_encoder** are described in the following table.

| Signal |      Name      | direction | width | description                                                  |
| :----: | :------------: | :-------: | :---: | :----------------------------------------------------------- |
|  rstn  |     reset      |    in     | 1bit  | When the clock rises, if rstn=0, the module is reset, and rstn=1 in normal use. |
|  clk   |     clock      |    in     | 1bit  | All signals should be aligned on the rising edge of clk.     |
| i_sof  | start of frame |    in     | 1bit  | When a new image needs to be input, keep i_sof=1 for at least 368 clock cycles. |
|  i_w   |    width-1     |    in     | 14bit | For example, if the image width is 1920, i_w should be set to 14'd1919. Needs to remain valid when i_sof=1. |
|  i_h   |    height-1    |    in     | 14bit | For example, if the image width is 1080, i_h should be set to 14'd1079. Needs to remain valid when i_sof=1. |
|  i_e   |  input valid   |    in     | 1bit  | i_e=1 indicates a valid input pixel is on i_x                |
|  i_x   |  input pixel   |    in     | 8bit  | The pixel value range is 8'd0 ~ 8'd255 .                     |
|  o_e   |  output valid  |    out    | 1bit  | o_e=1 indicates a valid data is on o_data.                   |
| o_data |  output data   |    out    | 16bit | Big endian, odata[15:8] online; odata[7:0] after.            |
| o_last |  output last   |    out    | 1bit  | o_last=1, indicate that this is the last data of the output stream of an image. |

> Note：i_w cannot less than 14'd4 。

## Input pixels

The operation flow of  **jls_encoder** module is:

1. **Reset** (optional): Set `rstn=0` for at least **1 cycle** to reset, and then keep `rstn=1` during normal operation. In fact, it is not necessary to reset.
2. **Start**: keep `i_sof=1` **at least 368 cycles**, while inputting the width and height of the image on the `i_w` and `i_h` signals, `i_w` and `i_h` should remain valid during` i_sof=1`.
3. **Input**: Control `i_e` and `i_x`, input all the pixels of the image from left to right, top to bottom. When `i_e=1`, `i_x` is input as a pixel.
4. **Idle between images**: After all pixel input ends, it needs to be idle for at least 16 cycles without any action (i.e. `i_sof=0`, `i_e=0`). Then you can skip to step 2 and start the next image.

Between `i_sof=1` and `i_e=1`; and between `i_e=1` each can insert any number of free bubbles (ie, `i_sof=0`, `i_e=0`), which means that we can input pixels intermittently (of course, without inserting any bubbles for maximum performance).

The following figure shows the input timing diagram of compressing 2 images (//represents omitting several cycles, X represents don't care). where image 1 has 1 bubble inserted after the first pixel is entered; while image 2 has 1 bubble inserted after i_sof=1. Note **Inter-image idle** must be at least **16 cycles**.

               __    __//  __    __    __    __   //_    __    //    __    __//  __    __    __    //    __
    clk    \__/  \__/  //_/  \__/  \__/  \__/  \__// \__/  \__///\__/  \__/  //_/  \__/  \__/  \__///\__/  \_
                _______//________                 //           //     _______//________            //
    i_sof  ____/       //        \________________//___________//____/       //        \___________//________
                _______//________                 //           //     _______//________            //
    i_w    XXXXX_______//________XXXXXXXXXXXXXXXXX//XXXXXXXXXXX//XXXXX_______//________XXXXXXXXXXXX//XXXXXXXX
                _______//________                 //           //     _______//________            //
    i_h    XXXXX_______//________XXXXXXXXXXXXXXXXX//XXXXXXXXXXX//XXXXX_______//________XXXXXXXXXXXX//XXXXXXXX
                       //         _____       ____//_____      //            //               _____//____
    i_e    ____________//________/     \_____/    //     \_____//____________//______________/     //    \___
                       //         _____       ____//_____      //            //               _____//____
    i_x    XXXXXXXXXXXX//XXXXXXXXX_____XXXXXXX____//_____XXXXXX//XXXXXXXXXXXX//XXXXXXXXXXXXXXX_____//____XXXX
    
    阶段：      |    开始图像1     |        输入图像1       | 图像间空闲  |    开始图像2      |       输入图像2       

## Output JLS stream

During the input, **jls_encoder** will also output a compressed **JPEG-LS stream**, which constitutes the content of the complete .jls file (including the file header and trailer). When `o_e=1`, `o_data` is a valid output data. Among them, `o_data` follows the big endian order, that is, `o_data[15:8]` is at the front of the stream, and `o_data[7:0]` is at the back of the stream. `o_last=1` indicates the end of the compressed stream for an image when the output stream for each image encounters the last data.

　

# RTL Simulation

Simulation related files are in the [SIM](./SIM) directory, including:

* [tb_jls_encoder.sv](./SIM) is a testbench for jls_encoder. The behavior is: batch uncompressed images in .pgm format in the specified folder into jls_encoder for compression, and then save the output of jls_encoder to a .jls file.
* [tb_jls_encoder_run_iverilog.bat](./SIM) is a command script for iverilog simulation.
* The [images](./SIM) folder contains several image files in .pgm format. The .pgm format stores an uncompressed (that is, raw pixel) 8bit grayscale image, which can be opened with photoshop software or a Linux image viewer (Windows image viewer cannot view it).

> The .pgm file format is very simple, with only a header to indicate the length and width of the image, followed by all the raw pixels of the image. So I choose .pgm file as the input file for the simulation, because it only needs to write some code in the testbench to parse the .pgm file, and take out the pixels and send it to jls_encoder . However, you can ignore the format of the pgm file, because the work of jls_encoder has nothing to do with the pgm format, it only needs to accept the raw pixels of the image as input. You only need to focus on the simulated waveform and how the image pixels are fed into the jls_encoder.

Before using iverilog for simulation, you need to install iverilog , see: [iverilog_usage](https://github.com/WangXuan95/WangXuan95/blob/main/iverilog_usage/iverilog_usage.md)

Then double-click tb_jls_encoder_run_iverilog.bat to run the simulation, which takes more than 10 minutes to run.

After the simulation is over, you can see that several .jls files are generated in the folder, which are compressed image files. In addition, the simulation also produces a waveform file dump.vcd, you can open dump.vcd with gtkwave to view the waveform.

In addition, you can also modify some simulation parameters:

- Modify the macro **NEAR** in tb_jls_encoder.sv to change the compression ratio.
- Modify the macro **BUBBLE_CONTROL** in tb_jls_encoder.sv to determine how many bubbles to insert between adjacent input pixels:
  - When **BUBBLE_CONTROL=0**, no bubbles are inserted.
  - When **BUBBLE_CONTROL>0**, insert **BUBBLE_CONTROL ** bubbles.
  - When **BUBBLE_CONTROL<0**, insert random **0~(-BUBBLE_CONTROL)** bubbles each time.

　

## View compressed JLS file

Because **JPEG-LS** is niche and professional, most image viewing software cannot view .jls files.

You can try [this site](https://filext.com/file-extension/JLS) to view .jls files (though this site doesn't work sometimes).

If the website doesn't work, you can use the decompressor [decoder.exe](./SIM) I provided to decompress it back to a .pgm file and view it again. Please run the command with CMD in the [SIM](./SIM) directory:

```powershell
.\decoder.exe <JLS_FILE_NAME> <PGM_FILE_NAME>
```

For example:

```powershell
.\decoder.exe test000.jls tmp.pgm
```

> Note: decoder.exe is compiled from the C language source code provided by UBC : http://www.stat.columbia.edu/~jakulin/jpeg-ls/mirror.htm

　

# FPGA Deployment

On Xilinx Artix-7 xc7a35tcsg324-2, the synthesized and implemented results are as follows.

|    LUT     |    FF    |              BRAM              | Max Clock freq. |
| :--------: | :------: | :----------------------------: | :-------------: |
| 2347 (11%) | 932 (2%) | 9 x RAMB18 (9%), total 144Kbit |     35 MHz      |

At 35MHz, the image compression performance is 35 Mpixel/s, which means the compression frame rate for 1920x1080 images is 16.8fps.

　

# Reference

- ITU-T T.87 : Information technology – Lossless and near-lossless compression of continuous-tone still images – Baseline : https://www.itu.int/rec/T-REC-T.87/en
- UBC's JPEG-LS baseline Public Domain Code : http://www.stat.columbia.edu/~jakulin/jpeg-ls/mirror.htm
- Simple JPEG-LS baseline encoder in C language : https://github.com/WangXuan95/JPEG-LS 

　

　

　

<span id="cn">FPGA JPEG-LS image compressor</span>
===========================

基于 **FPGA** 的流式的 **JPEG-LS** 图像压缩器，特点是：

* 纯 Verilog 设计，可在各种FPGA型号上部署
* 用于压缩 **8bit** 的灰度图像。
* 可选**无损模式**，即 NEAR=0 。
* 可选**有损模式**，NEAR=1~7 可调。
* 图像宽度取值范围为 [5,16384]，高度取值范围为 [1,16384]。
* 极简流式输入输出。

　

# 背景知识

**JPEG-LS** （简称**JLS**）是一种无损/有损的图像压缩算法，其无损模式的压缩率相当优异，优于 PNG、Lossless-JPEG2000、Lossless-WEBP、Lossless-HEIF 等。**JPEG-LS** 用压缩前后的像素的最大差值（**NEAR**值）来控制失真，无损模式下 **NEAR=0**；有损模式下**NEAR>0**，**NEAR** 越大，失真越大，压缩率也越大。**JPEG-LS** 压缩图像的文件后缀是 .**jls** 。

JPEG-LS 有两代：

- JPEG-LS baseline (ITU-T T.87) : 一般提到 JPEG-LS 默认都是指 JPEG-LS baseline。**本库也实现的是 JPEG-LS baseline 的 encoder** 。如果你对软件版本的 JPEG-LS baseline encoder 感兴趣，可以看 https://github.com/WangXuan95/JPEG-LS (C语言实现)
- JPEG-LS extension (ITU-T T.870) : 其压缩率高于 JPEG-LS baseline ，但使用的非常少 (在网上搜不到任何代码) 。**本库与 JPEG-LS extension 无关！**不过我依照 ITU-T T.870 实现了 C 语言的 JPEG-LS extension，见 https://github.com/WangXuan95/JPEG-LS_extension

　

# 使用方法

RTL 目录中的 [**jls_encoder.sv**](./RTL/jls_encoder.sv) 是用户可以调用的 JPEG-LS 压缩模块，它输入图像原始像素，输出 JPEG-LS 压缩流。

## 模块参数

**jls_encoder** 只有一个参数：

```verilog
parameter logic [2:0] NEAR
```

决定了 **NEAR** 值，取值为 3'd0 时，工作在无损模式；取值为  3'd1~3'd7 时，工作在有损模式。

## 模块信号

**jls_encoder** 的输入输出信号描述如下表。

| 信号名称 | 全称 | 方向 | 宽度 | 描述 |
| :---: | :---: | :---: | :---: | :--- |
| rstn | 同步复位 | input | 1bit | 当时钟上升沿时若 rstn=0，模块复位，正常使用时 rstn=1 |
| clk | 时钟 | input | 1bit | 时钟，所有信号都应该于 clk 上升沿对齐。 |
| i_sof | 图像开始 | input | 1bit | 当需要输入一个新的图像时，保持至少368个时钟周期的 i_sof=1 |
| i_w | 图像宽度-1 | input | 14bit | 例如图像宽度为 1920，则 i_w 应该置为 14‘d1919。需要在 i_sof=1 时保持有效。 |
| i_h | 图像高度-1 | input | 14bit | 例如图像宽度为 1080，则 i_h 应该置为 14‘d1079。需要在 i_sof=1 时保持有效。 |
| i_e | 输入像素有效 | input | 1bit | 当 i_e=1 时，一个像素需要被输入到 i_x 上。 |
| i_x | 输入像素    | input | 8bit | 像素取值范围为 8'd0 ~ 8'd255 。 |
| o_e | 输出有效    | output | 1bit | 当 o_e=1 时，输出流数据产生在 o_data 上。 |
| o_data | 输出流数据 | output | 16bit | 大端序，o_data[15:8] 在先；o_data[7:0] 在后。 |
| o_last | 输出流末尾 | output | 1bit | 当 o_e=1 时若 o_last=1 ，说明这是一张图像的输出流的最后一个数据。 |

> 注：i_w 不能小于 14'd4 。

## 输入图片

**jls_encoder 模块**的操作的流程是：

1. **复位**（可选）：令 rstn=0 至少 **1 个周期**进行复位，之后正常工作时都保持 rstn=1。实际上也可以不复位（即让 rstn 恒为1）。
2. **开始**：保持 i_sof=1 **至少 368 个周期**，同时在 i_w 和 i_h 信号上输入图像的宽度和高度，i_sof=1 期间 i_w 和 i_h 要一直保持有效。
3. **输入**：控制 i_e 和 i_x，从左到右，从上到下地输入该图像的所有像素。当 i_e=1 时，i_x 作为一个像素被输入。
4. **图像间空闲**：所有像素输入结束后，需要空闲**至少 16 个周期**不做任何动作（即 i_sof=0，i_e=0）。然后才能跳到第2步，开始下一个图像。

i_sof=1 和 i_e=1 之间；以及 i_e=1 各自之间可以插入任意个空闲气泡（即， i_sof=0，i_e=0），这意味着我们可以断断续续地输入像素（当然，不插入任何气泡才能达到最高性能）。

下图展示了压缩 2 张图像的输入时序图（//代表省略若干周期，X代表don't care）。其中图像 1 在输入第一个像素后插入了 1 个气泡；而图像 2 在 i_sof=1 后插入了 1 个气泡。注意**图像间空闲**必须至少 **16 个周期**。

               __    __//  __    __    __    __   //_    __    //    __    __//  __    __    __    //    __
    clk    \__/  \__/  //_/  \__/  \__/  \__/  \__// \__/  \__///\__/  \__/  //_/  \__/  \__/  \__///\__/  \_
                _______//________                 //           //     _______//________            //
    i_sof  ____/       //        \________________//___________//____/       //        \___________//________
                _______//________                 //           //     _______//________            //
    i_w    XXXXX_______//________XXXXXXXXXXXXXXXXX//XXXXXXXXXXX//XXXXX_______//________XXXXXXXXXXXX//XXXXXXXX
                _______//________                 //           //     _______//________            //
    i_h    XXXXX_______//________XXXXXXXXXXXXXXXXX//XXXXXXXXXXX//XXXXX_______//________XXXXXXXXXXXX//XXXXXXXX
                       //         _____       ____//_____      //            //               _____//____
    i_e    ____________//________/     \_____/    //     \_____//____________//______________/     //    \___
                       //         _____       ____//_____      //            //               _____//____
    i_x    XXXXXXXXXXXX//XXXXXXXXX_____XXXXXXX____//_____XXXXXX//XXXXXXXXXXXX//XXXXXXXXXXXXXXX_____//____XXXX
    
    阶段：      |    开始图像1     |        输入图像1       | 图像间空闲  |    开始图像2      |       输入图像2       

## 输出压缩流

在输入过程中，**jls_encoder** 同时会输出压缩好的 **JPEG-LS流**，该流构成了完整的 .jls 文件的内容（包括文件头部和尾部）。o_e=1 时，o_data 是一个有效输出数据。其中，o_data 遵循大端序，即 o_data[15:8] 在流中的位置靠前，o_data[7:0] 在流中的位置靠后。在每个图像的输出流遇到最后一个数据时，o_last=1 指示一张图像的压缩流结束。

　

# 仿真

仿真相关文件都在 SIM 目录里，包括：

* tb_jls_encoder.sv 是针对 jls_encoder 的 testbench。行为是：将指定文件夹里的 .pgm 格式的未压缩图像批量送入 jls_encoder 进行压缩，然后将 jls_encoder 的输出结果保存到 .jls 文件里。
* tb_jls_encoder_run_iverilog.bat 包含了执行 iverilog 仿真的命令。
* images 文件夹包含几张 .pgm 格式的图像文件。 .pgm 格式存储的是未压缩（也就是存储原始像素）的 8bit 灰度图像，可以使用 photoshop 软件或 Linux 图像查看器就能打开它（Windows图像查看器查看不了它）。

> .pgm 文件格式非常简单，只有一个文件头来指示图像的长宽，然后紧接着就存放图像的所有原始像素。因此我选用 .pgm 文件作为仿真的输入文件，因为只需要在 testbench 中简单地编写一些代码就能解析 .pgm 文件，并把其中的像素取出发给 jls_encoder 。不过，你可以不关注 pgm 文件的格式，因为 jls_encoder 的工作与 pgm 格式并没有关系，它只需要接受图像的原始像素作为输入即可。你只需关注仿真的波形，关注图像像素是如何被送入 jls_encoder 中即可。

使用 iverilog 进行仿真前，需要安装 iverilog ，见：[iverilog_usage](https://github.com/WangXuan95/WangXuan95/blob/main/iverilog_usage/iverilog_usage.md)

然后双击 tb_jls_encoder_run_iverilog.bat 就可以运行仿真，该仿真需要运行十几分钟。

仿真结束后，你可以看到文件夹中产生了几个 .jls 文件，它们就是压缩得到的图像文件。另外，仿真还产生了波形文件 dump.vcd ，你可以用 gtkwave 打开 dump.vcd 来查看波形。

另外，你还可以修改一些仿真参数来进行：

- 修改 tb_jls_encoder.sv 里的宏名 **NEAR** 来改变压缩率。
- 修改 tb_jls_encoder.sv 里的宏名 **BUBBLE_CONTROL** 来决定输入相邻的像素间插入多少个气泡：
  - **BUBBLE_CONTROL=0** 时，不插入任何气泡。
  - **BUBBLE_CONTROL>0** 时，插入 **BUBBLE_CONTROL **个气泡。
  - **BUBBLE_CONTROL<0** 时，每次插入随机的 **0~(-BUBBLE_CONTROL)** 个气泡

> 在不同 NEAR 值和 BUBBLE_CONTROL 值下，本库已经经过了几百张照片的结果对比验证，充分保证无bug。（这部分自动化验证代码就没放上来了）

## 查看压缩结果

因为 **JPEG-LS** 比较小众和专业，大多数图片查看软件无法查看 .jls 文件。

你可以试试用[该网站](https://filext.com/file-extension/JLS)来查看 .jls 文件（不过这个网站时常失效）。

如果该网站失效，可以用我提供的解压器 decoder.exe 来把它解压回 .pgm 文件再查看。请在 SIM 目录下用 CMD 运行命令：

```powershell
.\decoder.exe <JLS_FILE_NAME> <PGM_FILE_NAME>
```

例如：

```powershell
.\decoder.exe test000.jls tmp.pgm
```

> 注：decoder.exe 编译自 UBC 提供的 C 语言源码： http://www.stat.columbia.edu/~jakulin/jpeg-ls/mirror.htm

　

# FPGA 部署

在 Xilinx Artix-7 xc7a35tcsg324-2 上，综合和实现的结果如下。

|    LUT     |    FF    |              BRAM              | 最高时钟频率 |
| :--------: | :------: | :----------------------------: | :----------: |
| 2347 (11%) | 932 (2%) | 9个RAMB18 (9%)，等效于 144Kbit |    35 MHz    |

35MHz 下，图像压缩的性能为 35 Mpixel/s ，对 1920x1080 图像的压缩帧率是 16.8fps 。

　

# 相关链接

- ITU-T T.87 : Information technology – Lossless and near-lossless compression of continuous-tone still images – Baseline : https://www.itu.int/rec/T-REC-T.87/en
- UBC's JPEG-LS baseline Public Domain Code : http://www.stat.columbia.edu/~jakulin/jpeg-ls/mirror.htm
- 精简的 JPEG-LS baseline 编码器 (C语言) : https://github.com/WangXuan95/JPEG-LS 
