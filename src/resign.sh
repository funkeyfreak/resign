#! /bin/bash

#================================================================
# HEADER
#================================================================

###########
# Imports #
###########

# Import the assemblr library
#   il_to_assembly
#   assembly_to_il
. $( dirname "${BASH_SOURCE[0]}" )/../lib/assemblr/assemblr.sh
. $( dirname "${BASH_SOURCE[0]}" )/commands/key.sh
. $( dirname "${BASH_SOURCE[0]}" )/commands/check.sh

# TODO: move to global-scoped script AND use uname to determine if on windows
[ -x "$(uuidgen -h 2> /dev/null)" ] || alias uuidgen='powershell -command "[guid]::newguid().Guid"|xargs'

###########
# GLOBALS #
###########
#SCRIPT_FOLDER="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# The name of this script is its containing folder
#SCRIPT_NAME="$(basename $SCRIPT_FOLDER)"

# cmd context
# INPUT=($@)
# NUM_ARGS=$#
# CMD=
# CHECK_CMD=
# KEY_CMD=

# # options
# HELP=false
# BACKUP=false
# DRY_RUN=false
# SAVE_KEY=fakse
# VERBOSE=false

# # options: check
# DELAY=false
# NATIVE=false
# REMOVE=false
# SIGNED=false

# # options: key
# EXTRACT=false

# # argeuemtns
# PATH_ARG=

# # arguments: check
# CHECK_ARG=

# # argeuments: key
# KEY_ARG=

####################
# HELPER FUNCTIONS #
####################

#######################################
# Name: get_index
# Description: Fetches the index of a given string from a command-array
# Returns:
#   string - the index of the string in the array
#######################################
# TODO: move to associative array - this will remove the need for get_index (possibly)
get_index() {
  local arr=($@)
  local find=("${arr[-1]}")
  local idx=-1 
  unset 'arr[${#arr[@]}-1]'
  for i in "${!arr[@]}"; do
      if [[ "${arr[$i]}" = "${find}" ]]; then
          idx=${i}
          break
      fi
  done
  echo "$idx"
}

#######################################
# Name: validate_arguments
# Description: Prepares the arguments and subcommands to resign
# Returns:
#   string - The input parm if valid, else undefined
#######################################
validate_arguments() {
  local path="$1"
  if [[ ( -f $path ) && ( ! -d $path ) && ("${path##*.}" != "dll" && "${path##*.}" != "exe") ]]; then
    path=
  fi

  echo $path
}

#######################################
# Name: usage
# Description: Prints the usage text for this script
# Returns:
#   None
#######################################
usage() {
  case "$1" in
  -h | --help ) printf '
    Usage:  resign [options] [<command(s)>] <path-to-assembly(s)>
      
      Resign assembly(s) from a given path

    Options:
      -h|--help       Display this help message
      -b|--backup     Backup the folder before processing - will be named <path-to-assembly(s)>.backup.zip
      -d|--dry-run    Dry-run - prints the assemblies which will be signed
      -o|--output     The folder in which to place the output. Defaults to `.`
      -r|--robust     When given a folder, this will prompt our tool to not fail on a single file
                      NOTE: any artifacts from failed resign-attempts will be left in the directory which
                      contains the assembly which failed to resign
      -s|--save-all   Will save most of the intermediate files used during resigning. This includes dis-
                      -assembled assemblies in their intermediate language form and unsigned assemblies 
                      (<assembly-name>.orig.[dll|exe])
                      NOTE: Will NOT save the keys used in resigning. Please pass k|key -k|--keep to use
                      this scenario
      -v|--verbose    Enables verbose output
          
    Command(s):
      check         Run a check on the assemblies before signing
      key           Instead of generating a new snk, sign with this given key

    path-to-key-source:
      The path to a .snk/key source with which to sign the assembly(s)

    path-to-assembly(s):
      The path to the assembly/folder containing assembly(s)
      NOTE: Signing will only work on managed .dll(s), as native assemblies do not have the ability to be signed
    \n'>&2
    ;;
  *) printf '
    Usage:  resign [options] <path-to-assembly(s)>
      
      Resign assembly(s) given an snk

    Options:
      -h|--help       Display a help message

    path-to-assembly(s):
      The path to the assembly/folder containing assemblies
    \n'>&2
    ;;
  esac
}

#######################################
# Name: verbose_log
# Description: Prints the usage text for this script
# Returns:
#   None
#######################################
# TODO: Move to a utilities script
# TODO: Remove all "echo" logging statements - handle in this function & check 'level', e.g. ERROR, WARNING, etc.
verbose_log() {
  if [[ $1 == true ]]; then
    echo "${@:2}" 
  fi
}

