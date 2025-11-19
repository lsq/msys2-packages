#!/usr/bin/env bash

# set -eou pipefail

CURL_CMD="curl -fsSL --retry 5 --retry-all-errors"

usage() {
    tee <<done-usage

    Update Package Version 2025.4.20
    Copyright (C) 2025 Renato Silva
    Licensed under BSD

    Usage: ${program} [options]

    --build           Building and integrating updates
    --report          Report analysis and integration results

    --verbose         Enable verbose output

done-usage
    exit 1
}

read_arguments() {
    arguments=("${@}")
    program="$(basename "${0}")"
    indent="$(printf %3s)"
    for element in "${arguments[@]}"; do
        case "${element}" in
        --build) option_build='true' ;;
        --report) option_report='true' ;;
        --verbose) option_verbose='true' ;;
        -*) usage ;;
        *) args+=("${element//\\/\/}") ;;
        esac
    done
}

die() {
    echo -e '\033[40;31m$1 !!!\033[0m' >&2
    exit 1
}

success() {
    local _content="$1"

    echo -e "\033[40;32msucess: ${_content}\033[0m"

}

error() {
    local _err="$1"

    echo -e "\033[40;31merro: ${_err}\033[0m"
}

clearline() {
    # pactoys_terminal || return 0
    printf '\r\e[0K\r'
}

message() {
    local arguments=("${@}")
    clearline
    printf "${indent}"
    printf "${arguments[@]}"
}

header() {
    local title="${1}"
    printf "${d_colors[green]}::"
    printf "${d_colors[white]} %s" "${title}"
    printf "${d_colors[normal]}\n\n"
}

restore() {
    local -n ref=$1
    eval "$2"
    local -n eval_name="$(sed -n 's/declare -A \([^=]*\)=.*/\1/p' <<<"$2")"
    # printf "%s\n" "${eval_name[@]}"
    # ref=("${eval_name[@]}")
    local element

    for element in ${!eval_name[@]}; do
        ref["$element"]="${eval_name[$element]}"
    done
}

report() {
    local title="${1}"
    local elements=("${@:2}")
    local -A package
    test "${#elements[@]}" -gt 0 || return 0
    header "${title}"
    for element in "${elements[@]}"; do
        restore package "${element}"
        # declare -p package
        local arguments=("${package[pkg_name]}" "${package[oldver]}" ${package[newver]} "${package[pkg_install_type]}")
        message "\e[1;36m%-20s %-15s %-15s %s\e[0m\n" "${arguments[@]}"
    done
    echo
}

git_log() {
    local git_old=$1

    cd "$scriptdir" || exit 1
    if ! git diff-index --cached --quiet HEAD; then
        git status
        [ -f "${scriptdir}/gitlog.txt" ] && git commit -F "${scriptdir}/gitlog.txt"
    fi

    local git_now=$(git log -1 --format=%h)
    [[ $git_old == $git_now ]] && echo "pushflag=0" >>$GITHUB_ENV && return 0
    [[ -f "${scriptdir}/files/mlsq.db" ]] && echo "pushflag=1" >>$GITHUB_ENV || { echo "pushflag=0" >>$GITHUB_ENV && return 0; }
    # git log --format=%B -n 1 $(git log -1 --pretty=format:"%h") | cat -
    # git rev-list --max-count=1 --no-commit-header --format=%B <commit>
    # https://stackoverflow.com/questions/3357280/print-commit-message-of-a-given-commit-in-git
    local commiturl=https://github.com/lsq/msys2-packages/commit/
    local log_md=$(git log --pretty='format:%h %H %s' $git_old..HEAD | sed \
        -e 's/[][_*^<`\\]/\\&/g' \
        -e "s#^\([0-9a-f]*\) \([0-9.a-z]*\)#* [\1]($commiturl\2)#" \
        -e "s#^\([0-9a-f]*\) \(.*\)#* [\2]($commiturl\1)#")
    local log_plain=$(git log --pretty='format:* %s' $git_old..HEAD | sed \
        -e 's/^/* /g')
    echo "$log_md"
    # https://unix.stackexchange.com/questions/182153/sed-read-whole-file-into-pattern-space-without-failing-on-single-line-input
    # sed ':a;N;$!ba;s/\*/\n- /g;s/\n/\\n/g' <<<"$log_md" > "$scriptdir"/gitlog.txt
    # sed ':a;$!{N;ba};s/\*/\n- /g;s/\n/\\n/g' <<<"$log_md" > "$scriptdir"/gitlog.txt
    sed 'H;1h;$!d;x;s/\\\*/\n  - /g;' <<<"$log_md" >"$scriptdir"/gitlog.txt
    cat "$scriptdir/gitlog.txt"

}
download_url() {
    local download_url="$1"
    local zstdir="$2"
    local fileName="$3"
    [[ -z $fileName ]] && fileName=$(basename ${download_url})
    eval "${CURL_CMD} --create-dirs --output-dir $zstdir  ${download_url} -o $fileName" || die "$fileName downloading failed!"
    echo "$fileName download successed."

}

