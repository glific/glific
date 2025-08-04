# .profile.d/001_fixup_apt.sh
APT_PATHS=$(find $HOME/.apt/usr/lib/x86_64-linux-gnu/ -type d | xargs echo | sed -e 's/ /:/g')

export LD_LIBRARY_PATH="${APT_PATHS}:${LD_LIBRARY_PATH}"
export LIBRARY_PATH="${APT_PATHS}:${LIBRARY_PATH}"
export INCLUDE_PATH="${APT_PATHS}:${INCLUDE_PATH}"
export CPATH="${INCLUDE_PATH}"
export CPPPATH="${INCLUDE_PATH}"
