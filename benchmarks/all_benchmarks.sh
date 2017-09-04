#!/bin/bash

TOOLS="icover qcover petrinizer mist-backward bfc"

for tool in $TOOLS
do
    echo "Benchmarking tool \`$tool'"
    if [ "$tool" = "icover" ]; then
	tool=""
    fi
    ./benchmark.sh $tool
done
