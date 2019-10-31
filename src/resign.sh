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

###########
# GLOBALS #
###########
#SCRIPT_FOLDER="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# The name of this script is its containing folder
#SCRIPT_NAME="$(basename $SCRIPT_FOLDER)"

# cmd context
INPUT=($@)
NUM_ARGS=$#
CMD=
CHECK_CMD=
KEY_CMD=

# options
HELP=false
BACKUP=false
DRY_RUN=false
SAVE_KEY=fakse
VERBOSE=false

# options: check
DELAY=false
NATIVE=false
REMOVE=false
SIGNED=false

# options: key
EXTRACT=false

# argeuemtns
PATH_ARG=

# arguements: check
CHECK_ARG=

# argeuments: key
KEY_ARG=

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
# Name: validate_arguements
# Description: Prepares the arguments and subcommands to resign
# Returns:
#   string - The input parm if valid, else undefined
#######################################
validate_arguements() {
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
                      -assembled assemblies in their intermeidate language form and unsigned assemblies 
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

#########################
# script initialization #
#########################

#######################################
# Initalizes the key sub-command
# Arguments:
#   $1: required(string[]) - The incomming array of arguments
#   $2: required(ref:map[string]string) - The results associative array passed by reference:
#   map[string]string:
#   [
#     "cmd":        - string[]   : resign cmd options and arguements
#     "key":        - string[]   : key cmd options and arguements
#     "check":      - string[]   : check cmd option and arguements
#   ]
#   
# Returns:
#   None
#######################################
init_resign() {
  if [[ $#  == 0 ]]; then
    echo "ERROR: cannot have empty arguements">&2
    return 1
  fi

  local input=($1)
  local -n res=$2
  local cmd_arg="${input[-1]}"
  if [[ $(get_index "$cmd_arg" "c") != -1 || $(get_index "$cmd_arg" "check") != -1 || 
        $(get_index "$cmd_arg" "k") != -1 || $(get_index "$cmd_arg" "key") != -1 ]]; then
    echo "ERROR: poorly formed command: $cmd_arg">&2
    return 1
  elif [[ ( ! -d $cmd_arg ) || ( -f $cmd_arg && ( "${cmd_arg##*.}" != "dll" || "${cmd_arg##*.}" != "exe" ) ) ]]; then
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
      # if check has been suplied and key has not
      local idx_to_remove=$(get_index ${check_cmd[@]} "key")
      if [[ $idx_to_remove == -1 ]]; then
        idx_to_remove=$(get_index ${check_cmd[@]} "k")
      fi
      if [[ $idx_to_remove != -1 ]]; then
        check_cmd=(${check_cmd[@]:0:$idx_to_remove})
      fi
      
      # if key has been suplied and check has not
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
  if [[ ( ! -d $arg ) || ( ( -f $arg ) && ("${arg##*.}" != "dll" && "${arg##*.}" != "exe") ) ]]; then
    echo "ERROR: arguement $1 is not a valid assembly or a directory">&2
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
  arguments=$arg
}

#######################################
# Resign
#   Resigns assemblies
# Globals:
#   CMD         - The base command
#   CHECK_CMD   - The 'check' subcommand
#   KEY_CMD     - The 'key' subcommand
#   PATH_ARG    - The path on which to execute
# Arguments:
#   $@          - The incomming array of inputs
# Returns:
#   None
#######################################
resign() {
  local num_args=$#
  local all_args=$@
  if [[ $# == 0 ]]; then
    usage
    return 1
  fi

  declare -A parsed_input

  declare -A cmd_opt
  local cmd_arg=

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
  local options_sep='--'
  local idx_resign=
  echo "after ${t_key_cmd_inputs[@]}"
  # #if [[  ]]
  # local arrIN=(${IN//;/ })


  # initialize all commands
  init "${parsed_input[cmd]}" cmd_opt cmd_arg
  if [[ $? != 0 ]]; then 
    echo "ERROR: failed to initialize resign">&2
    exit 1
  fi

  echo "cmd opt ${cmd_opt[@]}"
  echo "cmd arg $cmd_arg"

  # check processes files provided to resign
  # TODO: check command
  if [[ ! -z ${parsed_input[check]} ]]; then
    local check_cmd_input=( "${parsed_input[check]}" "$arg" )
    # check "${check_cmd_input[@]}" check_opt check_arg
  elif [[ $(get_index ${all_args[@]} "check") != -1 ]]; then
    usage_check
    exit 1
  fi

  # key handles key creation for resign
  if [[ ! -z ${parsed_input[key]} ]]; then
    key "${parsed_input[key]}" key_opt key_arg
  elif [[ $(get_index ${all_args[@]} "key") != -1 ]]; then
    usage_key
    exit 1
  fi

  exit 0
  # local arr=($@)

  # PATH_ARG=("${arr[-1]}")
  # PATH_ARG=$(validate_arguements $PATH_ARG)
  
  # if [[ -z "$PATH_ARG" ]]; then
  #   echo "ERROR: arguement $1 is not a valid assembly or a directory"
  #   usage
  #   exit 1
  # fi  

  # if [[ ! -z ${check_cmd[@]} ]]; then 
  #   echo "check: ${check_cmd[@]}"
  #   check ${check_cmd[@]}
  #   check_arg=("${check_cmd[-1]}")
  #   echo "check arg: $check_arg"
  # fi

  # if [[ ! -z ${key_cmd[@]} ]]; then
  #   echo "key: ${key_cmd[@]}"
  #   key ${key_cmd[@]}
  #   key_arg=("${key_cmd[-1]}")
  #   echo "check arg: $key_arg"
  # fi

  

  # echo "base: ${CMD[@]}"
  # echo "path: ${PATH_ARG}"

  # #init_resign "${CMD}"

  # if [[ ! -z ${CHECK_CMD[@]} ]]; then 
  #   echo "check: ${CHECK_CMD[@]}"
  #   check ${CHECK_CMD[@]}
  #   CHECK_ARG=("${CHECK_CMD[-1]}")
  #   echo "check arg: $CHECK_ARG"
  # fi

  # if [[ ! -z ${KEY_CMD[@]} ]]; then
  #   echo "key: ${KEY_CMD[@]}"
  #   key ${KEY_CMD[@]}
  #   KEY_ARG=("${KEY_CMD[-1]}")
  #   echo "check arg: $KEY_ARG"
  # fi

  # echo "HELP: $HELP"
  # echo "BACKUP: $BACKUP"
  # echo "DRY_RUN: $DRY_RUN"
  # echo "SAVE_KEY: $SAVE_KEY"
  # echo "VERBOSE: $VERBOSE"

  # # options: check
  # echo "DELAY: $DELAY"
  # echo "NATIVE: $NATIVE"
  # echo "REMOVE: $REMOVE"
  # echo "SIGNED: $SIGNED"

  # # options: key
  # echo "EXTRACT: $EXTRACT"
}

# usage_check() {
#   case "$1" in
#   -h | --help ) printf '
#     Usage: check [options] <pattern>

#       Only sign the assembly(s) if they pass a binary condition
    
#     Options:
#       -h|--help         Display this help message
#       -d|--delay        Sign the assemblies which are delay signed
#       -n|--native       Check for native assemblies - if paired with -r|--remove will remove these binaries
#       -r|--remove       Remove assemblies which match this check
#       -s|--signed       Sign the assemblies which are signed
    
#     pattern:
#       A regex pattern
#     \n'
#     exit 0
#     ;;
#   * ) printf '
#     Usage: check [options] <pattern>

#       Only sign the assembly(s) if they pass a binary condition

#     Options:
#       -h|--help       Display help message
#     \n'
#     exit 1
#     ;;
#   esac
# }

# usage_key() {
#   case "$1" in
#   -h | --help ) printf '
#     k|key [options] <path-to-key-source>
    
#       Provide resign a key with which to resign the given assembly(s)

#     Options:
#       -h|--help         Display this help message
#       -e|--extract      Instead of .snk, extracts the public snk from a given assembly
#                         - replace path-to-key-source with a signed assembly
#                         NOTE: Will only apply the public key, resulting in a delay-signed only assembly
    
#     path-to-key-source:
#       The .snk or .dll to sign with
#     \n'
#     exit 0
#     ;;
#   * ) printf '
#     k|key [options] <path-to-key-source>
    
#       Provide resign a key with which to resign the given assembly(s)

#     Options:
#       -h|--help         Display help message
#     \n'
#     exit 1
#     ;;
#   esac
# }

function compose() {
  echo "composing $PATH_ARG"

}

function decompose() {
    echo "decomposing $PATH_ARG"

}

function sign() {
  echo "signing $PATH_ARG"

}

function report() {
  echo "reporting $PATH_ARG"

}

function generate_new_snk() {
  echo "generating new snk $PATH_ARG"
}

function analyze_package() {
  printf "Begin analyzing assemblies in for $1\n"

  for entry in $(du -a $1 | grep .dll | cut -f2-) 
  do
    printf "Analyzing $entry\n"
  done
}

main() {
  resign $@
}

#analyze_package $PATH_ARG
#main $@

#tester
# results=
# all_args=$@
# init_resign "${all_args[@]}" results
# echo "results ${results[@]}"
main $@
#validate_options $@

#ilasm
#ikdasm