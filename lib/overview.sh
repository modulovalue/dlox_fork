TEMP="overview.pdf"
echo '
digraph {
  rankdir=BT
  ast
  rawcode
  tokens
  objfunction
  output

  rawcode -> tokens [label="code_to_tokens.dart"]
  tokens -> ast [label="tokens_to_ast.dart"]
  ast -> objfunction [label="ast_to_objfunction.dart"]
  objfunction -> output [label="objfunction_to_output.dart"]
  rawcode -> objfunction [label="code_to_objfunction.dart"]
  rawcode -> output [label="code_to_output.dart"]
}
' | dot -Tpdf -o $TEMP
open $TEMP
sleep 1
rm $TEMP