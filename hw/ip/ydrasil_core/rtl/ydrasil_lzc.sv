module ydrasil_lzc
import ydrasil_pkg::*;
#(
  parameter int unsigned WIDTH = 32,
  parameter bit          MODE  = 1'b0,// Mode selection: 0 -> trailing zero, 1 -> leading zero
  parameter int unsigned CNT_WIDTH = ydrasil_pkg::idx_width(WIDTH)
) (
  input  logic [WIDTH-1:0]     lzc_in_i,
  output logic [CNT_WIDTH-1:0] lzc_cnt_o,
  output logic                 lzc_empty_o
);

  if (WIDTH == 1) begin : gen_degenerate_lzc

    assign lzc_cnt_o[0] = !lzc_in_i[0];
    assign lzc_empty_o = !lzc_in_i[0];

  end else begin : gen_lzc

    localparam int unsigned NumLevels = $clog2(WIDTH);

    logic [WIDTH-1:0][NumLevels-1:0] lzc_index;
    logic [2**NumLevels-1:0] sel_nodes;
    logic [2**NumLevels-1:0][NumLevels-1:0] index_nodes;

    logic [WIDTH-1:0] in_to_process;

    if (MODE) begin : g_input_reverse
      for (genvar i = 0; unsigned'(i) < WIDTH; i++) begin : g_each_input_reverse
        assign in_to_process[i] = lzc_in_i[WIDTH-1-i];
      end
    end
    else begin : g_input_direct
      for (genvar i = 0; unsigned'(i) < WIDTH; i++) begin : g_each_input_direct
        assign in_to_process[i] = lzc_in_i[i];
      end
    end


    for (genvar j = 0; unsigned'(j) < WIDTH; j++) begin : g_lzc_index
      assign lzc_index[j] = (NumLevels)'(unsigned'(j));
    end

        // 3. 树形归约计算每层

    for (genvar tree_level = 0; unsigned'(tree_level) < NumLevels; tree_level++) begin : g_tree_levels
        if(unsigned'(tree_level) == NumLevels - 1) begin : g_last_tree_level
          for (genvar k = 0; k < 2 ** tree_level; k++) begin : g_tree_nodes
            // if two successive indices are still in the vector...
            if (unsigned'(k) * 2 < WIDTH - 1) begin : g_reduce
              assign sel_nodes[2 ** tree_level - 1 + k] = in_to_process[k * 2] | in_to_process[k * 2 + 1];
              assign index_nodes[2 ** tree_level - 1 + k] = (in_to_process[k * 2] == 1'b1)
                ? lzc_index[k * 2] :
                  lzc_index[k * 2 + 1];
            end
            // if only the first index is still in the vector...
            if (unsigned'(k) * 2 == WIDTH - 1) begin : g_base
              assign sel_nodes[2 ** tree_level - 1 + k] = in_to_process[k * 2];
              assign index_nodes[2 ** tree_level - 1 + k] = lzc_index[k * 2];
            end
            // if index is out of range
            if (unsigned'(k) * 2 > WIDTH - 1) begin : g_out_of_range
              assign sel_nodes[2 ** tree_level - 1 + k] = 1'b0;
              assign index_nodes[2 ** tree_level - 1 + k] = '0;
            end
          end
        end else begin : g_other_tree_level
            for (genvar l = 0; l < 2 ** tree_level; l++) begin : g_level
                assign sel_nodes[2 ** tree_level - 1 + l] =
                    sel_nodes[2 ** (tree_level + 1) - 1 + l * 2] | sel_nodes[2 ** (tree_level + 1) - 1 + l * 2 + 1];
                assign index_nodes[2 ** tree_level - 1 + l] = (sel_nodes[2 ** (tree_level + 1) - 1 + l * 2] == 1'b1)
                ? index_nodes[2 ** (tree_level + 1) - 1 + l * 2] :
                    index_nodes[2 ** (tree_level + 1) - 1 + l * 2 + 1];
            end
        end
    end



    assign lzc_cnt_o = NumLevels > unsigned'(0) ? index_nodes[0] : {NumLevels {1'b0}};
    assign lzc_empty_o = NumLevels > unsigned'(0) ? ~sel_nodes[0] : ~(|in_to_process);

  end : gen_lzc



endmodule
