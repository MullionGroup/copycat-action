#!/bin/bash
#
# @author André Storhaug <andr3.storhaug@gmail.com>
# @date 2021-05-01
# @license MIT
# @version 3.2.4

set -o pipefail

shopt -s extglob globstar nullglob dotglob

PERSONAL_TOKEN="$INPUT_PERSONAL_TOKEN"
SRC_PATH="$INPUT_SRC_PATH"
DST_PATH="$INPUT_DST_PATH"
DST_OWNER="$INPUT_DST_OWNER"
DST_REPO_NAME="$INPUT_DST_REPO_NAME"
SRC_BRANCH="$INPUT_SRC_BRANCH"
DST_BRANCH="$INPUT_DST_BRANCH"
CLEAN="$INPUT_CLEAN"
FILE_FILTER="$INPUT_FILE_FILTER"
FILTER="$INPUT_FILTER"
EXCLUDE="$INPUT_EXCLUDE"
SRC_WIKI="$INPUT_SRC_WIKI"
DST_WIKI="$INPUT_DST_WIKI"
COMMIT_MESSAGE="$INPUT_COMMIT_MESSAGE"
USERNAME="$INPUT_USERNAME"
EMAIL="$INPUT_EMAIL"
RM_TOP_DIR="$INPUT_RM_TOP_DIR"
FORCE_PUSH="$INPUT_FORCE_PUSH"

if [[ -z "$SRC_PATH" ]]; then
    echo "SRC_PATH environment variable is missing. Cannot proceed."
    exit 1
fi

if [[ -z "$DST_OWNER" ]]; then
    echo "DST_OWNER environment variable is missing. Cannot proceed."
    exit 1
fi

if [[ -z "$DST_REPO_NAME" ]]; then
    echo "DST_REPO_NAME environment variable is missing. Cannot proceed."
    exit 1
fi

if [ "$SRC_WIKI" = "true" ]; then
    SRC_WIKI=".wiki"
else
    SRC_WIKI=""
fi

if [ "$DST_WIKI" = "true" ]; then
    DST_WIKI=".wiki"
else
    DST_WIKI=""
fi

if [[ -n "$EXCLUDE" && -z "$FILTER" ]]; then
    FILTER="**"
fi

BASE_PATH=$(pwd)
DST_PATH="${DST_PATH:-${SRC_PATH}}"

USERNAME="${USERNAME:-${GITHUB_ACTOR}}"
EMAIL="${EMAIL:-${GITHUB_ACTOR}@users.noreply.github.com}"

SRC_BRANCH="${SRC_BRANCH:-master}"
DST_BRANCH="${DST_BRANCH:-master}"

SRC_REPO="${GITHUB_REPOSITORY}${SRC_WIKI}"
SRC_REPO_NAME="${GITHUB_REPOSITORY#*/}${SRC_WIKI}"
DST_REPO="${DST_OWNER}/${DST_REPO_NAME}${DST_WIKI}"
DST_REPO_NAME="${DST_REPO_NAME}${DST_WIKI}"

DST_REPO_DIR=dst_repo_dir
FINAL_SOURCE="${SRC_REPO_NAME}/${SRC_PATH}"

git config --global user.name "${USERNAME}"
git config --global user.email "${EMAIL}"

if [[ -z "$FILE_FILTER" ]]; then
    echo "Copying \"${SRC_REPO_NAME}/${SRC_PATH}\" and pushing it to ${DST_OWNER}/${DST_REPO_NAME}"
else
    echo "Copying files matching \"${FILE_FILTER}\" from \"${SRC_REPO_NAME}/${SRC_PATH}\" and pushing it to ${DST_OWNER}/${DST_REPO_NAME}"
fi

git clone --branch ${SRC_BRANCH} --single-branch --depth 1 https://${PERSONAL_TOKEN}@github.com/${SRC_REPO}.git
if [ "$?" -ne 0 ]; then
    echo >&2 "Cloning '$SRC_REPO' failed"
    exit 1
fi
rm -rf ${SRC_REPO_NAME}/.git

if [[ -n "$FILE_FILTER" ]]; then
    find ${SRC_REPO_NAME}/ -type f -not -name "${FILE_FILTER}" -exec rm {} \;
fi

