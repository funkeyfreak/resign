#! /bin/bash
#
# key: Implements the key sub-command
#

#================================================================
# HEADER
#================================================================
# Required Libraries:
# basename
# getopt -- GCC library
# TODO: Complete required libraries

###########
# Imports #
###########

# TODO: move to global-scoped script AND use uname to determine if on windows
[ -x "$(uuidgen -h 2> /dev/null)" ] || alias uuidgen='powershell -command "[guid]::newguid().Guid"|xargs'

####################
# Helper Functions #
####################

#######################################
# Gets the checksum for a given file
# Arguments:
#   $1: required(string)  - The path to the file to fetch the checksum
# Returns:
#   string - The calculated checksum
#######################################
get_file_checksum() {
  echo "$(shasum $1 | cut -d ' ' -f1)"
}

#######################################
# Generates a snk given a key name
# Arguments:
#   $1: required(string)  - The name of the new key
#   $2: optional(string)  - The directory in which to place the new key 
#   $3: optional(bool)    - If true, print verbose logs
#   
# Returns:
#   None
#######################################
generate_snk() {
  local key_name=$1
  local output_dir=$2
  local verbose=false
  
  # validate params
  if [[ -z $key_name ]]; then
    echo "ERROR: please provide a key name"
    return 1
  fi

  if [[ ! -d $output_dir && ! -z $output_dir ]]; then
    echo "ERROR: invalid output directory: $output_dir"
    return 1
  elif [[ -z $output_dir ]]; then
    output_dir="$(pwd)"
  fi

  if [[ ! -z $3 && $3 == true ]]; then 
    verbose=true
  fi

  # TODO: Clean-up
  sn $( if [[ $verbose != true ]]; then echo "-q"; fi ) -k "$output_dir/$key_name.snk">&2 
}

#######################################
# Extracts the public key from a dll, exe, and snk file
# NOTE: The public key is placed in $output/$file_containing_key(name)_public_key.snk
#   If changes are made to this function, please make sure to update all references
# Arguments:
#   $1: required(string)  - The file to extract the pulbic key from
#   $2: optional(string)  - The directory in which to place the new key 
#   $3: optional(bool)    - If true, print verbose logs
#   
# Returns:
#   None
#######################################
extract_public_key() {
  local file_containing_key=$1
  local output=$2
  local verbose=$3

  local file_containing_key_fullname="$(basename "${1}")"
  local file_containing_key_ext="${1##*.}"
  local file_containing_key_name="${file_containing_key_fullname%.*}"

  local public_key_name="${file_containing_key_name}_public-key.snk"
 
  if [[ ! -d $output && ! -z $output ]]; then
    echo "ERROR: invalid value provided for the output dir: $2">&2
    return 1 
  elif [[ -z $output ]]; then
    output="$(pwd)"
  fi

  # clean-up if-statement
  if [[ -f $file_containing_key ]]; then
    if [[ $file_containing_key_ext == "ext" || $file_containing_key_ext = "dll" ]]; then
      sn $( if [[ $verbose != true ]]; then echo "-q"; fi ) -e "$file_containing_key" "$output/$public_key_name">&2 
    elif [[ $file_containing_key_ext == "snk" ]]; then
      sn $( if [[ $verbose != true ]]; then echo "-q"; fi ) -p "$file_containing_key" "$output/$public_key_name">&2 
    else
      echo "ERROR: the provided file is not supported by extract_public_key: $file_containing_key">&2
      return 1
    fi
  else
    echo "ERROR: the provided argument to extract_public_key is invalid: $file_containing_key">&2
    return 1
  fi
}

