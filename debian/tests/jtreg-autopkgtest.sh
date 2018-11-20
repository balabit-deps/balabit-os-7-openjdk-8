#!/bin/bash
set -o errexit
set -o errtrace
set -o pipefail
set -o nounset

if [ -z "${AUTOPKGTEST_TMP+x}" ] || [ -z "${AUTOPKGTEST_ARTIFACTS+x}" ]; then
  echo "Environment variables AUTOPKGTEST_TMP and AUTOPKGTEST_ARTIFACTS must be set" >&2
  exit 1
fi

source <(dpkg-architecture -s)

export JTREG_HOME=/usr/share/java
export JT_JAVA="${JT_JAVA:-/usr/lib/jvm/java-8-openjdk-${DEB_HOST_ARCH}}"
JDK_DIR="${JDK_DIR:-$JT_JAVA}"

jtreg_version="$(dpkg-query -W jtreg | cut -f2)"

# set additional jtreg options
jt_options="${JTREG_OPTIONS:-}"
if [[ "armel" == *"${DEB_HOST_ARCH}"* ]]; then
  jt_options+=" -Xmx256M"
fi
if dpkg --compare-versions ${jtreg_version} ge 4.2; then
  jt_options+=" -conc:auto"
fi
  
# check java binary
if [ ! -x "${JDK_DIR}/bin/java" ]; then 
  echo "Error: '${JDK_DIR}/bin/java' is not an executable." >&2
  exit 1
fi

# restrict the tests to a few archs (set from debian/rules)
if ! echo "${DEB_HOST_ARCH}" | grep -E "^($(echo amd64 i386 arm64 ppc64 ppc64el sparc64 armhf kfreebsd-amd64 kfreebsd-i386 alpha arm64 armel armhf ia64 mips mipsel mips64 mips64el powerpc powerpcspe ppc64 ppc64el s390x sh4 x32 | tr ' ' '|'))$"; then
  echo "Error: ${DEB_HOST_ARCH} is not on the jtreg_archs list, ignoring it."
  exit 77
fi

jtreg_processes() {
  ps x -ww -o pid,ppid,args \
    | awk '$2 == 1 && $3 ~ /^\/scratch/' \
    | sed "s,${JDK_DIR},<sdkimg>,g;s,$(pwd),<pwd>,g"
}

jtreg_pids() {
  ps x --no-headers -ww -o pid,ppid,args \
    | awk "\$2 == 1 && \$3 ~ /^${JDK_DIR//\//\\/}/ {print \$1}"
}

cleanup() {
  # kill testsuite processes still hanging
  pids="$(jtreg_pids)"
  if [ -n "$pids" ]; then
    echo "killing processes..."
    jtreg_processes
    kill -1 $pids
    sleep 2
    pids="$(jtreg_pids)"
    if [ -n "$pids" ]; then
      echo "try harder..."
      jtreg_processes
      kill -9 $pids
      sleep 2
    fi
  else
    echo "nothing to cleanup"
  fi
  pids="$(jtreg_pids)"
  if [ -n "$pids" ]; then
    echo "leftover processes..."
    $(jtreg_processes)
  fi
}

trap "cleanup" EXIT INT TERM ERR

jtreg ${jt_options} \
  -verbose:summary \
  -automatic \
  -retain \
  -ignore:quiet \
  -agentvm \
  -timeout:5 \
  -workDir:"${AUTOPKGTEST_ARTIFACTS}/JTwork" \
  -reportDir:"${AUTOPKGTEST_ARTIFACTS}/JTreport" \
  -jdk:${JDK_DIR} \
  $@ 
