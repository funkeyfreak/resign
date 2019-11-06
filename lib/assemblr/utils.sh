# !/bin/bash
#
# A collection of useful functions
#

#================================================================
# HEADER
#================================================================

#######################################
# Name: verbose_log
# Description: Log verbosely
# Arguments:
#   ${@:2}: Array - The incoming text to log
# Returns:
#   None
#######################################
#TODO: Check if $@ is a string
verbose_log() {
  if [[ $1 == true ]]; then
    echo "${@:2}" 
  fi
}

#######################################
# Name: join_by
# Description: Join an array by some deliniator
# Arguments:
#   $1: bool    - The delineator to join the array
#   $*: Array   - The array to join into the retuned string
# Returns:
#   A string delineated by $1
#######################################
join_by() { 
  local IFS="$1"; 
  shift; 
  echo "$*"; 
}