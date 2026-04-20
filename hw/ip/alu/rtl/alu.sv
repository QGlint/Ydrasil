module alu#(
    parameter   DATAWIDTH = 32   
)(
    input  logic [DATAWIDTH - 1:0]  A           ,
    input  logic [DATAWIDTH - 1:0]  B           ,
    input  logic [1:0]              ALUControl  ,
    output logic [DATAWIDTH - 1:0]  Result      ,
    output logic                    N           ,
    output logic                    Z           ,
    output logic                    V           ,
    output logic                    C           
);

    assign {C, Result} = A + B;
    


endmodule