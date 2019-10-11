# !/bin/bash
#
# assemblr - a library which wraps the ilasm and ikdasm with some sweet, sweet bonus features

#================================================================
# HEADER
#================================================================
# Required Libraries:
# basename
# dirname
# ikdasm
# getopt -- GCC library

main() {
  current_dir=$(dirname "${BASH_SOURCE[0]}")
  . $current_dir/il_to_assembly.sh
  . $current_dir/assembly_to_il.sh
}

main