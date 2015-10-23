#! /usr/bin/env bash

if [[ ${BASH_VERSINFO[0]} -lt 4 ]]; then
    echo "error: you need at least bash-4.0 to run this script."    >&2
    echo "You are currently using version $BASH_VERSION."           >&2
    exit 2
fi

# Compute script basename and report full path
PROG=$(basename $0)
REPORT="$PWD/${PROG%.*}.report"

# Colors
RED="$(tput setaf 1)"
GREEN="$(tput setaf 2)"
BLUE="$(tput setaf 4)"
WHITE="$(tput setaf 7)$(tput bold)"
RESET="$(tput sgr0)"

# Display the usage and exit
function usage {
    POSITIONAL="<remote> <repo-info> [<repo-info> ...]"
    echo "usage: ${WHITE}$PROG${RESET} [-n] $POSITIONAL"                     >&2
    echo ""                                                                  >&2
    echo "${RED}OPTIONS${RESET}"                                             >&2
    echo "    ${GREEN}-n${RESET}"                                            >&2
    echo "        Dry-run mode, do not execute git commands."                >&2
    echo ""                                                                  >&2
    echo "${RED}POSITIONAL ARGUMENTS${RESET}"                                >&2
    echo "    ${GREEN}<remote>${RESET}"                                      >&2
    echo "        The base URL to the remote."                               >&2
    echo ""                                                                  >&2
    echo "    ${GREEN}<repo-info>${RESET}"                                   >&2
    echo "        Must contain the repository name, and optionally a list of">&2
    echo "        of branches. If the branches are specified, this benchmark">&2
    echo "        program will try more strategies that fetch only those"    >&2
    echo "        branches."                                                 >&2
    echo ""                                                                  >&2
    echo "${RED}REPOSITORY INFORMATION${RESET}"                              >&2
    echo "    The syntax of the repository information is"                   >&2
    echo ""                                                                  >&2
    echo "        <repo-name>[:<branch-name>[,<branch-name> ...]]"           >&2
    echo ""                                                                  >&2
    exit 1
}

# Parse the command line
DRY_RUN=false
while getopts hn FLAG; do
    case $FLAG in
        n)
            DRY_RUN=true
            ;;
        h|\?)
            usage
            ;;
    esac
done

# Move on to the next argument
shift $((OPTIND-1))

