# Metadata: {"chunk_id": "phoenix_fly-1.0", "keywords": ["animation", "phoenix", "terminal"], "comment_type": "block"}
#!/bin/bash
# phoenix_fly.sh
# Displays the Phoenix flying animation with an optional final message
# Version: 1.0.1 (Added final message support)
# Author: (Incorporated logic from original common.sh and phoenix_fly.txt)

# Main: Displays a terminal animation of the Phoenix with text
# Args: Optional message to display after animation
# Returns: 0 on success
# Metadata: {"chunk_id": "phoenix_fly-1.1", "keywords": ["animation", "phoenix"], "comment_type": "block"}
# Algorithm: Phoenix animation
# Draws text incrementally, moves it diagonally, removes it, displays optional message
# Keywords: [animation, phoenix, terminal]
# TODO: Validate terminal size and enhance message styling

# Initialize terminal
clear
trap "clear; tput cnorm; exit" 2 15
tput civis

# draw_combined: Draws Phoenix text at specified position with partial visibility
# Args: $1: Row, $2: Column, $3: Number of visible characters
# Returns: None
# Metadata: {"chunk_id": "phoenix_fly-1.2", "keywords": ["animation", "draw"], "comment_type": "block"}
# Algorithm: Text drawing
# Clears screen, prints empty rows, displays partial or full text at position
# Keywords: [animation, draw, terminal]
draw_combined() {
    local row=$1
    local col=$2
    local visible_chars=$3
    clear
    for i in $(seq 1 $((row-1))); do
        echo
    done
    full_string="^=||=8>     The Phoenix is Rising!"
    if [ $visible_chars -gt 0 ]; then
        visible_string="${full_string:0:$visible_chars}"
        printf "%*s\n" $col "$visible_string"
    fi
}

# Animation sequence
# Metadata: {"chunk_id": "phoenix_fly-1.3", "keywords": ["animation"], "comment_type": "block"}
row=1
col=1
full_string="^=||=8>     The Phoenix is Rising!"
string_length=${#full_string}
for i in $(seq 1 $string_length); do
    draw_combined $row $col $i
    sleep 0.15
done
char_count=0
for i in $(seq 1 90); do
    col=$((col + 1))
    char_count=$((char_count + 1))
    if [ $((char_count % 12)) -eq 0 ]; then
        row=$((row + 1))
    fi
    draw_combined $row $col $string_length
    sleep 0.10
done
for i in $(seq $string_length -1 1); do
    draw_combined $row $col $i
    sleep 0.15
done

# Display final message
# Metadata: {"chunk_id": "phoenix_fly-1.4", "keywords": ["message"], "comment_type": "block"}
# TODO: Add color or formatting options for final message
tput cnorm
clear
if [[ $# -gt 0 ]]; then
    final_message="$*"
    term_width=$(tput cols)
    msg_width=${#final_message}
    padding=$(( (term_width - msg_width) / 2 ))
    printf "%*s%s\n" $padding "" "$final_message"
fi

tput cnorm
clear