#!/bin/bash
# check_ollama.sh
# This script checks the health of the Ollama service.

# Check if a process is listening on port 11434
if ! lsof -i:11434 -sTCP:LISTEN -t >/dev/null; then
    echo "Error: No process is listening on port 11434."
    exit 1
fi

# Check if the API is responsive
if ! curl --fail --silent http://localhost:11434/ > /dev/null; then
    echo "Error: Ollama API is not responding."
    exit 1
fi

echo "Success: Ollama is healthy."
exit 0