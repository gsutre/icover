#!/bin/bash

# Modifications Copyright 2017 CNRS & Universite de Bordeaux

# Copyright 2017 Michael Blondin, Alain Finkel, Christoph Haase, Serge Haddad

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

self="$(basename "$0")"

# Configuration Variables ######################################################

# Default list of directories to benchmark.
DIRECTORIES="mist wahl-kroening medical bug_tracking soter"

# Default timeout in seconds (max CPU time) for each run.
TIMEOUT=2000

# No extra option by default.
OPTIONS=""

# No user-specified output file by default.
OUTFILE=""

# Default verbosity level.
VERBOSITY=1

# No file is skipped by default.
SKIP=0


# Helper functions #############################################################

error ()
{
    echo "$self: error: $1" >&2
}

#
# Log a message unless the given level (fist argument) is larger than the chosen
# VERBOSITY level.
#
log ()
{
    level=$1
    shift
    if [ $level -le $VERBOSITY ]; then
	echo -e "[$(date +"%H:%M:%S")]" "$(printf '%*s' $((2*level)))" "$*"
    fi
}

#
# Run a given command with timeout $TIMEOUT and store the results into temporary
# files:
# - $tmp_err:  the error output of the command
# - $tmp_out:  the standard output of the command
# - $tmp_time: the time statistics
# The time format "%U %S" stands for %User time + %System time.
#
run_cmd ()
{
    log 2 "Command:" "$*"
    \time -o "$tmp_time" -f "%U %S" \
	\timeout $TIMEOUT \
	$* 1> "$tmp_out" 2> "$tmp_err"
}


# Command-line Processing ######################################################

usage ()
{
    cat <<EOF
Usage: $self [options] <program>

  -d <lst>    Set the list of directories to benchmark.
  -h          Print this message and exit.
  -o <str>    Store results into the given file.
  -q          Decrease verbosity.
  -s <int>    Skip the first <int> files of each benchmark directory.
  -t <int>    Set the (CPU) timeout to <int> for each run.
  -v          Increase verbosity.
  -x <opt>    Append <opt> to the options passed to the program.
EOF
}

while getopts "d:ho:qs:t:vx:" option; do
    case $option in
	d)
	    DIRECTORIES="$OPTARG"
	    ;;
	h)
	    usage
	    exit 0
	    ;;
	o)
	    OUTFILE="$OPTARG"
	    ;;
	q)
	    VERBOSITY=$((VERBOSITY-1))
	    ;;
	s)
	    SKIP="$OPTARG"
	    ;;
	t)
	    TIMEOUT="$OPTARG"
	    ;;
	v)
	    VERBOSITY=$((VERBOSITY+1))
	    ;;
	x)
	    OPTIONS="$OPTIONS $OPTARG"
	    ;;
	*)
	    usage
	    exit 1
	    ;;
    esac
done

shift $(($OPTIND - 1))

program="$1"
shift

if [ $# -gt 0 ]; then
    error "unrecognized arguments: $*."
    exit 1
fi

if ! [[ "$SKIP" =~ ^[0-9]+$ ]]; then
    error "the argument \`$SKIP' of the \`-s' option should be an integer."
    exit 1
fi

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]]; then
    error "the argument \`$TIMEOUT' of the \`-t' option should be an integer."
    exit 1
fi

# Allow an empty program with empty options as a shortcut for icover with limit
# engine and options --pre --omega.
if [ -z "$program" ]; then
    if [ -z "$OPTIONS" ]; then
	program="limit"
	OPTIONS="--pre --omega"
    else
	usage
	exit 1
    fi
fi


# Auto-configuration and checks ################################################

# Sanitize the environment to help reproducibility.
export LC_ALL=C

# Check for GNU time.
if ! \time --version 2>&1 | grep -q "GNU time"; then
    error "couldn't find GNU time."
    exit 1
fi

# Check for GNU timeout.
if ! \timeout --version 2>&1 | grep -q "GNU coreutils"; then
    error "couldn't find GNU timeout."
    exit 1
fi

# Log file base name.
logbase="$program$(echo $OPTIONS | tr -d '[:space:]')"

# Temporary files.
tmp_err="tmp_err_$logbase"
tmp_out="tmp_out_$logbase"
tmp_time="tmp_time_$logbase"

# Check that temporary files are not already in use.
if [ -e "$tmp_err" -o -e "$tmp_out" -o -e "$tmp_time" ]; then
    error "existing temporary file(s). Is another benchmark.sh running?"
    exit 1
