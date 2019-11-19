#! /bin/bash

#================================================================
# HEADER
#================================================================

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

check() {
  OPTS=`getopt -o hdnrs --long help,delay,native,remove,signed -n 'check' -- "$@"`

  if [ $? != 0 ] ; then echo "ERROR: failed parsing options" >&2 ; exit 1 ; fi

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