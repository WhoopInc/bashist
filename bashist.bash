## CONSTANTS ##

readonly _bashist_color_codes=(
  clear                                         # reset
  black red green yellow blue purple cyan white # colors
  bold dim                                      # bold/bright, unbold/dim
  rev                                           # reverse video
  under nounder                                 # underline, nounderline
)

# main
#
# This function is called at the end of this file so that we can access
# functions defined later in this file.
main() {
  ## PLATFORM-SPECIFIC FLAGS ##
  case "$(bashist::platform)" in
    mac)
      _bashist_sed_flags="-l"
      ;;
    linux)
      _bashist_sed_flags="-u"
      ;;
  esac

  _bashist_escapes=(
    "$(tput sgr0)"
    "$(tput setaf 0)" "$(tput setaf 1)" "$(tput setaf 2)" "$(tput setaf 3)"
    "$(tput setaf 4)" "$(tput setaf 5)" "$(tput setaf 6)" "$(tput setaf 7)"
    "$(tput bold)" "$(tput dim)"
    "$(tput rev)"
    "$(tput smul)" "$(tput rmul)"
  ) || true
}



## SHELL OPTIONS ##

# Enable advanced globbing patterns.
# See: http://stackoverflow.com/a/17191796
shopt -s extglob



## SHELL BUILT-IN OVERRIDES ##

# Prevent `pushd` built-in from producing output
pushd() {
  command pushd "$@" > /dev/null
}

# Prevent `popd` built-in from producing output
popd() {
  command popd "$@" > /dev/null
}

# Silence `tput` errors. Usually indicates an unknown terminal, which we can't
# do anything about.
tput() {
  command tput 2> /dev/null
}



## I/O UTILITY FUNCTIONS ##

# bashist::color <format string> [<format string>...]
#
# Outputs formatted <format string>s
#
# FORMAT STRING
#    A format string is a plain ol' shell string with some format codes mixed
#    in. Format codes consist of a code wrapped in curly braces: `{code}`
#
#    A format code applies to all following characters until it's overriden by
#    another format code.
#
# CAVEATS
#    You *must* send the `clear` format code when you're finished outputting
#    formatted text, or you'll format the user's prompt and future programs!
#
#    Example:
#        '{red}Red, {bold}bold beautiful text!{clear}'
#
# FORMAT CODES
#    See `$_bashist_color_codes` for a list of possible format codes
bashist::color() {
  local strings="$@"
  for (( i=0; i < ${#_bashist_color_codes[@]}; ++i )); do
    strings=${strings//\{${_bashist_color_codes[i]}\}/${_bashist_escapes[i]}}
  done
  echo "${strings[@]}"
}

# bashist::error <message> [<message>...]
#
# Outputs <message>s to standard error
bashist::error() {
  bashist::color "$@" 1>&2
}

# bashist::die <message> [<message>...]
#
# Outputs <message>s to standard error, then terminates with exit code 1
bashist::die() {
  bashist::error "$@"
  exit 1
}

# bashist::confirm <prompt>
#
# Prints <prompt> and waits for user agreement or refusal. Considers "y", "yes"
# agreement and "n", "no" refusal.
#
# RETURN VALUE
#     Success if user agrees; failure if user refuses.
bashist::confirm() {
  while true; do
    case $(bashist::ask "$1 [y/n]") in
      y|yes) return 0 ;;
      n|no) return 1 ;;
    esac
  done
}

# bashist::ask <prompt> <default>
#
# Prints <prompt> followed by " " and waits for one line of user input.
# Outputs that user input.
#
# If <default> is specified, " [<default>]" is appended to <prompt> to indicate
# to the user that a default is available, and <default> will be output if the
# user's input is blank.
#
# Note that <prompt> is output to stderr so that command substitution--
# `$(bashist::ask "prompt")`--will capture only the user's input, and not the
# prompt.
bashist::ask() {
  local answer prompt

  prompt="$1"
  if [[ ! -z "$2" ]]; then prompt+=" [$2]"; fi

  read -p "${prompt} " answer
  if [[ -z "${answer}" ]]; then answer=$2; fi
  echo "${answer}"
}

# bashist::header <text> [<text>...]
#
# Outputs all <text>s, separated by `$IFS`, preceded with a '-->' to indicate a
# header. Recommended to use `bashist::tab` or `bashist::tab_command` to output a
# "section" beneath this header.
bashist::header() {
  bashist::color "-->" "$@"
}

# <command> | bashist::tab
#
# Pipe the output of <command> to `bashist::tab` to indent <command>'s output by
# four spaces.
bashist::tab() {
  sed ${_bashist_sed_flags} 's%^%    %'
}

# bashist::tab_command <command> [<args>...]
#
# Runs <command> with any specified arguments, pipes its stdout and stderr
# through bashist::tab. Uses the `script` command to prevent <command> from
# detecting its stdout/stderr streams are not a TTY. (Often, programs will
# disable colorized output when stdout/stderr are not attached to a TTY.)
#
# In general, you should prefer `bashist::tab_command` to `bashist::tab` since
# it preserves colors and the command's exit code. It may, however, interfere
# with commands that make heavy use of terminal control libraries, like progress
# indicators.
bashist::tab_command() {
  local cmd
  declare -i exit_code

  case "$(bashist::platform)" in
    windows)
      "$@" | bashist::tab ;;
    linux)
      script -q /dev/null -c "$(printf "%q " "$@")" --return | bashist::tab ;;
    *)
      script -q /dev/null "$@" | bashist::tab ;;
  esac

  exit_code=${PIPESTATUS[0]}
  echo
  return $exit_code
}

