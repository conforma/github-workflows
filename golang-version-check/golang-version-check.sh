#!/bin/bash
# Copyright The Enterprise Contract Contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# SPDX-License-Identifier: Apache-2.0
#
# Checks if all Golang versions in use are in compatible with each other,
# currently compatible is interpreted as 'are equal'

set -o errexit
set -o nounset
set -o pipefail

shopt -s globstar nullglob

exec 3>&1

running_version="$(go env GOVERSION)"
running_version=${running_version#go}

status=0

error() {
    file="$1"
    line="$2"
    message="$3"
    message="${message//$'\n'/'%0A'}"
    printf "::error file=%s,line=${line},col=0::%s\n" "${file}" "${message}" >&3
    return 1
}

version_from() {
    file="$1"
    shift
    {
        stderr=$("$@" 2>&1 1>&3-)
    } 3>&1 || {
        error "${file}" 0 "Failed to extract golang version from ${file}: ${stderr}"
        status=1
        return 1
    }
}

# assumes that the go version is on the third line always
go_mod_version() {
    file="$1"
    version_from "${file}" grep -n -P -o '(?<=^go )(\d+(\.\d+)*.*$)' "${file}"
}

tool_version() {
    file="$1"
    version_from "${file}" grep -n -P -o '(?<=golang )(.*)' "${file}"
}

# expects that the version is in the line starting with 'FROM ' and ending with
# ' AS build', also assumes that the version follows the ':' character and is
# specified as x.y.z
builder_version() {
    file="$1"
    # '(?<=^FROM .{1,248}:v?)(\d+(?:\.\d+)+)(?=.* AS build.*$)' works fine here
    # on Fedora with grep 3.11 + pcre, it gives "lookbehind assertion is not
    # fixed length" on Ubuntu with grep 3.7, so for compatibility let's use the
    # least specific version here
    version_from "${file}" grep -i -n -P -o '\K(\d+(?:\.\d+)+)(?=.* AS build.*$)' "${file}"
}

compatible() {
    a="$1"
    b="$2"
    [[ "$a" == "$b" ]] || return 1
}

for mod in **/go.mod; do
    line_version=$(go_mod_version "${mod}") || continue
    line=${line_version%:*}
    version=${line_version#*:}
    [[ "${version}" == *allow* ]] && continue
    if ! compatible "${version}" "${running_version}"; then
        error "${mod}" "${line}" "Golang version incompatible, saw ${version}, running with version: ${running_version}"
    fi
done

for tv in **/.tool-versions; do
    line_version=$(tool_version "${tv}") || continue
    line=${line_version%:*}
    version=${line_version#*:}
    if ! compatible "${version}" "${running_version}"; then
        error "${tv}" "${line}" "Version manager version incompatible, saw ${version}, running with version: ${running_version}"
    fi
done

for d in **/{Dockerfile*,Containerfile*}; do
    line_version=$(builder_version "${d}") || continue
    line=${line_version%:*}
    version=${line_version#*:}
    if ! compatible "${version}" "${running_version}"; then
        error "${d}" "${line}" "Containerfile version incompatible, saw ${version}, running with version: ${running_version}"
    fi
done

exit ${status}