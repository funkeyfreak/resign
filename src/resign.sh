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
. ../lib/assemblr/assemblr.sh

###########
# GLOBALS #
###########

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

prep_commands() {
  local loc_cmd=("${INPUT[@]}")

  local idx_cmd_check="$(get_index $@ "c")"
  if [[ $idx_cmd_check == -1 ]]; then
      idx_cmd_check="$(get_index $@ "check")"
  fi

  local idx_cmd_key="$(get_index $@ "k")"
  if [[ $idx_cmd_key == -1 ]]; then
      idx_cmd_key="$(get_index $@ "key")"
  fi

  # process base-command
  if [[ $idx_cmd_check != $idx_cmd_key ]]; then
    local idx_cmd_end=$(($idx_cmd_check > $idx_cmd_key ? $idx_cmd_check : $idx_cmd_key))
    CMD=(${loc_cmd[@]:0:$idx_cmd_end})
  else
    CMD=($@)
  fi

  # process sub-commands
  unset 'loc_cmd[${#loc_cmd[@]}-1]'
  if [[ $idx_cmd_check != $idx_cmd_key ]]; then
    local end_of_cmd=$(($NUM_ARGS-1))

    # if either of the sub-commands exists, go ahead and set the appropriate CMD
    if [[ $idx_cmd_check != -1 ]]; then
        CHECK_CMD=(${loc_cmd[@]:$(($idx_cmd_check+1)):$end_of_cmd})
    fi
    if [[ $idx_cmd_key != -1 ]]; then
        KEY_CMD=(${loc_cmd[@]:$(($idx_cmd_key+1)):$end_of_cmd})
    fi

    # if both sub-commands are set, we need to find and remove the overlap    
    if [[ ${CHECK_CMD[@]} && ${CHECK_CMD[@]-x} ]] && [[ ${KEY_CMD[@]} && ${KEY_CMD[@]-x} ]]; then
      # if check has been suplied and key has not
      local idx_to_remove=$(get_index ${CHECK_CMD[@]} "key")
      if [[ $idx_to_remove == -1 ]]; then
        idx_to_remove=$(get_index ${CHECK_CMD[@]} "k")
      fi
      if [[ $idx_to_remove != -1 ]]; then
          CHECK_CMD=(${CHECK_CMD[@]:0:$idx_to_remove})
      fi
      
      # if key has been suplied and check has not
      idx_to_remove=$(get_index ${KEY_CMD[@]} "check")
      if [[ idx_to_remove == -1 ]]; then
        idx_to_remove=$(get_index ${KEY_CMD[@]} "c")
      fi
      if [ $idx_to_remove != -1 ]; then 
          KEY_CMD=(${KEY_CMD[@]:0:$idx_to_remove})
      fi
    fi
  fi
}

check_path() {
  local path="$1"
  if [[ ( -f $path ) && ( ! -d $path ) && ("${path##*.}" != "dll" && "${path##*.}" != "exe") ]]; then
    path=
  fi

  echo $path
}

#########################
# script initialization #
#########################

init_resign() {
  OPTS=`getopt -o h::bdsv --long help::,backup,dry-run,save-key,verbose -n 'resign' -- "$@"`

  if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi

  echo "all ${OPTS[@]}"
  echo "$optstring  "
  eval set -- "$OPTS"

  local test_value=

  while true; do
    case "$1" in
      -h | --help ) HELP=true; echo "lala $optarg - $@";if [[ ! -z $2 ]]; then test_value=$2; shift 2; else test_value=true; shift; fi ;;
      -b | --backup ) BACKUP=true; shift ;;
      -d | --dry-run ) DRY_RUN=true; shift ;;
      -s | --save-key ) SAVE_KEY=true; shift ;;
      -v | --verbose ) VERBOSE=true; shift ;;
      -- ) shift; break ;;
      * ) break ;;
    esac
  done

  echo "test_Value is $test_value"
  
  if [[ $HELP == true ]]; then
    usage --help
  fi
}

init_check() {
  OPTS=`getopt -o hdnrs --long help,delay,native,remove,signed -n 'check' -- "$@"`

  if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi

  eval set -- "$OPTS"

  while true; do
    case "$1" in
      -h | --help ) HELP=true; shift ;;
      -d | --delay ) DELAY=true; shift ;;
      -n | --native ) NATIVE=true; shift ;;
      -r | --remove ) REMOVE=true; shift ;;
      -s | --signed ) SIGNED=true; shift ;;
      -- ) shift; break ;;
      * ) break ;;
    esac
  done

  if [[ $HELP == true ]]; then
    usage_check "-h"
  fi
}