# bashist::force_cr_on_nl
#
# Due to some weird TTY bug, intermingling output between a host terminal and a
# backgrounded SSH terminal that's requested a psuedo-TTY drops carriage
# returns, producing output like the following:
#
# Line 1
#        Line 2
#               Line 3
#
# This function adds an additional carriage return after each line feed to
# guarantee the cursor returns to the beginning of each line. Due to sed
# limitations, this duplicates carriage returns, but that's invisible to the
# user.
bashist::force_cr_on_nl() {
  exec > >(sed ${_bashist_sed_flags} $'s/^/\r/')
}

# bashist::lines_to_args <lines>
#
# Converts a string of newline-separated (`\n`) values <lines> into a properly-
# escaped string of arguments.
#
# Example input:
#    "long-filename-one.js
#    filename with spaces.js
#    empty.js"
#
# Example output:
#     "long-filename-one.js filename\ with\ spaces.js empty.js"
bashist::lines_to_args() {
  IFS=$'\n' line_array=($1)
  printf "%q " "${line_array[@]}"
}

# bashist::regexp_escape <string>
#
# Outputs <string> escaped for use with basic regular expressions. See
# re_format(7) for details.
bashist::regexp_escape() {
  sed 's/[]^$*.\[]/\\&/g' <<< "$1"
}


## PROVISIONING UTILITIES ##

# bashist::platform
#
# Outputs this machine's platform. "windows" on Windows, "mac" on OS X,
# "unsupported" otherwise.
bashist::platform() {
  case "$(uname)" in
    *NT*)   echo "windows" ;;
    Darwin) echo "mac" ;;
    Linux)  echo "linux" ;;
    *)      echo "unsupported" ;;
  esac
}

# bashist::arch
#
# Outputs the architecture of this machine's CPU. "x86" or "x64".
bashist::arch() {
  if [[ $(uname -m) == "x86_64" ]]; then
    echo "x64"
  else
    echo "x86"
  fi
}

# bashist::which <executable>
#
# Returns success code if <executable> exists on the user's $PATH; failure
# otherwise. More portable than `which`.
bashist::which() {
  hash "$1" 2> /dev/null
}



## GENERAL CLI UTILITIES ##

# bashist::ensure_singleton <id>
#
# Ensures only one copy of <id> is running by writing a PID file.
bashist::ensure_singleton() {
  pid_file="/tmp/$1"
  touch "${pid_file}"
  read pid < "${pid_file}" || true

  if [[ ! -z "$pid" ]] && ps -p "$pid" > /dev/null; then
    bashist::die "{red}'$0' is already running! aborting...{clear}"
  fi

  echo $$ > $pid_file
}



main "$@"