download_release() {
    local repo url fileName download_url dirs

    repo="$1"
    dirs="$2"
    # [ ! -d "$scriptdir"/files ] && mkdir "$scriptdir"/files
    [ ! -d "$dirs" ] && mkdir -p "$dirs"
    release_info $repo release_infos
    declare -p release_infos
    for url in ${release_infos[@]}; do
        download_url=${url//\"/}
        fileName=$(basename "${download_url}")
        async "download_url $download_url $dirs $fileName" success error
    done
    wait
    ls "$dirs"/
}
release_info() {
    local repo json
    local -n arr2=$2
    repo="$1"

    # HTTP_RESPONSE=$(curl -sL -w "%h{ttp_code}" -o response.json "https://api.github.com/repos/be5invis/Iosevka/releases/latest")
    # if [ "$HTTP_RESPONSE" -ne 200 ]; then echo Error fetchin"g latest Iosevka release: HTTP $HTTP_RESPONSE"; cat response.json; exit 1; fi
    # https://unix.stackexchange.com/questions/177843/parse-one-field-from-an-json-array-into-bash-array
    # json=$(curl -s https://api.github.com/repos/$repo/releases/latest)
    # eval "$(jq -r '@sh "myarr=( \([.[].item2]))"' <<<"$json")"
    { readarray -td '' arr2; } < <(
        # { readarray -td '' arr2 && wait "$!"; } < <(
        # IFS=$'\r\n' readarray -td '' arr2  < <(
        # readarray -td $'\r' arr2  < <(
        # echo "$json" | jq -j '.[] | (., "\u0000") '
        set -o pipefail
        eval "${CURL_CMD} https://api.github.com/repos/$repo/releases/latest" | jq -j '.assets|map(.browser_download_url)| map(select(test(".*.tar.zst"))) |.[]| (., "\u0000") '
        # curl -s --fail https://api.github.com/repos/$repo/releases/latest | jq -j '.assets|map(.browser_download_url)| map(select(test(".*.tar.zst"))) |.[]| (., "\u0000") '
    )
    # declare -p arr2

}

parse_job_output() {
    # local -n updateinfos=$1
    local eval_str

    # eval_str="$(sed 's/\(declare -A\)/\1g/' <<<"$jobsinfo")"
    jobsinfo="${jobsinfo/-A/-Ag}"

    [ -n "$jobsinfo" ] || exit 1
    eval "$jobsinfo"
    eval "$packages_info"
    # eval "$eval_str"

    # for item in "${!updateinfos[@]}"
    # do
    # done

}
check_old_exist() {
    local pkg_name oldver zstfile
    local -n flag=$3

    pkg_name="$1"
    oldver="$2"

    # zstfile=($(find "$scriptdir/files" . -regextype posix-extended -regex ".*/[^/]*$pkg_name.*$oldver.*.tar.zst" -printf "%f " ))
    readarray -td '' zstfile < <(find "$scriptdir/files" . -regextype posix-extended -regex ".*/[^/]*$pkg_name.*$oldver.*.tar.zst" -printf "%f\0")
    test -z "$zstfile" && echo -e "${d_colors[green]}$pkg_name${d_colors[normal]} not in releases files" && flag=1 && return 0
    flag=0
}

build_dependency_check() {
    local -n pacakge_info="${1}"
    local make_option f str
    local oldver newver cur_files orig_files make_type
    local -A updated_info
    pacakge="${pacakge_info[pkg_name]}"
    oldver=${pacakge_info[oldver]}
    newver=${pacakge_info[newver]}
    make_type=${pacakge_info[pkg_install_type]}
    case "$make_type" in
    unix)
        make_option=
        makepkg=makepkg
        ;;
    mingw* | ucrt* | clangd*)
        make_option="MINGW_ARCH=$make_type"
        makepkg="makepkg-mingw"
        ;;
    esac

    pwd
    cd "$scriptdir"/"$pacakge" || exit 1

    [[ $oldver != $newver ]] && sed -i "s/\(^pkgver=\)$oldver/\1$newver/" PKGBUILD
    # updpkgver --makepkg="$make_option" --verbose --versioned "${pacakge}"
    eval "${make_option}" "$makepkg" --noconfirm --skippgpcheck --nocheck --clean --cleanbuild --force --syncdeps --noprepare --nobuild --noextract
    [[ -d src ]] && rm -rf src
}