init_key() {
  OPTS=`getopt -o he --long help,extract -n 'key' -- "$@"`

  if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi

  eval set -- "$OPTS"

  while true; do
    case "$1" in
      -h | --help ) HELP=true; shift ;;
      -e | --extract ) EXTRACT=true; shift ;;
      -- ) shift; break ;;
      * ) break ;;
    esac
  done

  if [[ $HELP == true ]]; then
    usage_key "-h"
  fi
}

#######################################
# Main init function
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
init() {
  prep_commands $@ 

  local arr=($@)

  PATH_ARG=("${arr[-1]}")
  PATH_ARG=$(check_path $PATH_ARG)
  
  if [[ -z "$PATH_ARG" ]]; then
    echo "ERROR: arguement $1 is not a valid assembly or a directory"
    usage
    exit 1
  fi  

  echo "base: ${CMD[@]}"
  echo "path: ${PATH_ARG}"

  init_resign "${CMD}"

  if [[ ! -z ${CHECK_CMD[@]} ]]; then 
    echo "check: ${CHECK_CMD[@]}"
    init_check ${CHECK_CMD[@]}
    CHECK_ARG=("${CHECK_CMD[-1]}")
    echo "please? ${#CHECK_ARG[@]}"
    echo "check arg: $CHECK_ARG"
  fi

  if [[ ! -z ${KEY_CMD[@]} ]]; then
    echo "key: ${KEY_CMD[@]}"
    init_key ${KEY_CMD[@]}
    KEY_ARG=("${KEY_CMD[-1]}")
    echo "check arg: $KEY_ARG"
  fi

  echo "HELP: $HELP"
  echo "BACKUP: $BACKUP"
  echo "DRY_RUN: $DRY_RUN"
  echo "SAVE_KEY: $SAVE_KEY"
  echo "VERBOSE: $VERBOSE"

  # options: check
  echo "DELAY: $DELAY"
  echo "NATIVE: $NATIVE"
  echo "REMOVE: $REMOVE"
  echo "SIGNED: $SIGNED"

  # options: key
  echo "EXTRACT: $EXTRACT"
}

usage() {
  case "$1" in
  [-h] | [--help] ) printf '
    Usage:  resign [options] [<command(s)>] <path-to-assembly(s)>
      
      Resign assembly(s) from a given path

    Options:
      -h|--help       Display this help message
      -b|--backup     Backup the folder before processing - will be named <path-to-assembly(s)>.backup.zip
      -d|--dry-run    Dry-run - prints the assemblies which will be signed
      -s|--save-key   Saves the key to path-do-assembly(s)
      -v|--verbose    Verbose output
          
    Command(s):
      check         Run a check on the assemblies before signing
      key           Instead of generating a new snk, sign with this given key

    path-to-key-source:
      The path to a .snk/key source with which to sign the assembly(s)

    path-to-assembly(s):
      The path to the assembly/folder containing assembly(s)
      NOTE: Signing will only work on managed .dll(s), as native assemblies do not have the ability to be signed

    \n'
    exit 0
    ;;
  *) printf '
    Usage:  resign [options] <path-to-assembly(s)>
      
      Resign assembly(s) given an snk

    Options:
      -h|--help       Display a help message

    path-to-assembly(s):
      The path to the assembly/folder containing assemblies
    \n'
    exit 1
    ;;
  esac
}

usage_check() {
  case "$1" in
  -h | --help ) printf '
    Usage: check [options] <pattern>

      Only sign the assembly(s) if they pass a binary condition
    
    Options:
      -h|--help         Display this help message
      -d|--delay        Sign the assemblies which are delay signed
      -n|--native       Check for native assemblies - if paired with -r|--remove will remove these binaries
      -r|--remove       Remove assemblies which match this check
      -s|--signed       Sign the assemblies which are signed
    
    pattern:
      A regex pattern
    \n'
    exit 0
    ;;
  * ) printf '
    Usage: check [options] <pattern>

      Only sign the assembly(s) if they pass a binary condition

    Options:
      -h|--help       Display help message
    \n'
    exit 1
    ;;
  esac
}

usage_key() {
  case "$1" in
  -h | --help ) printf '
    k|key [options] <path-to-key-source>
    
      Provide resign a key with which to resign the given assembly(s)

    Options:
      -h|--help         Display this help message
      -e|--extract      Instead of .snk, extracts the public snk from a given assembly
                        - replace path-to-key-source with a signed assembly
                        NOTE: Will only apply the public key, resulting in a delay-signed only assembly
    
    path-to-key-source:
      The .snk or .dll to sign with
    \n'
    exit 0
    ;;
  * ) printf '
    k|key [options] <path-to-key-source>
    
      Provide resign a key with which to resign the given assembly(s)

    Options:
      -h|--help         Display help message
    \n'
    exit 1
    ;;
  esac
}

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

#analyze_package $PATH_ARG

init $@
main $@
#prep_commands $@

#ilasm
#ikdasm