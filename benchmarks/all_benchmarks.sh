#!/bin/bash

TOOLS="icover qcover petrinizer mist-backward bfc"

for tool in $TOOLS
do
    ./benchmark.sh $tool
done