if [[ $# -lt 2 ]]; then
    echo "$0: missing parameter(s)"
    usage
fi
REMOTE=$1
shift; REPOSITORIES=$@; NB_REPOSITORIES=$#

# Output the repository URL
#
# PARAMETERS
#   $1: repository name
function repository_url {
    echo "ssh://$REMOTE/$1"
}

# Display a colorful title
#
# PARAMETERS
#   $@: all arguments are printed
function title {
    echo "${GREEN}==>${RESET} ${WHITE}$@${RESET}"
}

# Display a colorful section
#
# PARAMETERS
#   $@: all arguments are printed
function section {
    echo "${BLUE}==>${RESET} ${WHITE}$@${RESET}"
}

# Display a warning message
#
# PARAMETERS
#   $@: all arguments are printed
function warn {
    echo "${RED}==>${RESET} ${WHITE}$@${RESET}"
}

# Output the name of a repository from a <repo-info>
#
# PARAMETERS
#   $1: repository information
function repo_info_extract_name {
    echo ${1%:*}
}

# Output a comma-separated list of branches from a <repo-info>
#
# PARAMETERS
#   $1: repository information
function repo_info_extract_branches {
    echo ${1#*:}
}

# Output the formatted branch arguments for git-remote
# For exemple, for the following arguments list:
#
#   master develop fixup
#
# The formatted output is:
#
#   -t master -t develop -t fixup
#
# PARAMETERS
#   $@: list of branches to format
function format_git_remote_branch_options {
    GIT_REMOTE_OPTIONS=""
    for branch in $@; do
        if [ -z "$GIT_REMOTE_OPTIONS" ]; then
            GIT_REMOTE_OPTIONS="-t $branch"
        else
            GIT_REMOTE_OPTIONS="$GIT_REMOTE_OPTIONS -t $branch"
        fi
    done
    echo $GIT_REMOTE_OPTIONS
}

# Output the path to a newly created temporary directory with the given prefix
#
# PARAMETERS
#   $1: temporary directory prefix
function create_tempdir {
    mktemp -d -t $1-XXXXXX
}

# git clone REPOSITORY
#
# PARAMETERS
#   $1: repository name
function plain_clone {
    REPOSITORY="$1"
    REPOSITORY_URL="$(repository_url $REPOSITORY)"
    section "Commands"
    echo "  git clone $REPOSITORY_URL"

    section "Benchmark"
    tmpdir="$(create_tempdir plain-clone)"
    (
        cd $tmpdir
        if ! $DRY_RUN; then
            time (
                git clone $REPOSITORY_URL
            )
        fi
    )
    rm -rf $tmpdir
}

# git clone --depth 1 REPOSITORY
#
# PARAMETERS
#   $1: repository name
function shallow_clone {
    REPOSITORY="$1";
    REPOSITORY_URL="$(repository_url $REPOSITORY)"
    section "Commands"
    echo "  git clone --depth 1 $REPOSITORY_URL"

    section "Benchmark"
    tmpdir="$(create_tempdir shallow-clone)"
    (
        cd $tmpdir
        if ! $DRY_RUN; then
            time (
                git clone --depth 1 $REPOSITORY_URL
            )
        fi
    )
    rm -rf $tmpdir
}

# git clone --branch BRANCH --single-branch REPOSITORY
#
# PARAMETERS
#   $1: repository name
#   $2: branch name
function single_branch_clone {
    REPOSITORY="$1"; BRANCH="$2"
    REPOSITORY_URL="$(repository_url $REPOSITORY)"
    section "Commands"
    echo "  git clone --branch $BRANCH --single-branch $REPOSITORY_URL"

    section "Benchmark"
    tmpdir="$(create_tempdir single-branch-clone)"
    (
        cd $tmpdir
        if ! $DRY_RUN; then
            time (
                git clone --branch $BRANCH --single-branch $REPOSITORY_URL
            )
        fi
    )
    rm -rf $tmpdir
}

# git init
# git remote add -t BRANCH_0 -t BRANCH_1 -f origin REPOSITORY
# git checkout master
#
# PARAMETERS
#   $1: repository name
#   $2: repository URL
#   $*: branches name
function selected_branches_clone {
    REPOSITORY="$1"
    REPOSITORY_URL="$(repository_url $REPOSITORY)"
    shift; GIT_REMOTE_OPTIONS="$(format_git_remote_branch_options $@)"

    section "Commands"
    echo "  git init"
    echo "  git remote add $GIT_REMOTE_OPTIONS -f origin $REPOSITORY_URL"
    echo "  git checkout master"

    section "Benchmark"
    tmpdir="$(create_tempdir selected-branches-clone)"
    (
        cd $tmpdir
        if ! $DRY_RUN; then
            time (
                mkdir $REPOSITORY && cd $REPOSITORY
                git init
                git remote add $GIT_REMOTE_OPTIONS -f origin $REPOSITORY_URL
                git checkout master
            )
        fi
    )
    rm -rf $tmpdir
}

# git init
# git config remote.origin.tagopt --no-tags
# git remote add -t BRANCH_0 -t BRANCH_1 -f origin REPOSITORY
# git checkout master
# git config --unset remote.origin.tagopt
#
# PARAMETERS
#   $1: repository name
#   $2: repository URL
#   $*: branches name
function selected_branches_no_tags_clone {
    REPOSITORY="$1"
    REPOSITORY_URL="$(repository_url $REPOSITORY)"
    shift; GIT_REMOTE_OPTIONS="$(format_git_remote_branch_options $@)"

    section "Commands"
    echo "  git init"
    echo "  git config remote.origin.tagopt --no-tags"
    echo "  git remote add $GIT_REMOTE_OPTIONS -f origin $REPOSITORY_URL"
    echo "  git checkout master"
    echo "  git config --unset remote.origin.tagopt"

    section "Benchmark"
    tmpdir="$(create_tempdir selected-branches-no-tags-clone)"
    (
        cd $tmpdir
        if ! $DRY_RUN; then
            time (
                mkdir $REPOSITORY
                cd $REPOSITORY
                git init
                git config remote.origin.tagopt --no-tags
                git remote add $GIT_REMOTE_OPTIONS -f origin $REPOSITORY_URL
                git checkout master
                git config --unset remote.origin.tagopt
            )
        fi
    )
    rm -rf $tmpdir
}

# Bash magic to strip escape sequences from the output redirected to the log
# file. Requires Bash 4 and higher.
echo -n >$REPORT
exec 4<&1 5<&2 1>&2>&>(tee >(
    if [[ "$(uname)" == "Darwin" ]]; then
        # Use GNU sed on Darwin (install with Homebrew: brew install gnu-sed)
        PATH="/usr/local/opt/gnu-sed/libexec/gnubin:$PATH"
    fi
    if ! (
        sed --version 2> /dev/null |head -n1 |grep "GNU sed"
        exit $?
    ) > /dev/null 2>&1; then
        echo "GNU sed not installed, logs will contain escape sequence." >&2
        cat - > $REPORT
    else
        sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g' | \
        sed -r 's/\x1B\(B//g' > $REPORT
    fi
))

# Run benchmarks
(
    if [[ $NB_REPOSITORIES -eq 1 ]]; then
        total="1 repository"
    else
        total="$NB_REPOSITORIES repositories"
    fi
    title "Benchmarking git clone strategies for $total:"
    for repo_info in $REPOSITORIES; do
        case $repo_info in
            *:*)
                # repo_info contains the repository name and a list of branches
                repository=$(repo_info_extract_name $repo_info)
                branches=$(repo_info_extract_branches $repo_info)
                echo "  * $repository (${branches//,/, })"
                ;;
            *)
                # repo_info contains only the repository name
                echo "  * $repo_info"
                ;;
        esac
    done
    section "Host information: $(uname -sm)"
    section "Operating system details"; uname -a
    section "Git version: $(git --version)"

    $DRY_RUN && warn "Dry-mode activated: no actual command will be tested"

    for repo_info in $REPOSITORIES; do
        repository=$(repo_info_extract_name $repo_info)
        title "Benchmarking ${GREEN}$repository"
        title "Testing plain clone strategy"
        plain_clone $repository

        title "Testing shallow clone strategy"
        shallow_clone $repository

        branches=$(repo_info_extract_branches $repo_info)
        if [ -z "$branches" ]; then
            # No branches specified, do not attempt any strategy involving
            # branches.
            continue
        fi

        branches=${branches//,/ }
        for branch in $branches; do
            title "Testing single branch clone strategy for ${BLUE}$branch"
            single_branch_clone $repository $branch
        done

        # Only attempt multiple branches strategy if more than one branch were
        # provided.
        case $repo_info in
            *:*,*)
                # Multiple branches provided, attempt the single branch on each
                # one of them.
                title "Testing selected branches clone strategy"
                selected_branches_clone $repository $branches

                title "Testing selected branches (no tags) clone strategy"
                selected_branches_no_tags_clone $repository $branches
                ;;
        esac
    done
)

# Restore shell I/Os
exec 1<&4 4>&- 2<&5 5>&-
echo "Output saved to $REPORT"
