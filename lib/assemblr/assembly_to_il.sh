# !/bin/bash
#
# assembly_to_il: A library which can be used to convert an assembly to intermediate language
#

# TODO: Move this to top-level configuraiton
wsl_linux=ubuntu1804

#================================================================
# HEADER
#================================================================
# Required Libraries:
# basename
# dirname
# ikdasm
# getopt -- GCC library
# TODO: Complete required libraries

###########
# Imports #
###########

# Utilities:
#	join_by
#	verbose_log
. ./utils.sh

####################
# Helper Functions #
####################

#######################################
# Name: save_metadata
# Description: Saves the metadata of a given assembly into $OUTPUT/$ASSEMBLY_PATH
# Arguments:
#   $1: required(string)  - The comma delineated string containing the metadata to extract and save
#   $2: required(string)  - The file from which to extract metadata
#   $3: optional:(string) - The folder in which to save the metadata
#   $4: optional:(bool)   - An option to verbose-print information
# Returns:
#   None
#######################################
# TODO: support monodis commands for .exe assemblies
save_metadata() {
  local requested_metadata=$1
  local assembly=$2
  local output=$3
  local verbose=${4,false}

  if [[ ! -f $assembly || -z $assembly || ("${assembly##*.}" != "dll" && "${assembly##*.}" != "exe") ]]; then
    echo "ERROR: file $assembly is not a valid assembly">&2
    return 1
  fi

  if [[ ! -z $output && ! -d $output ]]; then
    echo "ERROR: output directory $output is not valid">&2
    return 1
  fi

  if [[ ! -z $verbose && $verbose == true ]]; then
    verbose=true
  else
    verbose=false
  fi

  # check the options
  t=($(echo $requested_metadata | tr "," "\n"))
  for item in ${t[@]}
  do
    case "$item" in 
      assembly )
        commands=("${commands[@]}" "-assembly" );
        ;;
      assemblyref )
        commands=( "${commands[@]}" "-assemblyref" );
        ;;
      moduleref )
        commands=( "${commands[@]}" "-moduleref" );
        ;;
      exported )
        commands=( "${commands[@]}" "-exported" );
        ;;
      #customattr ) - TODO: See how this can be supported
      #  commands=( "${commands[@]}" "-customattr" );
      #  ;;
      *)
        echo "ERROR: invalid option $item given to save_metadata">&2; 
        return 1;
    esac
  done

  # reform metadata
  requested_metadata="$(join_by , ${t[@]})"

  # operation variables
  local assembly_name=$(basename "${assembly}")
	local results=
	local csv=
  if [[ ! -z $output ]]; then
    csv="$output/${assembly_name%.*}-metadata.csv"
  else
    csv="${assembly%.*}-metadata.csv"
  fi

	if [[ ! -f "$csv" && commands[] ]]; then 
		verbose_log $verbose "INFO: creating $csv"
	 	touch "$csv"
  else
    local counter=1
    local old_csv=$csv
    until [[ ! -f  "${csv%.*}_$counter.csv" ]]; do
      let counter+=1
    done
    csv="${csv%.*}_$counter.csv"
    verbose_log $verbose "WARNING: $old_csv already exists, creating $csv"
    touch "$csv"
	fi
  echo "$requested_metadata"
	echo "$requested_metadata" > $csv

	for i in "${commands[@]}"
	do
		verbose_log $verbose "INFO: executing ikdasm $i..."
		res="$(ikdasm $assembly $i | awk '{printf("%s",$0)}')"
		results=( "${results[@]}" "${res//[,], <comma>}" )
	done
	results=("${results[@]:1}")	

	echo $(join_by , "${results[@]}") >> $csv
}

