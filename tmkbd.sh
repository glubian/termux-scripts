#!/bin/sh

tmuxDir="$HOME/.termux"
tmuxProperties="$tmuxDir/termux.properties"
tmuxPropertiesBackup="$tmuxDir/termux.properties.old"

tmkbdDir=$([ $TMKBD_INSTALL ] && echo $TMKBD_INSTALL || echo "$HOME/.local/share/tmkbd")
tmkbdBase="$tmkbdDir/base.properties"
tmkbds="$tmkbdDir/keyboards"
tmkbdProfiles="$tmkbdDir/profiles"

version='tmkbd, version 1.0.0'
help='A utility for managing termux keyboard.

Usage: tmkbd [subcommand] [options]

Running this command without any subcommand or options
is equivalent to running '\''tmkbd cycle'\''.

Subcommands:
add\tAdd or update a profile, or update settings
use\tSet keyboard layout
cycle\tCycle keyboard layout (default)
remove\tRemove a profile
list\tList profiles

Options:
   --help\tPrints this message and exits
   --version\tPrints version and exits'

# generic profile for Gboard
portrait='[[
  {"key":"ESC","popup":{"macro":"CTRL D","display":"^D"}},
  {"key":"CTRL","display":"CTL","popup":{"macro":"CTRL C","display":"^C"}},
  {"key":"(","popup":{"macro":"( ) LEFT","display":"(¶)"}},
  {"key":")","popup":{"macro":"HOME ( END ) LEFT","display":"(.¶)"}},
  {"key":"<","popup":{"macro":"< > LEFT","display":"<¶>"}},
  {"key":">","popup":{"macro":"HOME < END > LEFT","display":"<.¶>"}},
  {"key":"[","popup":{"macro":"[ ] LEFT","display":"[¶]"}},
  {"key":"]","popup":{"macro":"HOME [ END ] LEFT","display":"[.¶]"}},
  {"key":"{","popup":{"macro":"{ } LEFT","display":"{¶}"}},
  {"key":"}","popup":{"macro":"HOME { END } LEFT","display":"{.¶}"}}
],[
  {"key":"PGUP","display":"PGU"},
  {"key":"HOME","display":"HOM"},
  "UP",
  "END",
  {"key":"-","popup":"$"},
  {"key":"+","popup":"#"},
  {"key":"*","popup":"`"},
  {"key":"/","popup":"@"},
  {"key":"|","popup":{"macro":"| | LEFT","display":"|¶|"}},
  {"key":"BACKSLASH","popup":"_"}
],[
  {"key":"PGDN","display":"PGD"},
  {"key":"LEFT","popup":{"macro":"CTRL LEFT","display":"|←"}},
  "DOWN",
  {"key":"RIGHT","popup":{"macro":"CTRL RIGHT","display":"→|"}},
  {"key":"TAB","popup":{"macro":"SPACE SPACE LEFT","display":"«¶»"}},
  {"key":"=","popup":"~"},
  {"key":"APOSTROPHE","popup":{"macro":"APOSTROPHE APOSTROPHE LEFT","display":"'\'¶\''"}},
  {"key":"QUOTE","popup":{"macro":"QUOTE QUOTE LEFT","display":"\"¶\""}},
  "&",
  {"key":";","popup":":"}
]]'

# used to disable level indicators for small logs
biglog=0

user() {
  [ $biglog -ne 0 ] && echo -n "?? $@" || echo -n $@
}

info() {
  [ $biglog -ne 0 ] && echo ':: '$@ || echo $@
}

error() {
  [ $biglog -ne 0 ] && echo '!! '$@ || echo $@
}

more() {
  [ $biglog -ne 0 ] && echo '   '$@ || echo $@
}

listProfiles() {
  for profile in $(ls "$tmkbdProfiles"); do
    basename "$profile" .properties
  done
  echo base
}

currentProfile() {
  basename $(realpath $tmuxProperties) .properties
}

getJSONParser() {
  for parser in jq node; do
    [ -e "$(command -v $parser)" ] && echo -n $parser && return 0
  done
}