# Enables multi-threading for resign
resign_helper() {
  local resign_helper_file=$1
  local resign_helper_key=$2
  local resign_helper_output=$3
  local resign_helper_verbose=$4

  local resign_helper_file_type="${resign_helper_file##*.}"
  local resign_helper_intermediate_file="${resign_helper_file%.*}.il"
  local resign_error_code=
  local resign_helper_tmp_dir="$resign_helper_output/$(uuidgen)"
  mkdir -p $resign_helper_tmp_dir

  copy_file_to_resign_helper_output() {
    cp -r --backup=t "$resign_helper_tmp_dir/*.$1" "$resign_helper_output"
  }

  local_file_cleanup_resign_helper() {
    rm -rf "$resign_helper_tmp_dir"
  }

  cleanup_resign_helper() {
    copy_file_to_resign_helper_output "il"
    copy_file_to_resign_helper_output "dll"
    copy_file_to_resign_helper_output "exe"
    local_file_cleanup_resign_helper
  }

  verbose_log $resign_helper_verbose "INFO: processing $resign_helper_file..."
  assembly_to_il $( if [[ $resign_helper_verbose == true ]]; then echo "-v"; fi ) -o $resign_helper_output $resign_helper_file
  resign_error_code=$?
  if [[ $resign_error_code != 0 ]]; then
    echo "ERROR: Failed intermediate step assembly_to_il with code $resign_error_code: $resign_helper_file"
    return $resign_error_code
  fi

  il_to_assembly $( if [[ $resign_helper_verbose == true ]]; then echo "-v"; fi ) -k $resign_helper_key -a $resign_helper_file_type -o $resign_helper_output $resign_helper_intermediate_file
  resign_error_code=$?
  if [[ $resign_error_code != 0 ]]; then
    echo "ERROR: Failed intermediate step il_to_assembly with code $resign_error_code: $resign_helper_file"
    return $resign_error_code
  fi
  verbose_log $resign_helper_verbose "INFO: successfully processed $resign_helper_file"
}

