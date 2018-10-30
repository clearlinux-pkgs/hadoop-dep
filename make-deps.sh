#!/bin/bash

# determine the root directory of the package repo

REPO_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)
if [ ! -d  "${REPO_DIR}/.git" ]; then
    2>&1 echo "${REPO_DIR} is not a git repository"
    exit 1
fi

# the first and the only argument should be the version of hadoop

NAME=$(basename ${BASH_SOURCE[0]})
if [ $# -ne 1 ]; then
    2>&1 cat <<EOF
Usage: $NAME <hadoop version>
EOF
    exit 2
fi

HADOOP_VERSION=$1

### move previous repository temporarily

if [ -d ${HOME}/.m2/repository ]; then
    mv ${HOME}/.m2/repository ${HOME}/.m2/repository.backup.$$
fi

### fetch the hadoop sources and unpack

HADOOP_TGZ=hadoop-${HADOOP_VERSION}-src.tar.gz

if [ ! -f "${HADOOP_TGZ}" ]; then
    HADOOP_URL=http://apache.cs.utah.edu/hadoop/common/hadoop-${HADOOP_VERSION}/${HADOOP_TGZ}
    if ! curl -L -o "${HADOOP_TGZ}" "${HADOOP_URL}"; then
        2>&1 echo Failed to download sources: $HADOOP_URL
        exit 1
    fi
fi

cd "${REPO_DIR}"

# assume all the files go to a subdir (so any file will give us the directory
# it's extracted to)
HADOOP_DIR=$(tar xzvf "${HADOOP_TGZ}" | head -1)
HADOOP_DIR=${HADOOP_DIR%%/*}
tar xzf "${HADOOP_TGZ}"

### fetch the hadoop depenencies and store the log (to retrieve the urls)

cd "${HADOOP_DIR}"
mvn dependency:resolve | grep "^Downloading:" | sed -e 's/^Downloading: \(\S\+\)\s*$/\1/' > "${REPO_DIR}/urls.txt"

cd "${REPO_DIR}"

### make the list of the dependencies
DEPENDENCIES=($(find ${HOME}/.m2/repository -type f -name *.jar -o -name *.pom))

### create pieces of the spec (SourceXXX definitions and their install actions)

SOURCES_SECTION=""
INSTALL_SECTION=""
FILES_SECTION=""
warn=
n=0

for dep in "${DEPENDENCIES[@]}"; do
    dep=${dep##${HOME}/.m2/repository/}
    dep_bn=$(basename "$dep")
    dep_dn=$(dirname "$dep")
    dep_dn=${dep_dn##"${HOME}/.m2/repository/"}
    dep_url=$(grep "${dep_bn}" urls.txt | tail -1 | sed -e 's/^\s*//' -e 's/\s*$//')
    if [ -z "${dep_url}" ]; then
        # try to see if we had it before
        dep_url=$(grep "Source[0-9]\+\s*:.*${dep_bn}" hadoop-dep.spec | sed -e 's/^Source[0-9]\+\s*:\s*\(\S\+\)\s*$/\1/')
        if [ -z "${dep_url}" ]; then
            2>&1 echo Cannot find url for file: $dep_bn:
            2>&1 grep "${dep_bn}" urls.txt
            dep_url="FIXME: ${dep_bn}"
            warn=1
        fi
    fi
    SOURCES_SECTION="${SOURCES_SECTION}
Source${n} : ${dep_url}"
    INSTALL_SECTION="${INSTALL_SECTION}
mkdir -p %{buildroot}/usr/share/apache-hadoop/.m2/repository/${dep_dn}
cp %{SOURCE${n}} %{buildroot}/usr/share/apache-hadoop/.m2/repository/${dep_dn}"
    FILES_SECTION="${FILES_SECTION}
/usr/share/apache-hadoop/.m2/repository/${dep_dn}"
    let n=$n+1
done

echo "${SOURCES_SECTION}" | sed -e '1d' > sources.txt
echo "${INSTALL_SECTION}" | sed -e '1d' > install.txt
echo "${FILES_SECTION}" | sed -e '1d' > files.txt

if [ "${warn}" -eq 1 ]; then
    cat <<EOF
WARNING: Some URs are missing. sources.txt is not usable as is. Fix the
WARNING following issues in sources.txt:
EOF
    grep 'FIXME:' sources.txt
fi
cat <<EOF

sources.txt contains SourceXXXX definitions for the spec file.
install.txt contains %install section.
files.txt contains the %files section.
EOF

# restore previous .m2
rm -rf ${HOME}/.m2/repository
if [ -d ${HOME}/.m2/repository.backup.$$ ]; then
    mv ${HOME}/.m2/repository.backup.$$ ${HOME}/.m2/repository
fi

# vim: si:noai:nocin:tw=80:sw=4:ts=4:et:nu