generateProfile() {
  keyboardPath="$tmkbds/$1.json"
  profilePath="$tmkbdProfiles/$1.properties"
  cp "$tmkbdBase" "$profilePath"
  echo -n '\n' >> "$profilePath"
  case $(getJSONParser) in
    jq)
      echo -n 'extra-keys=' >> "$profilePath"
      cat "$keyboardPath" | jq -c 'walk(
        if . == "\"" then
          "QUOTE"
        elif . == "'\''" then
          "APOSTROPHE"
        elif . == "\n" then
          "ENTER"
        elif . == "\\" then
          "BACKSLASH"
        elif . == "\t" then
          "TAB"
        elif type == "string" then
          gsub("(?<a>\\\\|\")"; "\\\(.a)")
        else
          .
        end
      )' >> "$profilePath"
      ;;
    node)
      echo -n 'extra-keys=' >> "$profilePath"
      cat "$keyboardPath" | node -e '
        // Courtesy of https://stackoverflow.com/a/54565854/11967372
        async function read(stream) {
          const chunks = [];
          for await (const chunk of stream) chunks.push(chunk);
          return Buffer.concat(chunks).toString("utf-8");
        }

        async function main() {
          const json = JSON.parse(await read(process.stdin));
          const stringified = JSON.stringify(json, (_, v) => {
            switch (v) {
              case "\"": return "QUOTE";
              case "'\''": return "APOSTROPHE";
              case "\n": return "ENTER";
              case "\\": return "BACKSLASH";
              case "\t": return "TAB";
            }
            return typeof v === "string" ? v.replaceAll(/(?=\\\\|\")/g, "\\") : v;
          });
          console.log(stringified);
        }

        main();
      ' >> "$profilePath"
      ;;
    *)
      error 'Unreachable: something went wrong with parser detection'
      more 'Installing jq or node might fix the issue.'
      exit 1
      ;;
  esac
}

requireJSONParser() {
  [ "$(getJSONParser)" ] && return 0
  error 'No supported JSON parser implementation found.'
  more 'You must have one of the following packages installed:'
  more 'jq nodjs nodejs-lts'
  more 'Run '\''tmkbd add --help'\'' for more info.'
  return 1
}

addBase() {
  validProps=$(
    echo -n '^((use-black-ui)|(use-fullscreen-workaround)|(fulscreen)|'
    echo -n '(use-fullscreen-workaround)|(shortcut\.)|(bell-character)|'
    echo -n '(back-key)|(enforce-char-based-input)|(ctrl-space-workaround)|'
    echo -n '(terminal-margin-(horizontal)|(vertical)))'
  )

  # assume all properties are stored in a single line
  grep -P "$validProps" "$1" > "$tmkbdBase"
}

generateProfiles() {
  for profile in $(ls $tmkbds); do
    generateProfile $(basename "$profile" .json)
  done
}

forceLinkProfile() {
  [ "$1" = base ] && nextProfile="$tmkbdBase" || nextProfile="$tmkbdProfiles/$1.properties"
  rm -f "$tmuxProperties"
  ln -fs "$nextProfile" "$tmuxProperties"
}

linkProfile() {
  if [ -e "$tmuxProperties" -a ! -h "$tmuxProperties" ]; then
    info 'It looks like termux.properties is not a symlink.'
    more 'Removing it could cause data loss.'
    user -n 'Do you want to proceed? [y/N] '
    read res
    ! [ "$res" = y -o "$res" = Y ] && info 'Aborted.' && exit 0
  fi
  forceLinkProfile "$1"
}