#######################################
# Helps to determine if a given snk is a public, private snk key-pair.
# Arguments:
#   $1: required(string)  - The file to extract the pulbic key from
#   $2: optional(string)  - The directory in which to place the new key 
#   $3: optional(bool)    - If true, print verbose logs
#   
# Returns:
#   None
#######################################
snk_is_public_private_pair() {
  local file_containing_key=$1
  local verbose=$2
  local tmp_dir="$(pwd)/$(uuidgen)"
  mkdir -p $tmp_dir>&2 

  local file_containing_key_fullname="$(basename "${1}")"
  local file_containing_key_ext="${1##*.}"
  local file_containing_key_name="${file_containing_key_fullname%.*}"
  local tmp_public_key="$tmp_dir/${file_containing_key_name}_public-key.snk"

  local public_key_checksum=
  local private_key_checksum=

  if [[ ! -f $file_containing_key || $file_containing_key_ext != "snk" ]]; then
    echo "ERROR: the provided argument to snk_is_public_private_pair is invalid: $file_containing_key_ext">&2
    return 1
  fi

  extract_public_key $file_containing_key $tmp_dir $verbose
  
  public_key_checksum="$(get_file_checksum $tmp_public_key)"
  private_key_checksum="$(get_file_checksum $file_containing_key)"
  rm -rf $tmp_dir &
  if [[ "$public_key_checksum" != "$private_key_checksum" ]]; then
    true
  else
    false
  fi 
}

#######################################
# Prints the usage text for the key sub-command
# Arguments:
#   $1: string(optional) - If provided flag is -h|--help, usage_key will print out additional information
# Returns:
#   None
#######################################
usage_key() {
  case "$1" in
  -h | --help ) printf '
    Usage: k|key [options] [<path-to-key-source>]
    
      Provide resign a key with which to strongname resign the given assembly(s)

    Options:
      -h|--help         Display this help message
  
      -g|--generate     Generate a new key
                        NOTE: Will not work if path-to-key-source is provided
      -k|--keep         Save all key artifacts - will be available in the root 
                        of the output directory
      -p|--public       Sign the assembly only using the public key (delay-sign). 
                        If used with -g|--generate and -s|--save, the private key 
                        will be saved to the output directory. Will be ignored if
                        <path-to-key-soruce> only contains a public key

    path-to-key-source:
      (optional) The .snk assembly [.dll|.snk] to sign with

    Examples:
      key ./some-assembly.[dll|exe]   - Will sign the assemblies with the public-key 
                                        extracted from ./some-assembly.[dll|exe]
      key ./some.snk                  - Will strong-name sign the assembly(s) with 
                                        the public-private key given by ./some.snk
                                        NOTE: If the provided key is not a public/
                                        private pair, an error will be thrown
      key -g                          - Will strong-name sign the assembly(s) with 
                                        a newly generated snk
      key -p ./some.snk               - Will sign the assemblies with the public-key
                                        in ./some.snk
    \n'>&2 
    ;;
  * ) printf '
    Usage: k|key [options] [<path-to-key-source>]
    
      Provide resign a key with which to resign the given assembly(s)

    Options:
      -h|--help         Display help message
    \n'>&2 
    ;;
  esac
}

#######################################
# Initializes the key sub-command
# Arguments:
#   $@: required(string[]) - The incoming array of arguments
# Returns:
#   string[] - An array of strings representing the parsed options
#######################################
getopt_key() {
  echo "$(getopt -o hgko:pv -l help,generate,keep,output:,public,verbose -n 'key' -- "$@")"
}

######################
# Exported Functions #
######################

