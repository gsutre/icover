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

TIMEFORMAT="%U %S" # Important: %User time + %System time
: ${DIRECTORIES:="mist wahl-kroening medical bug_tracking soter"}
: ${TIMEOUT:=2000}

function echo_time {
    echo "[$(date +"%H:%M:%S")] $1 $2 $3 $4 $5 $6"
}

# Arguments
if [ "$1" = "" ]; then
    program="icover"
else
    program=$1
fi

# Check that temporary files are not already in use
if [ -e temp_output -o -e temp_time ]; then
    echo "Existing temporary file(s). Is another benchmark.sh running?" >&2
    exit 1
fi

# Perform benchmarks
for dir in $DIRECTORIES
do
    files=$(find ./$dir -type f -name "*.spec") # .spec of all subdirectories
    mkdir -p $dir/results
    logfile=./$dir/results/$program.log

    [ -e $logfile ] && mv $logfile $logfile.bak # Backup and clear logs file

    echo_time "### Processing" $dir "###"

    skip=1
    for file in $files
    do
	if [ "$skip" -lt "0" ]; then
	    echo_time " Skiping $file."
	    skip=$(($skip+1))
	    continue
	fi

	echo_time " Verifying $file..."

	# Obtain output and running time
	if [ "$program" = "icover" ]; then
	    (time (timeout $TIMEOUT python ../main.py $file limit --pre --omega | tail -1)) 1> temp_output \
	                                                                                    2> temp_time
	    if [ "$?" -ne 0 ]; then
		echo_time " Tool error ($program)" >&2
		cat temp_time
		exit 1
	    fi
	    output=$(cat temp_output)
	elif [ "$program" = "qcover" ]; then
	    (time (timeout $TIMEOUT python ../main.py $file qcover)) 1> temp_output \
	                                                             2> temp_time
	    if [ "$?" -ne 0 ]; then
		echo_time " Tool error ($program)" >&2
		cat temp_time
		exit 1
	    fi
	    output=$(cat temp_output)
	elif [ "$program" = "mist-backward" ]; then
	    (time (timeout $TIMEOUT mist --backward $file)) 1> temp_output \
	                                                    2> temp_time
	    output=$(python parse_output.py temp_output --tool $program)
	elif [ "$program" = "petrinizer" ]; then
	    (time (timeout $TIMEOUT ../petrinizer/src/main \
		              -refinement-int $file.pl)) 1> temp_output \
	                                                 2> temp_time
	    result=$?
	    if [ "$result" = "0" ]; then
		output="Safe"
	    elif [ "$result" = "1" ]; then
		output="Unsafe"
	    elif [ "$result" = "2" ]; then
		output="Unknown"
	    fi
	elif [ "$program" = "bfc" ]; then
	    (time (timeout $TIMEOUT ../bfc/bfc --target $file.tts.prop \
		                               $file.tts)) 1> temp_output \
	                                                   2> temp_time

	    tail -n 1 temp_time > temp_time.tail && mv temp_time.tail temp_time
	    output=$(python parse_output.py temp_output --tool $program)
	fi

	# An empty output should come from a timeout
	if [ "$output" = "" ]; then
	    output="Timeout"
	fi

	# Process timing
	elapsed=$(cat temp_time | awk '{print 1000*($1+$2);}')

	# Clear temporary files
	rm temp_output temp_time

	# Outputs
	echo_time "   Result:" $output          # Console ouput
	echo_time "   Time:  " $elapsed "ms"    #

	echo $file $output $elapsed >> $logfile # Logs output
    done

    # Print directory summary
    echo_time " Summary:"
    python summary.py $dir --tool $program
done

# Print overall summary if more than one directory
list=( $DIRECTORIES )

if [ "${#list[@]}" -gt "1" ]; then
    echo_time "### Overall summary ###"
    python summary.py $DIRECTORIES --mode overall --tool $program
fi
