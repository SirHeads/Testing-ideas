#!/bin/bash

# Perform a health check on the Qdrant service inside container 952
if pct exec 952 -- curl -s --fail http://localhost:6333 > /dev/null; then
    echo "Qdrant service in container 952 is healthy."
    exit 0
else
    echo "Qdrant service in container 952 is not responding."
    exit 1
fi