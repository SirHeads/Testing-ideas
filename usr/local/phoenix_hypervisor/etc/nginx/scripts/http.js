import fs from 'fs';

function get_portainer_jwt(r) {
    const token_path = '/api_tokens/portainer_jwt.token';
    try {
        if (fs.existsSync(token_path)) {
            return fs.readFileSync(token_path).toString().trim();
        }
    } catch (e) {
        r.error(`Failed to read Portainer JWT: ${e.message}`);
    }
    return '';
}

export default { get_portainer_jwt };