#######################################
# Initializes the key sub-command
# Arguments:
#   $1: required(string[]) - The incoming array of arguments
#   $2: optional(ref:map[string]string) - The results associative array passed by reference:
#   map[string]string:
#     [
#       "cmd":        - string[]   : resign cmd options and arguments
#       "key":        - string[]   : key cmd options and arguments
#       "check":      - string[]   : check cmd option and arguments
#     ]
# Returns:
#   None
#######################################
init_resign() {
  if [[ $#  == 0 ]]; then
    echo "ERROR: cannot have empty arguments">&2
    return 1
  fi

  local input=($1)
  local -n res=$2
  local cmd_arg="${input[-1]}"
  
  if [[ $(get_index "$cmd_arg" "c") != -1 || $(get_index "$cmd_arg" "check") != -1 || 
        $(get_index "$cmd_arg" "k") != -1 || $(get_index "$cmd_arg" "key") != -1 ]]; then
    echo "ERROR: poorly formed command: $cmd_arg">&2
    return 1
  elif [[ ( ! -d $cmd_arg ) && ! ( ( -f $cmd_arg ) && ("${cmd_arg##*.}" == "dll" || "${cmd_arg##*.}" == "exe") ) ]]; then
    echo "ERROR: invalid argument: $cmd_arg">&2
    return 1
  fi

  local num_args=${#input[@]}
  local cmd=
  local check_cmd=
  local key_cmd=

  # extract subcommands
  local loc_cmd=("${input[@]::${#input[@]}-1}")
  local idx_cmd_check="$(get_index "${input[@]}" "c")"
  if [[ $idx_cmd_check == -1 ]]; then
    idx_cmd_check="$(get_index "${input[@]}" "check")"
  fi

  local idx_cmd_key="$(get_index "${input[@]}" "k")"
  if [[ $idx_cmd_key == -1 ]]; then
    idx_cmd_key="$(get_index "${input[@]}" "key")"
  fi

  # process base-command
  if [[ $idx_cmd_check != -1 && $idx_cmd_key != -1 ]]; then
    local idx_cmd_end=$(($idx_cmd_check < $idx_cmd_key ? $idx_cmd_check : $idx_cmd_key))
    cmd=(${loc_cmd[@]:0:$idx_cmd_end})
    if [[ idx_cmd_end == 0 ]]; then
      unset cmd
    fi
  elif [[ $idx_cmd_check != -1 ]]; then
    local idx_cmd_end=$idx_cmd_check
    cmd=(${loc_cmd[@]:0:$idx_cmd_end})
    if [[ idx_cmd_end == 0 ]]; then
      unset cmd
    fi
  elif [[ $idx_cmd_key != -1 ]]; then
    local idx_cmd_end=$idx_cmd_key
    cmd=(${loc_cmd[@]:0:$idx_cmd_end})
    if [[ idx_cmd_end == 0 ]]; then
      unset cmd
    fi
  else
    cmd=("${loc_cmd[@]}")
  fi
  cmd=( "${cmd[@]}" "$cmd_arg" )

  # process subcommands
  if [[ $idx_cmd_check != $idx_cmd_key ]]; then
    local end_of_cmd=$(($num_args-1))
    # if either of the subcommands exists, go ahead and set the appropriate CMD
    if [[ $idx_cmd_check != -1 ]]; then
      check_cmd=(${loc_cmd[@]:$(($idx_cmd_check+1)):$end_of_cmd})
    fi
    if [[ $idx_cmd_key != -1 ]]; then
      key_cmd=(${loc_cmd[@]:$(($idx_cmd_key+1)):$end_of_cmd})
    fi

    # if both subcommands are set, we need to find and remove the overlap    
    if [[ $idx_cmd_check != -1 ]] && [[ $idx_cmd_key != -1 ]]; then
      # if check has been supplied and key has not
      local idx_to_remove=$(get_index ${check_cmd[@]} "key")
      if [[ $idx_to_remove == -1 ]]; then
        idx_to_remove=$(get_index ${check_cmd[@]} "k")
      fi
      if [[ $idx_to_remove != -1 ]]; then
        check_cmd=(${check_cmd[@]:0:$idx_to_remove})
      fi
      
      # if key has been supplied and check has not
      idx_to_remove=$(get_index ${key_cmd[@]} "check")
      if [[ idx_to_remove == -1 ]]; then
        idx_to_remove=$(get_index ${key_cmd[@]} "c")
      fi
      if [ $idx_to_remove != -1 ]; then 
        key_cmd=(${key_cmd[@]:0:$idx_to_remove})
      fi
    fi
  fi

  res["cmd"]="${cmd[@]}"
  res["check"]="${check_cmd[@]}"
  res["key"]="${key_cmd[@]}"
}

#   $3: optional(ref string[]) - A list of signable files. If a directory is given, this will
#     contain more than one entry
init() {
  # set all inputs to local args & pass-by-reference args
  declare -A t_options
  local t_arguments

  local input=($1)
  local -n options=${2:-t_options}
  local -n arguments=${3:t_arguments}

  # temp helper variables
  local help=false
  local backup=false
  local dry_run=false
  local output=.
  local robust=false
  local save_all=false
  local verbose=false

  local opts=

  if ! opts=$(getopt -o hbdo:rsv --long help,backup,dry-run,output:,robust,save-all,verbose -n 'resign' -- "${input[@]}"); then 
    echo "ERROR: failed while parsing resigns options: ${input[@]}" >&2
    usage
    return 1
  fi

  eval set -- "$opts"
  unset opts

  while true; do
    case "$1" in
      -h | --help ) help=true; shift ;;
      -b | --backup ) backup=true; shift ;;
      -d | --dry-run ) dry_run=true; shift ;;
      -o | --output ) output="$2"; shift 2 ;;
      -r | --robust ) robust=true; shift ;;
      -s | --save-all ) save_all=true; shift ;;
      -v | --verbose ) verbose=true; shift ;;
      -- ) shift; break ;;
      * ) break ;;
    esac
  done
  
  if [[ $help == true ]]; then
    usage "-h"
    exit 0
  fi

  local arr=($@) 2> /dev/null
  local arg=("${arr[-1]}")

  # validate arguments  
  # is a file, not accepted, and is not a directory
  #[t && (t && (f && f))] => f
  # is not a  file, is a directory
  #[t]
  # is not a file, is not a directory
  # is a file, is accepted, is not a directory
  if [[ ( ! -d $arg ) && ! ( ( -f $arg ) && ("${arg##*.}" == "dll" || "${arg##*.}" == "exe") ) ]]; then
    echo "ERROR: argument $1 is not a valid assembly or a directory">&2
    usage
    return 1
  fi

  if [[ -d $arg ]]; then
    arg=($(du -a ./$1 | grep "\.dll[[:cntrl:]]*$\|\.exe[[:cntrl:]]*$" | cut -f2-))
    if [[ ${#arg[@]} == 0 ]]; then
      echo "ERROR: provided folder does not contain any resignable files: $arg">&2; 
      return 1
    fi
  fi

  # validate options
  if [[ ! -d $output ]]; then
    echo "ERROR: output is not a directory: $output">&2
    usage
    return 1
	fi

  if [[ $backup == true && $dry_run == true ]]; then
    echo "ERROR: running backup and dry_run is an illegal option">&2
    usage
    return 1
  fi


  options["backup"]=$backup
  options["dry_run"]=$dry_run
  options["output"]=$output
  options["robust"]=$robust
  options["verbose"]=$verbose
  arguments=("${arg[@]}")
}

#######################################
# Resigns assemblies
# Arguments:
#   $1: required(string[]) - The incoming array of arguments
#   $2: required(string) - The temporary directory to use for 
# Returns:
#   None
#######################################
resign() {
  local all_args=$1
  local resign_tmp_dir=$2

  echo "$1"
  if [[ $# != 2 ]]; then
    usage
    return 1
  fi

  declare -A parsed_input

  declare -A cmd_opt
  declare -a cmd_arg=

  declare -A check_opt
  local check_arg=

  declare -A key_opt
  local key_arg=

  # format input 
  local parsed_input
  init_resign "${all_args[@]}" parsed_input >&2
  if [[ $? != 0 ]]; then
    echo "ERROR: failed to parse input: $@" >&2
    usage
    exit 1
  fi

  # valid all commands
  # We validate these commands in the following order to preserve optimal command run-time
  # * The main command (cmd)
  # * The check sub-command (check)
  # * The key sub-command (key)

  # this initialization function sets global args for the operation of this method
  init "${parsed_input[cmd]}" cmd_opt cmd_arg
  if [[ $? != 0 ]]; then
    echo "ERROR: failed to initialize resign">&2
    exit 1
  fi

  # check processes files provided to resign
  # TODO: check command
  if [[ ! -z ${parsed_input[check]} ]]; then
    # check "${parsed_input[check]}" "${cmd_arg[@]}" check_opt check_arg $resign_tmp_dir ${cmd_opt[verbose]}
    # cmd_arg=("${check_arg[@]}")
    # verbose_log ${cmd_opt[verbose]} "INFO: check subcommand processed successfully"
    echo "check">&2
  elif [[ $(get_index ${all_args[@]} "check") != -1 ]]; then
    usage_check
    exit 1
  fi

  echo "cmd opt ${cmd_opt[@]}">&2
  echo "cmd arg ${cmd_arg[@]}">&2

  # key handles key creation for resign
  # TODO: if key is not provided, use the key from the first assembly given 
  if [[ ! -z ${parsed_input[key]} ]]; then
    key ${parsed_input[key]} key_opt key_arg $resign_tmp_dir ${cmd_opt[verbose]}
    if [[ $? != 0 ]]; then
      exit $?
    fi
    verbose_log ${cmd_opt[verbose]} "INFO: key subcommand processed successfully"
  elif [[ $(get_index ${all_args[@]} "key") != -1 ]]; then
    usage_key
    exit 1
  fi
  # process all files

  multi_process() {
    local file=$1
    resign_helper $file $key_arg ${cmd_opt[output]} ${cmd_opt[verbose]}
    local error_code=$?
    if [[ $error_code != 0  && ${cmd_opt[robust]} != true ]]; then
      echo "ERROR: failed to resign, aborting: $file" >&2
      exit $error_code
    fi
  }

  for file in "${cmd_arg[@]}"; do
    multi_process $file &
  done
  wait
}

######################
# Exported Functions #
######################

main() {
  # Create a temporary directory - will handle cleanup if script crashes or
  # if resign is forcefully closed
  local resign_tmp_dir=$(mktemp -d -t 'resign.XXXXXXXXXX' 2> /dev/null || mktemp -d -t 'resign.XXXXXXXXXX')
  if [[ $? != 0 ]]; then
    echo "ERROR: Cannot create directory - please run this script as sudo"
    exit 1
  fi

  emrg_exit() {
    trap - SIGTERM && kill 0
  }

  norm_exit() {
    local exit_code=$?
    rm -rf "$resign_tmp_dir"
    echo "exiting... ">&2
    exit $exit_code
  }

  trap norm_exit EXIT INT TERM
  trap emrg_exit SIGINT SIGTERM

  local main_args="${@}"

  resign "${main_args[@]}" $resign_tmp_dir
  exit 0
}

main $@