sort_array() {
    local -n A=$1
    local -n sorted=$2
    readarray -d '' sorted < <(printf '%s\0' "${!A[@]}" | sort -z)
}

check_pacman_dblock() {
    while [[ -e /var/lib/pacman/db.lck ]]; do
        echo -e "${d_colors[red]}another process is using pacman. \nwaiting for exit in 5 second.\n${d_colors[normal]}}"
        sleep 5s
    done
}

build_packages() {
    local updateinfo index db_files
    local -a array_index
    local gitoldver

    gitoldver=$(git log -1 --format=%h)
    parse_job_output
    # download_release "$GITHUB_REPOSITORY" "$scriptdir/files"
    declare -p updateinfos

    # for item in ${!updateinfos[@]}
    # do
    #     eval "${updateinfos[$item]}"
    #     printf "${d_colors[cyan]}:: fetch ${updateinfo[pkg_name]} dependenci...${d_colors[normal]}\n$"
    #     build_dependency_check updateinfo
    # done
    #

    sort_array updateinfos array_index
    # for item in ${!updateinfos[@]}
    echo "Update PKGBUILD:" >"$scriptdir/gitlog.txt"
    for index in "${array_index[@]}"; do
        eval "${updateinfos[$index]}"
        # if [[ ${updateinfo[pkg_as_dependency]} == 0 ]]; then
        # async "build_package updateinfo" success error
        # else
        build_package updateinfo
        # fi
    done
    wait
    declare -p updated
    cd "$scriptdir"/files || exit 1
    ls
    local zstd_files=(*pkg.tar.zst)
    db_files=(mlsq*)
    if [ -e "${zstd_files[0]}" ]; then
        test -n "$db_files" && rm -rf mlsq*
        repo-add "mlsq.db.tar.zst" *.pkg.tar.zst
    fi
    git_log "$gitoldver"
}
# 需要参数:
# 1. pacakge name
# 2. old version number
# 3. new version number
# 4. make type: msys2/mingw
build_package() {
    local -n pacakge_info="${1}"
    local make_option f str
    local pacakge oldver newver cur_files orig_files make_type
    local -A updated_info
    local -Ag updated failed
    local install_flag=''
    package="${pacakge_info[pkg_name]}"
    oldver=${pacakge_info[oldver]}
    newver=${pacakge_info[newver]}
    make_type=${pacakge_info[pkg_install_type]}
    case "$make_type" in
    unix)
        make_option=
        makepkg=makepkg
        ;;
    mingw* | ucrt* | clangd*)
        make_option="MINGW_ARCH=$make_type"
        makepkg="makepkg-mingw"
        ;;
    esac

    if [[ "${pacakge_info[pkg_as_dependency]}" == 1 ]]; then
        install_flag="-i"
    fi

    pwd
    cd "$scriptdir"/"$package" || exit 1
    pwd
    orig_files=(*)
    if [[ $oldver != $newver ]]; then
        sed -i "s/\(^pkgver=\)$oldver/\1$newver/" PKGBUILD
        updpkgsums
        git status
        git add PKGBUILD
        # git commit -a -m "${package} update to version $newver($oldver)."
        echo "* $package update to version $newver($oldver)" >>"$scriptdir/gitlog.txt"
    else
        echo "* rebuild $package version $oldver" >>"$scriptdir/gitlog.txt"
    fi
    # updpkgver --makepkg="$make_option" --verbose --versioned "${pacakge}"
    # eval "${make_option}" "$makepkg" --noconfirm --skippgpcheck --nocheck --nodeps --clean --cleanbuild --force
    # check_pacman_dblock
    eval "${make_option}" "$makepkg" --noconfirm --skippgpcheck --nocheck --syncdeps --clean --cleanbuild --force "$install_flag"

    ls *.tar.zst
    buildTars=(*.tar.zst)
    updated_info=([pkg_name]="$package" [oldver]="$oldver" [newver]="$newver" [pkg_install_type]="$make_type")
    str="$(declare -p updated_info)"
    # release_files=($(ls "$scriptdir"/files))
    if [ -f "${buildTars[0]}" ]; then
        echo -e "${d_colors[yellow]}${package}${d_colors[normal]} built successed."
        updated["${package}"]="$str"
        cp -rf *.tar.zst ../files
    else
        echo -e "${d_colors[yellow]}${package}${d_colors[normal]} built failed."
        failed["${package}"]="$str"
    fi
    if [[ $oldver != $newver ]]; then
        # if printf "%s\0"  "${release_files[@]}"| grep -xqz -- ".*${pacakge}.*${oldver}.*.tar.zst";then
        # echo ".*${pacakge}.*${oldver}.*.tar.zst"
        # fi
        # https://unix.stackexchange.com/questions/577309/find-regular-expression-in-name
        find "$scriptdir/files" . -regextype posix-extended -regex ".*/[^/]*$package.*$newver.*.tar.zst" -printf "%f\n"
    fi
    remove_new_file orig_files
}

