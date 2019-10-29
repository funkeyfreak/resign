#! /bin/bash
#
# key: Implements the key sub-command
#

#================================================================
# HEADER
#================================================================

get_thumbprint() {
  local thumbprint
  local assembly_ext="${1##*.}"
  if [[ $assembly_ext == "snk" ]]; then
    thumbprint=$(sn -q -t "$1" | head -n1)
  else
    thumbprint=$(sn -q -T "$1" | head -n1)
  fi
  echo "${thumbprint:18}"
}

get_public_key() {
  local public_key=
  local assembly_ext="${1##*.}"
  if [[ $assembly_ext == "snk" ]]; then
    public_key=$(sn -q -tp "$1" | head -n6 | tail -n5 |  awk '{print}' ORS='')
  else
    public_key=$(sn -q -Tp "$1" | head -n6 | tail -n5 |  awk '{print}' ORS='')
  fi
  echo "$public_key"
}

save_public_key_to_snk() {
  local assembly=$(basename "${1}")
  local assembly_name="${assembly%.*}"
  local assembly_ext="${1##*.}"
  if [[ $assembly_ext == "snk" ]]; then
    sn -q -p $1 "$2/$assembly_name.snk"
  else
    sn -q -e $1 "$2/$assembly_name.snk"
  fi
}

public_snk_file_checksums_match() {
  # TODO: Use mktempdir's using block
  local work_dir="$(whoami | shasum | cut -d " " -f1)_public_snk_file_checksums_match/"
  mkdir -p $work_dir

  save_public_key_to_snk $1 $work_dir &
  save_public_key_to_snk $2 $work_dir &
  wait

  local file_basename=

  file_basename=$(basename "${1}")
  local first_file_snk="$work_dir/${file_basename%.*}.snk"

  file_basename=$(basename "${2}")
  local second_file_snk="$work_dir/${file_basename%.*}.snk"

  local first_file_snk_checksum=$(get_file_checksum $first_file_snk)
  local second_file_snk_checksum=$(get_file_checksum $second_file_snk)
  
  # clean-up tmp dir in a seperate thread
  # TODO: Use mktempdir's using closure
  rm -rf $work_dir &

  if [[ $first_file_snk_checksum == $second_file_snk_checksum ]]; then
    true
  else
    false
  fi
}

public_keys_match() {
  local first_snk_public_key=$(get_public_key $1)
  local second_snk_public_key=$(get_public_key $2)

  if [[ $first_snk_public_key == $second_snk_public_key ]]; then
    true
  else
    false
  fi
}

thumbprints_match() {
  local first_snk_thumbprint=$(get_thumbprint $1)
  local second_snk_thumbprint=$(get_thumbprint $2)

  if [[ $first_snk_thumbprint == $second_snk_thumbprint ]]; then
    true
  else
    false
  fi
}

snks_are_compatable() {
  if thumbprints_match $1 $2 && public_keys_match $1 $2 && public_snk_file_checksums_match $1 $2; then
    true
  else
    false
  fi
}

