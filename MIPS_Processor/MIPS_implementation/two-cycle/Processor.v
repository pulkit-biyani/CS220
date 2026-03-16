`timescale 1ns / 1ps
`include "defs.vh"

module Processor(
    input clk, 
    output reg halt,      // Changed to 'reg' because the FSM controls it now
    input reset, 
    output reg [7:0] pc, 
    input [31:0] ins, 
    output [31:0] io_reg1, 
    output [31:0] io_reg2, 
    output [31:0] io_reg3, 
    output [31:0] io_reg4
);

    // --- Combinational Wires ---
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
    wire [15:0] imm;               
    wire halt_comb;

    // --- FSM States ---
    reg state;
    localparam S_FETCH_EXEC = 1'b0; // Cycle 1
    localparam S_WRITEBACK  = 1'b1; // Cycle 2

    // --- Inter-Stage Registers (To carry data from Cycle 1 to Cycle 2) ---
    reg [4:0] dest_addr_reg;
    reg [31:0] dest_data_reg;
    reg dest_valid_reg;

    // --- I/O Registers ---
    reg [31:0] io_reg [0:3];       
    reg [1:0] io_reg_index;        
    reg fetched;                   

    // Assign I/O registers
    assign io_reg1 = io_reg[0];
    assign io_reg2 = io_reg[1];
    assign io_reg3 = io_reg[2];
    assign io_reg4 = io_reg[3];

    // --- Decode Instruction (Combinational) ---
    assign opcode = ins[31:26];
    assign src1_addr = ins[25:21]; // rs
    assign src2_addr = ins[20:16]; // rt
    assign dest_addr = (opcode == `OP_REG) ? ins[15:11] : ins[20:16]; 
    assign shift_amount = ins[10:6];
    assign func = ins[5:0];
    assign imm = ins[15:0];

    // Extend the immediate value
    wire [31:0] sign_ext_imm = {{16{imm[15]}}, imm}; 
    wire [31:0] zero_ext_imm = {16'b0, imm};         
    
    // Mux for the ALU's second input
    wire [31:0] alu_src2 = (opcode == `OP_REG) ? src2 : 
                           ((opcode == `OP_ANDI) || (opcode == `OP_ORI) || (opcode == `OP_XORI)) ? zero_ext_imm : 
                           sign_ext_imm;

    // Halt condition check
    assign halt_comb = (reset | ~fetched) ? 1'b0 : 
                       (((opcode == `OP_REG) && (func == `FUNC_SYSCALL) && (src1 == `SYS_exit)) ? 1'b1 : 1'b0);

    // --- Module Instantiations ---
    
    // Notice how the Register File now takes its write inputs from the inter-stage registers!
    RegisterFile rf (
        src1_addr, 
        src2_addr, 
        src1, 
        src2, 
        dest_addr_reg,     // Updated to use FSM register
        dest_data_reg,     // Updated to use FSM register
        dest_valid_reg,    // Updated to use FSM register
        clk
    );

    ALU alu (
        src1, 
        alu_src2, 
        shift_amount, 
        opcode, 
        func, 
        dest_data, 
        dest_data_valid
    );

    // --- Sequential Logic (The Two-State FSM) ---
    always @(posedge clk) begin
        if (reset) begin
            pc <= 8'b0;
            io_reg_index <= 2'b0;
            fetched <= 1'b0;
            state <= S_FETCH_EXEC;
            dest_addr_reg <= 5'b0;
            dest_data_reg <= 32'b0;
            dest_valid_reg <= 1'b0;
            halt <= 1'b0;
        end
        else begin
            case (state)
                S_FETCH_EXEC: begin
                    fetched <= 1'b1;
                    if (!halt) begin
                        // 1. Capture the ALU's combinational output into inter-stage registers
                        dest_addr_reg <= dest_addr;
                        dest_data_reg <= dest_data;
                        dest_valid_reg <= dest_data_valid;
                        
                        // 2. Capture halt status
                        halt <= halt_comb;

                        // 3. Move to Cycle 2
                        state <= S_WRITEBACK;
                    end
                end

                S_WRITEBACK: begin
                    // 1. Ensure we only write to the register file for one cycle
                    dest_valid_reg <= 1'b0;

                    // 2. Increment the PC now that the instruction is fully complete
                    if (!halt) begin
                        pc <= pc + 1;
                    end

                    // 3. Return to Cycle 1 to fetch the next instruction
                    state <= S_FETCH_EXEC;
                end
            endcase
        end
    end

    // --- I/O Syscall Logic (Negedge) ---
    // Trigger I/O writes on the negative edge of Cycle 1
    always @(negedge clk) begin
        if (state == S_FETCH_EXEC && fetched) begin
            if ((opcode == `OP_REG) && (func == `FUNC_SYSCALL) && (src1 == `SYS_write)) begin
                io_reg_index <= io_reg_index + 1;
                io_reg[io_reg_index] <= src2;
            end
        end
    end

endmodule