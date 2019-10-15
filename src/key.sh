#! /bin/bash
#
# key: Implements the key sub-command
#

#================================================================
# HEADER
#================================================================

extract_public_key() {
  local 
}

get_thumbprint() {
  local thumbprint
  local assembly_ext="${@##*.}"
  if [[ $assembly_ext == "snk" ]]; then
    thumbprint=
  else
    thumbprint=$(sn -q -T "$1" | head -n1)
  fi
  echo "${thumbprint:18}"
}

get_public_key() {
  local public_key=$(sn -q -Tp "$1" | head -n6 | tail -n5 |  awk '{print}' ORS='')
  echo "$public_key"
}

public_snks_match() {
  echo "" 
}

public_keys_match() {
  local first_snk_public_key=$(get_public_key $1)
  local 
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

valid_snks_are_compatable() {
  echo ""
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
    
      Provide resign a key with which to resign the given assembly(s)

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
      -s|--strong       Denotes a .snk containing a private-key to strong-name sign
                        the assemblies if the provided <path-to-key-soruce> does not
                        contain a private key. The thumbprints and public-keys of the 
                        provided key and <path-to-key-source> must be equivalent
                        NOTE: Since -s|--strong is an optional command, if a 
                        value is being provided, it must be quoted and 
                        directly adjacent to -s|--strong, e.g.: -s"./some-key.snk"

    path-to-key-source:
      (optional) The .snk assembly [.dll|.snk] to sign with

    Examples:
      k|key ./some-assembly.[dll|exe]   - Will sign the assemblies with the public-key 
                                          extracted from ./some-assembly.[dll|exe]
    \n'
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
    exit 0
    ;;
  * ) printf '
    Usage: k|key [options] [<path-to-key-source>]
    
      Provide resign a key with which to resign the given assembly(s)

    Options:
      -h|--help         Display help message
    \n'
    exit 1
    ;;
  esac
}

#######################################
# Initalizes the key sub-command
# Arguments:
#   $@: optional(string[]) - The incomming array of arguments
#   
# Returns:
#   None
# NOTE:
#   This command uses the following hidden flags:
#   -v|--verbose  - Enables verbose logging
#   -o|--output   - The output directory
#######################################
inti_key() {
  local help=false
  local generate=false
  local keep=false
  local output=
  local public=false
  local strong=false
  local verbose=false

  local opts=`getopt -o hgko:ps::v --long help,generate,keep,output:,public,strong::,verbose -n 'key' -- "$@"`

  if [ $? != 0 ] ; then echo "Failed parsing options." >&2 ; exit 1 ; fi

  eval set -- "$opts"

  while true; do
    case "$1" in
      -h | --help ) help=true; shift ;;
      -g | --generate ) generate=true; shift ;;
      -k | --keep ) keep=true; shift ;;
      -o | --output ) output="$2"; shift 2 ;;
      -p | --public ) public=true; shift ;;
      -s | --strong ) if [[ ! -z $2 ]]; then strong="$2"; shift 2; else strong=true; shift; fi; ;;
      -v | --verbose ) verbose=true; shift ;;
      -- ) shift; break ;;
      * ) break ;;
    esac
  done

  # argument metadata storage
  local strong_key=
  local strong_ext=
  local strong_name=
  if [[ $strong != false && -f $strong ]]; then
    strong_key=$(basename "${strong}")
    strong_ext="${strong##*.}"
    strong_name="${strong_key%.*}"
  fi

  local key_source=$(basename "${@}")
  local key_source_ext="${@##*.}"
  local key_source_name="${key_source%.*}"
  local key_source_path="$@"

  # validate arguements
  if [[ $# > 1 ]]; then
		echo "ERROR: too many arguments provided to assembly_to_il: $@">&2
		exit 1
	elif [[ (! -f $@ && ! -z $@) || ($key_source_ext != "dll" && $key_source_ext != "exe" && $key_source_ext != "snk") ]]; then
    echo "ERROR: the key source is not accepted, please provide .dll, .exe, or .snk: $key_source_ext">&2
    exit 1
  fi

  # validate options
  if [[ $strong != false && $public == true ]]; then
    echo "ERROR: invalid options combination -s|--strong and -p|--public - please use -h|--help for more details">&2
    exit 1
  elif [[ ( $strong != true && $strong != false) && (! -f $strong || $strong_ext != "snk") ]]; then
    echo "ERROR: provided file for strong signing is invalid: $strong">&2
    exit 1
  elif [[ $strong == true && $generate == true && ! -z $key_soruce ]]; then
    echo "ERROR: cannot strongname sign using a generated key - public keys will not match"
    exit 1
  elif [[ $strong == true && $key_source_ext != "snk" && $generate != true ]]; then
    echo "ERROR: strong signing is not possible - please provide a .snk as the <path-to-key-source> argument">&2
    exit 1
  fi

  # validate snk
  # We preform three phases of checking against incoming keys
  # 1. thumbprints match
  # 2. public key tokens match
  # 3. snk sha1s match
  if [[ -f $strong && ! -z $key_source]]; then
    case "$key_source_ext" in
      dll | exe )
          
        ;;
      snk )
        ;;
      * )

    esac
  fi


  if [[ $HELP == true ]]; then
    usage_key "-h"
  fi
}