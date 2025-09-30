#!/bin/bash

# --- Deprecation Warning ---
echo "WARNING: The phoenix_orchestrator.sh script is deprecated and will be removed in a future version." >&2
echo "Please use the new 'phoenix' CLI instead." >&2
echo "" >&2

# --- Argument Parsing and Command Mapping ---
new_command="phoenix"
id_args=()

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --setup-hypervisor)
            new_command="$new_command setup"
            shift
            ;;
        --delete)
            new_command="$new_command delete $2"
            shift 2
            ;;
        --reconfigure)
            new_command="$new_command reconfigure"
            shift
            ;;
        --smoke-test)
            new_command="$new_command smoke-test"
            shift
            ;;
        --test)
            new_command="$new_command test $2"
            shift 2
            ;;
        --dry-run|--wipe-disks|--LetsGo|--provision-template)
            # Pass these flags through to the new command
            new_command="$new_command $1"
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            id_args+=("$1")
            shift
            ;;
    esac
done

# --- Construct and Execute the New Command ---
if [ ${#id_args[@]} -gt 0 ]; then
    new_command="$new_command orchestrate ${id_args[*]}"
fi

echo "Executing command: $new_command" >&2
eval "$new_command"