#######################################
# Name: usage
# Description: Prints the usage text for this library
# Returns:
#   None
#######################################
# TODO: Add additional details to usage
usage() {
  printf '
  Usage: assembly_to_il [options] <path-to-assembly-file>
    Convert an assembly file into an intermediate language file
  Options:
    -h|--help       Display this help message
    -m|--metadata   The metadata to grab from the assembly. This data will be saved in -o|--output or in the scripts place of execution
    -o|--output     The output directory in which to place the intermediate language file
    -v|--verbose    Enable verbose logging

  path-to-assembly-file:
    The path to the assembly file to convert into an intermediate language file  
  \n'
	#echo "available metadata options: assembly-table,assembly-ref,module-ref,exported,custom-attributes"
	exit 0
}

####################
# Public Functions #
####################

#######################################
# Name: assembly_to_il
# Description: Converts a given assembly into intermediate language
# Globals:
#	ASSEMBLY_PATH
# 	OUTPUT
# Arguments:
#   $@        	 - The incomming array of inputs
# Returns:
#   None
#######################################
assembly_to_il() {
	local help=false
	local metadata=
  local output=
  local verbose=

	local opts=`getopt -o hm:o:v --long help,metadata:,output:,verbose -n 'assembly_to_il' -- "$@"`
	if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi

	eval set -- "$opts"

	while true; do
		case "$1" in
		-h | --help ) help=true; shift ;;
		-m | --metadata ) metadata="$2"; shift 2 ;;
		-o | --output ) output="$2"; shift 2 ;;
		-v | --verbose ) verbose=true; shift ;;
		-- ) shift; break ;;
		* ) break ;;
		esac
	done

	if [[ $help == true ]]; then
    usage
  fi
  
  # assembly meta-data storage
  local assembly=$(basename "${@}")
  local assembly_ext="${@##*.}"
  local assembly_name="${assembly%.*}"
  local assembly_path="$@"

  # validate arguement
	if [[ $# > 1 ]]; then
		echo "ERROR: too many arguments provided to assembly_to_il: $@">&2
		exit 1
	elif [[ ( ! -f $@ && ! -z $@ ) || ( $assembly_ext != "dll" && $assembly_ext != "exe") ]]; then
		echo "ERROR: file $@ is not a valid assembly">&2
		exit 1
	fi

  # validate options
	if [[ -z $output ]]; then
    output=$(dirname "${assembly_path}")
  elif [[ ! -d $output ]]; then
    echo "ERROR: output is not a directory: $output"
    exit 1
	fi
	
	if [[ ! -z "${metadata}" ]]; then
		save_metadata "$metadata"  "$assembly_path" "$output" $verbose
	fi	

	verbose_log $verbose "INFO: creating $assembly_name.il in $output"

  local os_name=$(uname)

  if [[ -f "$output/$assembly_name.il" ]]; then
    rm -f "$output/$assembly_name.il"
  fi

  # NOTE: the branch(s) containing "MSYS_NT-10.0" will check if we are running this script on windows, and then perform the operation in the linux subsystem
  #   you must run the command in the windows subsystem, as mono has a different version of ikdasm for windows vs linux/posix
  # TODO: ping the mono community on this
  if [[ $os_name == "MSYS_NT-10.0" ]]; then
    output=$(readlink --canonicalize "$output")
    assembly_path=$(readlink --canonicalize "$assembly_path")

    output="/mnt$output"
    assembly_path="/mnt$assembly_path"
  fi

  case "$assembly_ext" in
    dll )
        if [[ $os_name == "MSYS_NT-10.0" ]]; then      
          sudo $wsl_linux run "ikdasm $assembly_path ^> $output/$assembly_name.il"
        else
          ikdasm "$assembly_path" > "$output/$assembly_name.il"
        fi
      ;;
    exe )
        # TODO: iklasm could be ran after to produce a second-il - look into this, as the .il created by
        #   ikdasm and monodis are both different
        if [[ $os_name == "MSYS_NT-10.0" ]]; then      
          sudo $wsl_linux run "monodis $assembly_path --output=$output/$assembly_name.il"
        else
          monodis "$assembly_path" --output="$output/$assembly_name.il"
        fi
      ;;
    * )
        echo "ERROR: Unhandled assembly extension $assembly_ext encountered">&2
        exit 1
      ;;
  esac 
}