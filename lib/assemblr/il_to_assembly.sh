# !/bin/bash
#
# il_to_assembly: A library which can be used to convert an intermediate language file to an assembly
#

#================================================================
# HEADER
#================================================================
# Required Libraries:
# basename
# dirname
# ilasm
# getopt -- GCC library
# TODO: Complete required libraries

###########
# Imports #
###########

# Utilities:
#	join_by
#	verbose_log
. "$( dirname "${BASH_SOURCE[0]}" )/utils.sh"

####################
# Helper Functions #
####################

#######################################
# Name: usage
# Description: Prints the usage text for this library
# Returns:
#   None
#######################################
# TODO: Add additional details to usage
usage() {
	printf '
  Usage: il_to_assembly [options] <path-to-il-file>
    Convert an intermediate language file into an assembly
  Options:
    -h|--help             Display this help message
    -a|--assembly-type    The type of assembly to convert the intermedeiate language file into
    -k|--key-file         The key with which to sign the assembly file
    -o|--output           The output directory in which to place the assembly file
    -v|--verbose          Enable verbose logging

  path-to-il-file:
    The path to the intermediate language file to convert into an assembly file
  \n'
	exit 0
}

#######################################
# Name: verify_il
# Description: Verifies than an il file is valid
# Returns:
#   None
#######################################
# TODO: add more test-cases
verify_il() {
	local il_file=$1
  local verbose=$2
  local il_file_ext="${il_file##*.}"
  if [[ $il_file_ext != "il" ]]; then
    echo "WARNING: invalid file given to verify_il: $il_file">&2
    return 1
  fi

  # typically, any file containing .permissionset .. = {..} will be impossible to decompile
  results=$(pcregrep -M '\.permissionset[\S+\n\r\s]*?\b(?:reqmin)\b[\S+\n\r\s]*?=[\S+\n\r
\s]*?\{[^{}]*+(\{(?:[^{}]|(?1))*+\}[^{}]*+)++\}' $il_file)
  if [[ -z $results ]]; then
    verbose_log $verbose "INFO: $il_file is valid"
    return 0
  else
    verbose_log $verbose "WARNING: $il_file is invalid: $results"
    return 1
  fi 
}

#######################################
# Name: il_to_assembly
# Description: Converts an intermediate language into an assembly file
# Globals:
#		ASSEMBLY_PATH
# 	OUTPUT
# Arguments:
#   $@        	 - The incomming array of inputs
# Returns:
#   None
#######################################
il_to_assembly() {
	local help=false
	local assembly_type=
	local output=
	local key_file=
	local verbose=false

	local opts=`getopt -o ha:o:k:v --long help,assembly_type:,output:,key_file:,verbose -n 'il_to_assembly' -- "$@"`
	if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi

	eval set -- "$opts"

	while true; do
		case "$1" in
		-h | --help ) help=true; shift ;;
    -a | --assembly-type ) assembly_type="$2"; shift 2 ;;
    -k | --key-file ) key_file="$2"; shift 2 ;;
		-o | --output ) output="$2"; shift 2 ;;
		-v | --verbose ) verbose=true; shift ;;
		-- ) shift; break ;;
		* ) break ;;
		esac
	done

  if [[ $help == true ]]; then
    usage
  fi

  
  local il_path="$@"
  local il=$(basename "${il_path}")
  local il_ext="${il_path##*.}"
  local il_name="${il%.*}"

  # validate argument
  if [[ $# != 1 ]]; then
    echo "ERROR: incorrect arguments provided to il_to_assembly: $@" >&2
    exit 1
  elif [[ ! -f $il_path || $il_ext != "il" ]]; then
    echo "ERROR: provided input file is not an intermediate language file: $@" >&2
    exit 1
  fi

  # validate options
  if [[ $assembly_type != "dll" && $assembly_type != "exe" ]]; then
    echo "ERROR: assembly-type is invalid - please provide dll or exe: $assembly_type" >&2
    exit 1
  fi

  # TODO: Handle "ilasm -key @key_container - see online documentation"
  if [[ ! -z $key_file && ( ! -f $key_file || "${key_file##*.}" != "snk" ) ]]; then
    echo "ERROR: provided key-file is not a valid: $key_file" >&2
    exit 1
  fi

  if [[ -z $output ]]; then
    output=$(dirname "${il_path}")
  elif [[ ! -d $output ]]; then
    echo "ERROR: output is not a directory: $output"
    exit 1
	fi

  verbose_log $verbose "INFO: handling edge-cases"
  verify_il $il_path $verbose
  if [[ $? != 0 ]]; then
    $verbose_log $verbose "WARNING: il file may not be converted into an assembly: $il_path">&2
  fi

  verbose_log $verbose "INFO: creating $il_name.$assembly_type in $output"

  if [[ ! -z $key_file ]]; then
    ilasm -$assembly_type -key="$key_file" -output="$output/$il_name.$assembly_type" "$il_path"
  else
    ilasm -$assembly_type -output="$output/$il_name.$assembly_type" "$il_path"
  fi
}