tar_check() {
    local -n info="$1"
    local oldver newver str release_exist
    local pkg_name="${info[pkg_name]}"
    local pkg_install_type="${info[pkg_install_type]}"
    local pkg_build_force="${info[pkg_build_force]}"
    local -n first_build="$2"
    local -a ofiles

    local oldver newver str
    local -A updateinfo
    cd "${scriptdir}" || exit 1

    # local update_info pkgver
    # update_info="$(updpkgver --no-build --versioned --color "$item")"
    # pwd
    cd "${scriptdir}/${pkg_name}" || exit 1
    ofiles=(*)
    cd -
    updpkgver --no-build --versioned --color "${pkg_name}"
    cd "${scriptdir}/${pkg_name}" || exit 1
    oldver=$(sed -n 's/pkgver=\(.*\)/\1/p' PKGBUILD)
    check_old_exist "$pkg_name" "$oldver" release_exist
    newver=
    if [[ -e "$scriptdir"/"$pkg_name"/PKGBUILD.NEW ]]; then
        newver=$(sed -n 's/pkgver=\(.*\)/\1/p' PKGBUILD.NEW)
    elif [[ "${pkg_build_force}" == "1" ]]; then
        newver="$oldver"
    fi
    if [[ -n "$newver" || "$first_build" == "1" || $release_exist == "1" ]]; then
        updateable=1
        [[ -z "$newver" ]] && newver=$oldver

        updateinfo=([pkg_name]="$pkg_name" [oldver]="$oldver" [newver]="$newver" [pkg_install_type]="$pkg_install_type" [pkg_as_dependency]="${info[pkg_as_dependency]}")
        str=$(declare -p updateinfo)
        updateinfos["${info[pkg_build_order]}"]="$str"
    fi
    remove_new_file ofiles
    # cd ..
    # printf "%s\n" "$update_info"
}
git_check() {
    local -n info="$1"
    local oldver newver str release_exist
    local -a ofiles
    local pkg_name="${info[pkg_name]}"
    local pkg_install_type="${info[pkg_install_type]}"
    local pkg_build_force="${info[pkg_build_force]}"
    local -n first_build="$2"
    local -A updateinfo
    # pwd
    cd "$scriptdir"/"$pkg_name" || exit 1

    ofiles=(*)
    source PKGBUILD
    oldver="$pkgver"
    check_old_exist "$pkg_name" "$oldver" release_exist
    makepkg -od
    local srcdir="src"
    newver=$(pkgver)

    if [[ "$oldver" == "$newver" && "$pkg_build_force" == "0" && "$first_build" != "1" && $release_exist == "0" ]]; then
        printf "[1;34m::[$pkg_name][1;37m no updates detected.\n [0m"
    else
        updateable=1
        updateinfo=([pkg_name]="$pkg_name" [oldver]="$oldver" [newver]="$newver" [pkg_install_type]="$pkg_install_type" [pkg_as_dependency]="${info[pkg_as_dependency]}")
        str=$(declare -p updateinfo)
        updateinfos["${info[pkg_build_order]}"]="$str"
        [[ $newver != $oldver ]] && printf "[1;34m::[$pkg_name][1;37m new version:$newver\n [0m"
    fi
    remove_new_file ofiles
}

