`timescale 1ns / 1ps
`include "defs.vh"

module Processor(
    input clk, 
    output halt, 
    input reset, 
    output reg [7:0] pc, 
    input [31:0] ins, 
    output [31:0] io_reg1, 
    output [31:0] io_reg2, 
    output [31:0] io_reg3, 
    output [31:0] io_reg4
);

    wire [5:0] opcode;             
    wire [5:0] func;               
    wire [4:0] shift_amount;       
    wire [4:0] src1_addr;          
    wire [4:0] src2_addr;          
    wire [31:0] src1;              
    wire [31:0] src2;              
    wire [4:0] dest_addr;          
    wire [31:0] dest_data;         
    wire dest_data_valid;          
    wire [7:0] next_pc;            
    wire [15:0] imm;               

    reg [31:0] io_reg [0:3];       
    reg [1:0] io_reg_index;        
    reg fetched;                   

    // Assign I/O registers
    assign io_reg1 = io_reg[0];
    assign io_reg2 = io_reg[1];
    assign io_reg3 = io_reg[2];
    assign io_reg4 = io_reg[3];

    // Decode instruction combinationally (Must be BEFORE the Mux and ALU)
    assign opcode = ins[31:26];
    assign src1_addr = ins[25:21]; // rs
    assign src2_addr = ins[20:16]; // rt
    assign dest_addr = (opcode == `OP_REG) ? ins[15:11] : ins[20:16]; // rd or rt
    assign shift_amount = ins[10:6];
    assign func = ins[5:0];
    assign imm = ins[15:0];

    // Extend the immediate value (Must be BEFORE the Mux)
    wire [31:0] sign_ext_imm = {{16{imm[15]}}, imm}; 
    wire [31:0] zero_ext_imm = {16'b0, imm};         
    
    // Mux for the ALU's second input (Must be BEFORE the ALU instantiation)
    wire [31:0] alu_src2 = (opcode == `OP_REG) ? src2 : 
                           ((opcode == `OP_ANDI) || (opcode == `OP_ORI) || (opcode == `OP_XORI)) ? zero_ext_imm : 
                           sign_ext_imm;

    // Halt condition check
    assign halt = (reset | ~fetched) ? 1'b0 : 
                  (((opcode == `OP_REG) && (func == `FUNC_SYSCALL) && (src1 == `SYS_exit)) ? 1'b1 : 1'b0);

    assign next_pc = (fetched & ~halt) ? pc + 1 : 8'b0;


    // Instantiate Register File
    RegisterFile rf (
        src1_addr, 
        src2_addr, 
        src1, 
        src2, 
        dest_addr, 
        dest_data, 
        dest_data_valid & fetched, 
        clk
    );

    // Instantiate ALU (Now alu_src2 is properly defined as 32 bits!)
    ALU alu (
        src1, 
        alu_src2, 
        shift_amount, 
        opcode, 
        func, 
        dest_data, 
        dest_data_valid
    );


    // PC and Fetch Logic (Sequential)
    always @(posedge clk) begin
        if (reset) begin
            pc <= 8'b0;
            io_reg_index <= 2'b0;
            fetched <= 1'b0;
        end
        else begin
            pc <= halt ? pc : next_pc;
            fetched <= 1'b1;
        end
    end

    // I/O Syscall Logic (Sequential, Negedge)
    always @(negedge clk) begin
        if ((opcode == `OP_REG) && (func == `FUNC_SYSCALL) && (src1 == `SYS_write)) begin
            io_reg_index <= io_reg_index + 1;
            io_reg[io_reg_index] <= src2;
        end
    end

endmodule