#######################################
# Gets the checksum for a given file
# Arguments:
#   $1: required(string)  - The path to the file to fetch the checksum
# Returns:
#   string - The calculated checksum
#######################################
get_file_checksum() {
  shasum $1 | cut -d ' ' -f1
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
  else
    output_dir=$(pwd)
  fi

  if [[ ! -z $3 && $3 == true ]]; then 
    verbose=true
  fi

  # TODO: Clean-up
  sn $( if [[ $verbose != true ]]; then echo "-q"; fi ) -k "$output_dir/$key_name.snk"
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

  local file_containing_key_fullname=$(basename "${1}")
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
      sn $( if [[ $verbose != true ]]; then echo "-q"; fi ) -e "$file_containing_key" "$output/$public_key_name"
    elif [[ $file_containing_key_ext == "snk" ]]; then
      sn $( if [[ $verbose != true ]]; then echo "-q"; fi ) -p "$file_containing_key" "$output/$public_key_name"
    else
      echo "ERROR: the provided file is not supported by extract_public_key: $file_containing_key">&2
      return 1
    fi
  else
    echo "ERROR: the provided arguement to extract_public_key is invalid: $file_containing_key">&2
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
  mkdir -p $tmp_dir

  local file_containing_key_fullname=$(basename "${1}")
  local file_containing_key_ext="${1##*.}"
  local file_containing_key_name="${file_containing_key_fullname%.*}"
  local tmp_public_key="$tmp_dir/${file_containing_key_name}_public-key.snk"

  local public_key_checksum=
  local private_key_checksum=

  if [[ ! -f $file_containing_key || $file_containing_key_ext != "snk" ]]; then
    echo "ERROR: the provided arguement to snk_is_public_private_pair is invalid: $file_containing_key">&2
    return 1
  fi

  extract_public_key $file_containing_key $tmp_dir $verbose
  
  public_key_checksum=$(get_file_checksum $tmp_public_key)
  private_key_checksum=$(get_file_checksum $file_containing_key)
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
    \n'
    #-s|--strong       UTILITY FUNCTION:
    #                    Denotes a .snk containing a private-key to strong-name sign
    #                    the assemblies if the provided <path-to-key-soruce> does not
    #                    contain a private key. The thumbprints and public-keys of the 
    #                    provided key and <path-to-key-source> must be equivalent
    #                    NOTE: The default behavour of k|key is to strong name sign
    #                    using the source in <path-to-key-source>, this is a way to 
    #                    provide a .dll and its private key equivilant
    #                    NOTE: Since -s|--strong is an optional command, if a 
    #                    value is being provided, it must be quoted and 
    #                    directly adjacent to -s|--strong, e.g.: -s"./some-key.snk"
    #-s|--strong       Strong-name sign the assembly. The default behaviour of 
    #                    key is to sign only with the public key
    #-e|--extract      Extract the public snk from a given assembly or
    #                    snk and signs the assemblies with this key
    #                    NOTE: Since -e|--extract is an optional command, if a 
    #                    value is being provided, it must be quoted and 
    #                    directly adjacent to -e|--extract, e.g.: -e"./some-key.snk"
    #                    NOTE: Will only sign the assemblies with the public key. 
    #                    In order to strong-name sign, you will need to include 
    #                    the -s|--strong flag and a key containing the private 
    #                    key as well. To this end, a key can be provided to this
    #                    option which contains the public key. However,
    #                    If -e|--extract is used without a <path-to-key-source>,
    #                    the given assembly will be delay signed
    return 0
    ;;
  * ) printf '
    Usage: k|key [options] [<path-to-key-source>]
    
      Provide resign a key with which to resign the given assembly(s)

    Options:
      -h|--help         Display help message
    \n'
    return 1
    ;;
  esac
}

