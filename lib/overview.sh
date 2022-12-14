TEMP="overview.pdf"
echo '
digraph {
  rankdir=BT
  ast
  rawcode
  tokens
  objfunction
  output

  rawcode -> tokens [label="code_to_tokens.dart\nana"]
  tokens -> ast [label="tokens_to_ast.dart\nnat"]
  ast -> objfunction [label="ast_to_objfunction.dart\ncat if to bytecode, worth trying to make it a nat with a dsl?"]
  objfunction -> output [label="objfunction_to_output.dart\nthink about making the vm a nat, and the tracing capabilities a composition."]
  rawcode -> objfunction [label="code_to_objfunction.dart\nshould deforest because it is hylomorph"]
  rawcode -> output [label="code_to_output.dart\nif vm a nat, should deforest because it is hylomorph"]
}
' | dot -Tpdf -o $TEMP
open $TEMP
sleep 1
rm $TEMP