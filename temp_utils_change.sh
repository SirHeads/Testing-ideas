# =====================================================================================
# Function: generate_rule_string (Corrected)
# Description: Generates a correctly formatted firewall rule string from a JSON object.
# =====================================================================================
generate_rule_string() {
    local rule_json="$1"
    local type=$(echo "$rule_json" | jq -r '.type // ""')
    local action=$(echo "$rule_json" | jq -r '.action // ""')
    local proto=$(echo "$rule_json" | jq -r '.proto // ""')
    local source=$(echo "$rule_json" | jq -r '.source // ""')
    local dest=$(echo "$rule_json" | jq -r '.dest // ""')
    local port=$(echo "$rule_json" | jq -r '.port // ""')
    local iface=$(echo "$rule_json" | jq -r '.iface // ""')
    local comment=$(echo "$rule_json" | jq -r '.comment // ""')

    # Proxmox firewall rules are case-insensitive, but uppercase is conventional
    local rule_string="${type^^} ${action^^}"

    [ -n "$iface" ] && rule_string+=" -iface ${iface}"
    [ -n "$proto" ] && rule_string+=" -proto ${proto}"
    [ -n "$source" ] && rule_string+=" -source ${source}"
    [ -n "$dest" ] && rule_string+=" -dest ${dest}"
    [ -n "$port" ] && rule_string+=" -dport ${port}"
    [ -n "$comment" ] && rule_string+=" -comment \"${comment}\""
    
    echo "$rule_string"
}