#######################################
# Initalizes the key sub-command
# Arguments:
#   $@: optional(string[]) - The incomming array of arguments
#   
# Returns:
#   [
#     0: keep   - boolean   : The -k|--keep flag
#     1: public - boolean   : The -p|--public flag
#     2: key    - string    : The path to the key file
#   ]
# NOTE:
#   This command uses the following hidden flags:
#   -v|--verbose  - Enables verbose logging
#   -o|--output   - The output directory
#######################################
init_key() {
  local help=false
  local generate=false
  local keep=false
  local output=
  local public=false
  local strong=false
  local verbose=false

  #local opts=`getopt -o hgko:ps::v --long help,generate,keep,output:,public,strong::,verbose -n 'key' -- "$@"`
  local opts=`getopt -o hgko:pv --long help,generate,keep,output:,public,verbose -n 'key' -- "$@"`

  if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi
  echo "$@"

  eval set -- "$opts"
  

  while true; do
    case "$1" in
      -h | --help ) help=true; shift ;;
      -g | --generate ) generate=true; shift ;;
      -k | --keep ) keep=true; shift ;;
      -o | --output ) output="$2"; shift 2 ;;
      -p | --public ) public=true; shift ;;
      #-s | --strong ) if [[ ! -z $2 ]]; then strong="$2"; shift 2; else strong=true; shift; fi; ;;
      -v | --verbose ) verbose=true; shift ;;
      -- ) shift; break ;;
      * ) break ;;
    esac
  done

  if [[ $HELP == true ]]; then
    usage_key "-h"
    return 0
  fi

  # argument metadata storage
  #local strong_key=
  #local strong_ext=
  #local strong_name=
  #if [[ $strong != false && -f $strong ]]; then
  #  strong_key=$(basename "${strong}")
  #  strong_ext="${strong##*.}"
  #  strong_name="${strong_key%.*}"
  #fi

  local key_source=$(basename "${@}")
  local key_source_ext="${@##*.}"
  local key_source_name="${key_source%.*}"
  local key_source_path="$@"

  # validate arguements
  if [[ $# > 1 ]]; then
    echo "$#"
    echo "$@"
		echo "ERROR: too many arguments provided to init_key: $@">&2
		return 1
	elif [[ (! -f $@ && ! -z $@) || ($key_source_ext != "dll" && $key_source_ext != "exe" && $key_source_ext != "snk") ]]; then
    echo "ERROR: the key source is not accepted, please provide .dll, .exe, or .snk: $key_source_ext">&2
    return 1
  fi

  # validate options
  if [[ -z $output ]]; then
    output=$(pwd)
  elif [[ ! -d $output ]]; then
    echo "ERROR: output is not a directory: $output">&2
    exit 1
	fi

  # key -sd
  #if [[ $strong != false && $public == true ]]; then
  #  echo "ERROR: invalid options combination -s|--strong and -p|--public - please use -h|--help for more details">&2
  #  return 1
  # key -s=/some/file.ext
  #elif [[ ( $strong != true && $strong != false) && (! -f $strong || $strong_ext != "snk") ]]; then
  #  echo "ERROR: provided input for -s|--strong signing is not a valid snk: $strong">&2
  #  return 1
  # key -sg, key -s /path/to/strong/name/key.snk, key -s=/path/to/strong/name/key.snk -g
  #elif [[ ($strong == true && $generate == true && ! -z $key_soruce) || (-f $strong && $key_source_ext == "snk" ) ||
  #  ( -f $strong && $generate == true ) ]]; then
  #  echo "ERROR: cannot strongname sign - public keys will not match">&2
  #  return 1
  # key -s /path/to/assembly.[dll|ext]
  #elif [[ $strong == true && $key_source_ext != "snk" && $generate != true ]]; then
  #  echo "ERROR: strongname signing without providing a key is not possible - please use -g|--generate to generate a new key, or provide a .snk as the <path-to-key-source> argument">&2
  #  return 1
  #fi

  # we preform three phases of checking against incoming keys
  # 1. thumbprints match
  # 2. public key tokens match
  # 3. snk sha1s match
  # see snks_are_compatable for more details
  # key -s=/path/to/strong/name/key.snk path/to/assembly/or/snk.[dll|exe|snk]
  #if [[ -f $strong && -f $key_source ]] && ! snks_are_compatable $strong $key_soruce; then
  #  echo "ERROR: strongname signing is not possible if the public keys in both files do not match">&2
  #  return 1
  #fi

  # TODO: verify that the snk provided through -s|--strong is an snk with a private key

  # valid outcomes:
  # k -gs 

  # We want to warn the user if they've passed a snk which contains only a public key. 
  #validate_snk_is_public_private_pair()

  # values to retrun
  local key=$key_source_path
  local key_output="$output/key"
  mkdir -p $key_output
  
  # extract/create the key
  local extracted_from_assembly=false
  if [[ $key_source_ext == "dll" || $key_source_ext == "exe" ]]; then
    extract_public_key $key_source_path $key_output $verbose
    key="${key_source_path%.*}_public_key.snk"
    extracted_from_assembly=true
  elif [[ $key_source_ext != "snk" && $generate == true ]]; then
    local generated_snk="$key_soruce_name_$(uuidgen)_generated"
    generate_snk $generated_snk $key_output $verbose
    key="$key_output/$generated_snk.snk"
  elif [[ $key_source_ext == "snk" ]]; then 
    cp -f $key $key_output 2> /dev/null
  fi
  
  # handle public flag
  if [[ $public == true && $extracted_from_assembly != true ]]; then
    if snk_is_public_private_pair $key $verbose; then
      extract_public_key $key $key_output $verbose
    fi
  fi

  declare -a results
  results=( $keep $public $key );

  echo "${results[@]}"
}

init_key $@