remove_new_file() {
    local cur_files f
    local -n orig_list=$1
    cur_files=(*)
    for f in "${cur_files[@]}"; do
        # if [[ "${orig_files[@]}" =~ "$f" ]];then
        if [[ " ${orig_list[*]} " =~ " ${f} " ]]; then
            continue
        fi
        echo "now remove $f"
        rm -rf "$f"
    done
}

check_update() {
    # local -A updateinfo
    local item first_build_tag release_infos
    updateable=0

    read_config
    # release_info lsq/vime release_infos
    download_release "$GITHUB_REPOSITORY" "$scriptdir/files"
    # release_info "$GITHUB_REPOSITORY" release_infos
    # declare -p release_infos
    if [[ ${#release_infos[@]} == 0 ]]; then
        first_build_tag=1
    else
        first_build_tag=0
    fi
    for item in "${!pkginfos[@]}"; do
        eval "${pkginfos[$item]}"
        echo "[1;34m::[$item][1;37m Checking ["${pkginfo[pkg_name]}"] updates [0m"
        # declare -p pkginfo
        if [[ "${pkginfo[pkg_source_type]}" =~ tar ]]; then
            tar_check pkginfo first_build_tag

        elif [[ "${pkginfo[pkg_source_type]}" =~ git ]]; then
            git_check pkginfo first_build_tag
        fi
    done

    [ "$updateable" == 1 ] && echo "updateable=1"
    echo "updateable=${updateable}" >>"$GITHUB_OUTPUT"
    echo "jobsinfo=packages_info=\"$(declare -p updateinfos | sed 's/\\/\\\\/g;s/"/\\"/g')\"" >>$GITHUB_OUTPUT
}
parse_config() {
    local pkg_config="${1//|/ }"
    local pkg_build_order pkg_name pkg_install_type pkg_build_force pkg_source_type pkg_as_dependency
    local -A pkginfo
    IFS=" " read -r pkg_build_order pkg_name pkg_install_type pkg_build_force pkg_source_type pkg_as_dependency <<<"$pkg_config"
    pkginfo[pkg_build_order]="${pkg_build_order}"
    pkginfo[pkg_name]="${pkg_name}"
    pkginfo[pkg_install_type]="${pkg_install_type}"
    pkginfo[pkg_build_force]="${pkg_build_force}"
    pkginfo[pkg_source_type]="${pkg_source_type}"
    pkginfo[pkg_as_dependency]="${pkg_as_dependency}"

    # check_version_list+=("${pkg_name}")

    local string
    string=$(declare -p pkginfo)
    # printf "%s\n" "$string"
    pkginfos["${pkg_build_order}"]="$string"
    # declare -p pkginfos
}

read_config() {
    local contents

    contents="$(sed -n '/|:--/{:c;$b e;N;s/\s*\(|.*|\)$/\1/;t c;s/\(.*\)\n.*/\1/;:e;s/[^\n]*\n//;p}' "$scriptdir"/README.md)"
    while read -r line; do
        parse_config "$line"
    done <<<"$contents"
}

if [[ "${BASH_SOURCE}" = "${0}" ]]; then
    read_arguments "${@}"
    scriptdir=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
    source "$scriptdir"/scripts/async.bash
    cp -rf "$scriptdir"/scripts/makepatch /usr/bin/makepatch
    cp -rf "$scriptdir"/scripts/updpkgver /usr/bin/updpkgver

    declare -A pkginfos updateinfos
    declare -Ag d_colors
    d_colors[normal]='\e[0m'
    d_colors[gray]='\e[1;30m'
    d_colors[red]='\e[1;31m'
    d_colors[green]='\e[1;32m'
    d_colors[yellow]='\e[1;33m'
    d_colors[blue]='\e[1;34m'
    d_colors[purple]='\e[1;35m'
    d_colors[cyan]='\e[1;36m'
    d_colors[white]='\e[1;37m'

    # declare -a check_version_list
    # read_config
    # echo "${pkginfos[*]}"
    # echo "${check_version_list[*]}"
    git config --global user.email "github-actions[bot]@users.noreply.github.com"
    git config --global user.name "github-actions[bot]"
    [[ -z "${option_build+true}" ]] && check_update
    [[ ! -z "${option_report+'true'}" ]] && report "Update information" "${updateinfos[@]}"
    # git config --local user.email "github-actions[bot]@users.noreply.github.com"
    # git config --local user.name "github-actions[bot]"
    [[ ! -z "${option_verbose+set}" ]] && declare -p pkginfos
    [[ ! -z "${option_verbose+set}" ]] && declare -p updateinfos
    # echo "jobsinfo=\"$(declare -p updateinfos|sed 's/\\/\\\\/g;s/"/\\"/g')\"" #>> $GITHUB_OUTPUT
    #aaa="nupdateinfos=\"$(declare -p updateinfos|sed 's/\\/\\\\/g;s/"/\\"/g;s/updateinfo/lsq/g')\""
    #echo "$aaa"
    #eval "$aaa"
    #declare -p nupdateinfos
    #eval "$nupdateinfos"
    #declare -p lsqs
    #eval "${lsqs[perl-Locale-Gettext]}"
    #declare -p lsq
    # download_release lsq/vim-mingw64-installer "$scriptdir"/files
    # download_release lsq/vime "$scriptdir"/files
    # https://www.geeksforgeeks.org/bash-scripting-how-to-check-if-variable-is-set/
    [[ ! -z "${option_build+'true'}" ]] && build_packages
    [[ ! -z "${option_report+'true'}" ]] && report "Updated packages" "${updated[@]}"
    [[ ! -z "${option_report+'true'}" ]] && report "Failed packages" "${failed[@]}"
    git status
    # git commit -a -m "Add changes"
fi