fi

# Check that the user-specified output file does not exist.
if [ -n "$OUTFILE" -a -e "$OUTFILE" ]; then
    error "existing output file \`$OUTFILE'."
    exit 1
fi


# Main #########################################################################

# Exit on SIGINT.
trap "exit" SIGINT

# Clear temporary files on exit.
trap "rm -f \"$tmp_err\" \"$tmp_out\" \"$tmp_time\"" EXIT

# Write header into the user-specified output file (if any).
if [ -n "$OUTFILE" ]; then
    echo "# Generated by $self on $(date)" > "$OUTFILE"
fi

# Perform benchmarks.
for dir in $DIRECTORIES
do
    # Get the *.spec files of all subdirectories
    files=$(find "$dir" -type f -name "*.spec" | sort)
    mkdir -p "$dir"/results
    logfile="$dir"/results/"$logbase".log

    # Backup and clear log file.
    if [ -e "$logfile" ]; then
	mv "$logfile" "$logfile".bak
    fi
    echo "# Generated by $self on $(date)" > "$logfile"

    log 0 "### Processing $dir (log file: $logfile) ###"

    skipped=0
    for file in $files
    do
	if [ $skipped -lt $SKIP ]; then
	    log 0 "Skipping $file."
	    skipped=$(($skipped+1))
	    continue
	fi

	log 0 "Verifying $file..."
	unset output

	# Obtain error and standard outputs, time statistics, and exit status.
	case "$program" in
	    limit|hfifos|hstacks|qcover)
		run_cmd python ../main.py $file $program $OPTIONS
		status=$?
		output="$(tail -n 1 "$tmp_out")"
		;;
	    mist-backward)
		run_cmd mist --backward $OPTIONS $file
		status=$?
		# Compute output according to standard output.
		output="$(sed -n -e 's/backward algorithm concludes \(.\)/\U\1/p' "$tmp_out")"
		;;
	    petrinizer)
		run_cmd ../petrinizer/src/main -refinement-int $OPTIONS $file.pl
		status=$?
		# Compute output according to exit status and standard output.
		if [ $status -eq 0 ] && \
		    grep -q 'The petri net satisfies the property' "$tmp_out"; then
		    output="Safe"
		elif [ $status -eq 2 ] && \
		    grep -q 'The petri net may not satisfy the property' "$tmp_out"; then
		    output="Unknown"
		    status=0
		fi
		;;
	    bfc)
		run_cmd ../bfc/bfc --target $file.tts.prop $OPTIONS $file.tts
		status=$?
		# Compute output according to exit status and standard output.
		if [ $status -eq 0 ] && \
		    grep -q 'VERIFICATION SUCCESSFUL' "$tmp_out"; then
		    output="Safe"
		elif [ $status -eq 10 ] && \
		    grep -q 'VERIFICATION FAILED' "$tmp_out"; then
		    output="Unsafe"
		    status=0
		fi
		;;
	    *)
		error "unknown program: $program."
		exit 1
		;;
	esac

	log 3 "Standard output:\n$(cat "$tmp_out")"
	log 3 "Error output:\n$(cat "$tmp_err")"
	log 3 "Time output:\n$(cat "$tmp_time")"

	# Detect timeouts and errors.
	if [ $status -eq 124 ]; then
	    output="Timeout"
	elif [ $status -ne 0 ]; then
	    output="Error"
	fi

	# Check that output has been computed.
	if [ -z "$output" ]; then
	    error "unable to compute output."
	fi

	# Compute the elapsed CPU time.
	elapsed=$(tail -n 1 "$tmp_time" | awk '{printf "%d", 1000*($1+$2);}')

	# Log the result and time.
	log 1 "Result: $output"
	log 1 "Time:   $elapsed ms"

	# Store output and time into the log file.
	echo $file $output $elapsed >> "$logfile"

	# Also store them into the user-specified output file (if any).
	if [ -n "$OUTFILE" ]; then
	    echo $file $output $elapsed >> "$OUTFILE"
	fi
    done

    # Print directory summary.
    log 1 "Summary:\n$(python summary.py "$dir" --tool "$logbase")"
done

# Print overall summary if more than one directory.
list=( $DIRECTORIES )

if [ "${#list[@]}" -gt "1" ]; then
    log 1 "### Overall summary ###\n$(python summary.py $DIRECTORIES \
	--mode overall --tool "$logbase")"
fi

exit