install() {
  if [ -e "$tmkbdDir" ]; then
    info "$tmkbdDir already exists."
    more 'Reinstalling will replace all of its contents.'
    user 'Do you sill want to continue? [y/N] '
    read res
    ! [ "$res" = 'y' -o "$res" = 'Y' ] && echo 'Aborted.' && exit 0
    rm -rf $tmkbdDir
    info "Removed $tmkbdDir".
  fi

  mkdir -p "$tmkbdDir" "$tmkbds" "$tmkbdProfiles"
  info "Created '$tmkbdDir'."

  if [ -e "$tmuxDir" ]; then
    cat /dev/null >> "$tmuxProperties"
    cp "$tmuxProperties" "$tmuxPropertiesBackup"
    addBase "$tmuxProperties"
    info 'Imported base settings from '\''termux.properties'\'.
    linkProfile base
    info ''\''termux.properties'\'' is now a symlink. Old settings are backed up as '\''termux.profile.old'\'.
  else
    info "$tmuxDir (where Termux settings are normally stored) does not exist."
    more 'tmkbd requires it to properly function.'
    user 'Do you want to create it? [Y/n] '
    read res

    if [ "$res" = 'n' -o "$res" = 'N' ]; then
      info "Cleaning up - removing $tmkbdDir"
      rm -rf "$tmkbdDir"
      info "Aborted."
      exit 0
    fi

    info 'Default settings will be used. You can change them later using '\''tmkbd add'\'.
    mkdir -p "$tmuxDir"
    cat /dev/null >> "$tmkbdBase"
  fi

  user 'Do you want to install an included profile? [Y/n] '
  read res
  ! [ "$res" = 'n' -o "$res" = 'N' ] && echo "$portrait" > "$tmkbds/portrait.json"

  generateProfiles

  info 'Installation complete! Run '\''tmkbd --help'\'' to get started.'
}

addSubcommand() {
  help='Adds or updates a keyboard profile or other Termux settings.

Usage: tmkbd add <file> [options]

Options:
   --base\tUpdates base Termux settings from the specified file
   --as <NAME>\tSave the profile with a custom name
   --help\tPrints this message and exits
   --version\tPrints version and exits'

  moreInfo='Run "tmkbd add --help" for more info.'

  file=''
  as=''
  base=0

  asExpected=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --help) echo "$help" && exit 0 ;;
      --version) echo "$version" && exit 0 ;;
    esac

    if [ $asExpected -eq 1 ]; then
      as="$1"
      asExpected=0
      shift
      continue
    fi

    case "$1" in
      --base)
        if [ $base -ne 0 ]; then
          error '--base can be specified only once'
          more "$moreInfo"
          exit 1
        fi
        if [ "$as" ]; then
          error '--base cannot be used with --as'
          more "$moreInfo"
          exit 1
        fi
        base=1
        shift
        ;;
      --as)
        if [ "$as" ]; then
          error '--as can be specified only once'
          more "$moreInfo"
          exit 1
        fi
        if [ $base -ne 0 ]; then
          error '--base cannot be used with --as'
          more "$moreInfo"
          exit 1
        fi
        asExpected=1
        shift
        ;;
      *)
        if [ "$file" ]; then
          error 'You can only add one file at a time.'
          more "$moreInfo"
          exit 1
        fi
        file="$1"
        shift
        ;;
    esac
  done

  if [ $asExpected -eq 1 ]; then
    error '--as requires a profile name'
    more "$moreInfo"
    exit 1
  fi

  if [ ! "$file" ]; then
    error 'No file specified.'
    more "$moreInfo"
    exit 1
  fi

  if [ $base -ne 0 ]; then
    addBase "$file"
    info 'Rebuilding profiles...'
    generateProfiles
  else
    profile=$([ $as ] && echo $as || basename $file .json)
    cp "$file" "$tmkbds/$profile.json"
    info "Compiling $profile..."
    generateProfile $profile
    info "$profile now available."
    more 'Run '"'tmkbd use $profile'"' to apply it.'
  fi

  exit 0
}

useSubcommand() {
  help='Sets the profile.

Usage: tmkbd use <profile> [options]

Run '\''tmkbd list'\'' to see available profiles.

Options:
   --hold\tSets the profile and changes it back upon keypress
   --help\tPrints this message and exits
   --version\tPrints version and exits'

  moreInfo='Run '\''tmkbd use --help'\'' for more info.'
  profile=''

  while [ $# -gt 0 ]; do
    case "$1" in
      --help) echo "$help" && exit 0 ;;
      --version) echo "$version" && exit 0 ;;
    esac
    [ $profile ] && exitUnexpectedArgument "$1"
    profile="$1"
    shift
  done

  if [ ! "$profile" ]; then
    error "No profile specified."
    more 'Run '\''tmkbd list'\'' to see available profiles.'
    exit 1
  fi

  if [ ! -e "$tmkbdProfiles/$profile.properties" ]; then
    error "$profile does not exist."
    more 'Run '\''tmkbd list'\'' to see available profiles.'
    exit 1
  fi

  if [ "$profile" != "$(currentProfile)" ]; then
    linkProfile "$profile"
    termux-reload-settings
  fi

  info "Using $profile."
  exit 0
}

