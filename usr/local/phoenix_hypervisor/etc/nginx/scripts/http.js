// /etc/nginx/scripts/http.js

function get_model(r) {
    try {
        if (r.requestBuffer) {
            const body = JSON.parse(r.requestBuffer);
            return body.model || '';
        }
    } catch (e) {
        r.error(`Error parsing JSON: ${e}`);
    }
    return '';
}

export default { get_model };