if [[ -n "$FILTER" ]]; then
    tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
    mkdir ${temp_dir}/${SRC_REPO_NAME}
    cd ${SRC_REPO_NAME}
    FINAL_SOURCE="${tmp_dir}/${SRC_REPO_NAME}/${SRC_PATH}"
    SAVEIFS=$IFS
    IFS=$(echo -en "\n\b")
    for f in ${FILTER} ; do
        [ -e "$f" ] || continue
        [ -d "$f" ] && continue
        if [[ -n "$EXCLUDE" ]] ; then
            [[ "$f" == $EXCLUDE ]] && continue
        fi
        file_dir=$(dirname "${f}")
        mkdir -p "${tmp_dir}/${SRC_REPO_NAME}/${file_dir}" && cp "${f}" "${tmp_dir}/${SRC_REPO_NAME}/${file_dir}"
    done
    IFS=$SAVEIFS
    cd ..
fi


git clone --branch ${DST_BRANCH} --single-branch --depth 1 https://${PERSONAL_TOKEN}@github.com/${DST_REPO}.git ${DST_REPO_DIR}
if [ "$?" -ne 0 ]; then
    echo >&2 "Cloning branch '$DST_BRANCH' in '$DST_REPO' failed"
    echo >&2 "Falling back to default branch"
    git clone --single-branch --depth 1 https://${PERSONAL_TOKEN}@github.com/${DST_REPO}.git ${DST_REPO_DIR}
    cd ${DST_REPO_DIR} || exit "$?"
    echo >&2 "Creating branch '$DST_BRANCH'"
    git checkout -b ${DST_BRANCH}
    if [ "$?" -ne 0 ]; then
        echo >&2 "Creation of Branch '$DST_BRANCH' failed"
        exit 1
    fi
    cd ..
fi

if [ "$CLEAN" = "true" ]; then
    if [ -f "${DST_REPO_DIR}/${DST_PATH}" ] ; then
        find "${DST_REPO_DIR}/${DST_PATH}" -type f -not -path '*/\.git/*' -delete
    elif [ -d "${DST_REPO_DIR}/${DST_PATH}" ] ; then
        find "${DST_REPO_DIR}/${DST_PATH%/*}"/* -type f -not -path '*/\.git/*' -delete
    else
        echo >&2 "Nothing to clean 🧽"
    fi
fi

mkdir -p "${DST_REPO_DIR}/${DST_PATH%/*}" || exit "$?"


pwd

cp -rf "${FINAL_SOURCE}" "${DST_REPO_DIR}/${DST_PATH}" || exit "$?"


cd "${DST_REPO_DIR}" || exit "$?"

# if rm_top_dir is true, remove the top directory(s) from the destination path by copying the contents of 
if [ "$RM_TOP_DIR" = "true" ]; then
    # cd to the DST_PATH directory
    echo dst_path: "${DST_PATH}"
    echo src_path: "${SRC_PATH}"
    echo final_source: "${FINAL_SOURCE}"
    echo "${DST_REPO_DIR}/${DST_PATH}"
    
    cd "${DST_PATH}" || exit "$?"
    pwd
  
    if [ -d "${SRC_PATH}" ] ; then
        # recursively copy the contents of the source path to the current directory and rm the source directory. Exit with code 1 if the copy fails
        cp -rf "${SRC_PATH}"/* . && rm -rf "${SRC_PATH}" || exit "$?"
        
    else
        # exit with error and error message
        echo >&2 "Source directory does not exist"
        exit 1
    fi
fi
pwd



if [[ -z "${COMMIT_MESSAGE}" ]]; then
    if [ -f "${BASE_PATH}/${FINAL_SOURCE}" ]; then
        COMMIT_MESSAGE="Update file in \"${SRC_PATH}\" from \"${GITHUB_REPOSITORY}\""
    else
        COMMIT_MESSAGE="Update file(s) \"${SRC_PATH}\" from \"${GITHUB_REPOSITORY}\""
    fi
fi

if [ -z "$(git status --porcelain)" ]; then
    # Working directory is clean
    echo "No changes detected "
else
    # Uncommitted changes
    git add -A
    git commit --message "${COMMIT_MESSAGE}"
    
    # if force push is true, force push to the destination branch
    if [ "$FORCE_PUSH" = "true" ]; then
        git push --force origin ${DST_BRANCH}
    else
        git push origin ${DST_BRANCH}
    fi
fi

echo "Copying complete 👌"