cycleSubcommand() {
  help='Cycles profiles.

Usage: tmkbd [cycle] [options]

Options:
   --help\tPrints this message and exits
   --version\tPrints version and exits'

  while [ $# -gt 0 ]; do
    case "$1" in
      --help) echo "$help" && exit 0 ;;
      --version) echo "$version" && exit 0 ;;
    esac
    exitUnexpectedArgument "$1"
  done

  crProfile=$(currentProfile)
  nextProfile=''
  next=0
  for profile in $(listProfiles); do
    [ ! "$nextProfile" ] && nextProfile="$profile"
    [ $next -ne 0 ] && nextProfile="$profile" && break
    [ "$profile" = "$crProfile" ] && next=1
  done

  if [ "$nextProfile" != "$crProfile" ]; then
    linkProfile "$nextProfile"
    termux-reload-settings
  fi

  info "Using $(currentProfile)."

  exit 0
}

listSubcommand() {
  help='Lists available keyboard profiles.

Usage: tmkbd list [options]

Options:
   --help\tPrints this message and exits
   --version\tPrints version and exits'

  moreInfo='Run '\''tmkbd list --help'\'' for more info.'

  while [ $# -gt 0 ]; do
    case "$1" in
      --help) echo "$help" && exit 0 ;;
      --version) echo "$version" && exit 0 ;;
    esac
    exitUnexpectedArgument "$1"
  done

  listProfiles | sed -e "s/$(currentProfile)/\0 (active)/"
  exit 0
}

removeSubcommand() {
  help='Removes specified profile.

Usage: tmkbd remove <profile> [options]

Run '\''tmkbd list'\'' to see available profiles.

Options:
   --help\tPrints this message and exits
   --version\tPrints version and exits'

  moreInfo='Run '\''tmkbd remove --help'\'' for more info.'
  profile=''

  while [ $# -gt 0 ]; do
    case "$1" in
      --help) echo "$help" && exit 0 ;;
      --version) echo "$version" && exit 0 ;;
    esac
    if [ $profile ]; then
      error 'You can remove only one profile at a time.'
      more "$moreInfo"
      exit 1
    fi
    profile="$1"
    shift
  done

  lastProfile="$(currentProfile)"

  if ! [ -e "$tmkbds/$profile.json" -o -e "$tmkbdProfiles/$profile.properties" ]; then
    info 'Nothing to do.'
    exit 0
  fi

  rm -f "$tmkbds/$profile.json"
  rm -f "$tmkbdProfiles/$profile.properties"
  info "$profile removed."

  if [ "$lastProfile" = "$profile" ]; then
    linkProfile base
    termux-reload-settings
    info "Using base."
  fi

  exit 0
}

exitUnexpectedArgument() {
  error "'$1': unexpected argument"
  more "$moreInfo"
  exit 1
}

if [ ! -e "$tmkbdDir" ]; then
  biglog=1
  user "$tmkbdDir does not exist. Run setup? [y/N] "
  read res
  [ "$res" = 'y' -o "$res" = 'Y' ] && install
  exit 0
fi

moreInfo='Run '\''tmkbd --help'\'' for more info.'

case "$1" in
  add) shift && addSubcommand $@ ;;
  set) shift && setSubcommand $@ ;;
  use) shift && useSubcommand $@ ;;
  cycle) shift && cycleSubcommand $@ ;;
  remove) shift && removeSubcommand $@ ;;
  list) shift && listSubcommand $@ ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --help) echo "$help" && exit 0 ;;
    --version) echo "$version" && exit 0 ;;
  esac
  exitUnexpectedArgument "$1"
done

cycleSubcommand