#######################################
# Initializes the key sub-command
# Arguments:
#   $1: required(string[]) - The incoming array of arguments
#   $2: required(ref:map[string]string) - The map of validated options
#     map[string]string:
#     [
#       "generate":    - bool: The generate flag
#       "keep":        - bool: The keep flag
#       "public":      - bool: The public flag
#     ]
#   $3: required(ref:string) - The key to use during resigning
#   $4: optional(bool) - The output directory
#   $5: optional(bool) - Enable verbose output
# Returns:
#   None
# NOTE:
#   This command uses the following hidden flags:
#   -v|--verbose  - Enables verbose logging
#   -o|--output   - The output directory
#######################################
key() {
  # set all inputs to local args & pass-by-reference args
  declare -A t_options
  local t_arguments=
  local echo_output_enabled=false
  if [[ -z $2 && -z $3 ]]; then
    echo_output_enabled=true
  fi

  local input=($1)
  local -n options=${2:-t_options}
  local -n arguments=${3:-t_arguments}

  # temp helper variables
  local help=false
  local generate=false
  local keep=false
  local output=$4
  local public=false
  local verbose=$5

  local opts=

  if ! opts=$(getopt_key "${input[@]}"); then  #$(getopt -o hgko:pv -l help,generate,keep,output:,public,verbose -n 'key' -- "${input[@]}"); then 
    echo "failed parsing options: ${input[@]}" >&2; usage_key; return 1;
  fi

  eval set -- "$opts"
  unset opts

  while true; do
    case "$1" in
      -h | --help ) help=true; shift ;;
      -g | --generate ) generate=true; shift ;;
      -k | --keep ) keep=true; shift ;;
      -o | --output ) output="${output:-$2}"; shift 2 ;;
      -p | --public ) public=true; shift ;;
      -v | --verbose ) verbose=${verbose:-true}; shift ;;
      -- ) shift; break ;;
      * ) break ;;
    esac
  done

  if [[ $help == true ]]; then
    usage_key "-h"
    exit 0
  fi

  local key_source_path="$@"
  local key_source="$(basename "$key_source_path")" 2> /dev/null
  local key_source_ext="${key_source_path##*.}"
  local key_source_name="${key_source%.*}"

  # validate arguments
  if [[ $# > 1 ]]; then
		echo "ERROR: too many arguments provided to key: $key_source_path">&2
    usage_key
		return 1
	elif [[ (! -f $key_source_path && ! -z $key_source_path) && ($key_source_ext != "dll" && $key_source_ext != "exe" && $key_source_ext != "snk") ]]; then
    echo "ERROR: the key source is not accepted, please provide .dll, .exe, or .snk: $key_source_ext">&2
    usage_key
    return 1
  elif [[ ! -z $key_source_path && $generate == true ]]; then
    echo "ERROR: cannot generate a new key when one is given">&2
    usage_key
    return 1
  elif [[ -z $key_source_path && $generate != true ]]; then
    echo "ERROR: key-containing file not provided">&2
    usage_key
    return 1
  fi

  # validate options
  if [[ -z $output ]]; then
    output="$(pwd)"
  elif [[ ! -d $output ]]; then
    echo "ERROR: output is not a directory: $output">&2
    usage_key
    return 1
	fi

  # values to retrun
  local key=$key_source_path
  local key_output="$output/key"
  mkdir -p $key_output
  
  # extract/create the key
  local extracted_from_assembly=false
  if [[ $key_source_ext == "dll" || $key_source_ext == "exe" ]]; then
    extract_public_key $key_source_path $key_output $verbose
    local pub_key="$key_output/${key_source_name}_public-key.snk"
    key="$key_output/$key_source_name.snk"
    mv -f "$pub_key" "$key"
    extracted_from_assembly=true
  elif [[ $key_source_ext != "snk" && $generate == true ]]; then
    local generated_snk_name="$(uuidgen)_generated"
    generate_snk $generated_snk_name $key_output $verbose
    key="$key_output/$generated_snk_name.snk"
  elif [[ $key_source_ext == "snk" ]]; then 
    cp -f $key $key_output 2> /dev/null
  fi
  
  # handle public flag
  if [[ $public == true && $extracted_from_assembly != true ]]; then
    if snk_is_public_private_pair $key $verbose; then
      local pub_key="${key%.*}_public-key.snk"
      extract_public_key $key $key_output $verbose
      # if keep is not true, delete the private key
      $keep || rm -f $key

      key=$pub_key
    fi
  fi

  options["generate"]=$generate
  options["keep"]=$keep
  options["public"]=$public
  arguments=$key
  
  if [[ $echo_output_enabled == true ]]; then
    for i in "${!options[@]}"; do
      echo $i ${options[$i]}
    done
    echo "key $key"
  fi
}