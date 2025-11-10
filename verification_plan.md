# Phoenix Service Verification Plan

This plan outlines the steps to verify the successful deployment of the Phoenix services from your local machine.

## 1. Verify DNS Resolution

We will use the `ping` command to ensure that the hostnames for Portainer and Traefik are correctly resolving to the IP address of the Nginx gateway (`10.0.0.153`).

*   **Command:**
    ```bash
    ping -c 3 portainer.internal.thinkheads.ai
    ping -c 3 traefik.internal.thinkheads.ai
    ```
*   **Expected Outcome:** Both commands should show that you are pinging `10.0.0.153` and that you are receiving replies.

## 2. Verify Network Connectivity

Next, we will use `curl` to verify that the Nginx gateway is responding to HTTPS requests for our services. Since we are using an internal CA, we will use the `-k` flag to ignore certificate validation for this step.

*   **Command:**
    ```bash
    curl -k -v https://portainer.internal.thinkheads.ai
    curl -k -v https://traefik.internal.thinkheads.ai/dashboard/
    ```
*   **Expected Outcome:**
    *   For Portainer, you should see a `302` redirect to `/auth/login` and a response that includes HTML for the Portainer login page.
    *   For Traefik, you should receive a `200 OK` and a response containing the HTML for the Traefik dashboard.

## 3. Verify UI Access in Browser

The final step is to access the dashboards in your web browser.

*   **Action:**
    1.  Ensure you have imported and trusted the `phoenix_root_ca.crt` in your operating system or browser.
    2.  Open your web browser and navigate to the following URLs:
        *   `https://portainer.internal.thinkheads.ai`
        *   `https://traefik.internal.thinkheads.ai`
*   **Expected Outcome:**
    *   You should see the Portainer login page without any certificate warnings.
    *   You should see the Traefik dashboard without any certificate warnings.