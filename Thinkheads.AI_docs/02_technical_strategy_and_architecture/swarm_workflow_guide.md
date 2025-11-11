# Swarm Workflow Guide

This guide outlines the new workflow for managing isolated, multi-tenant application environments using the Docker Swarm integration in `phoenix-cli`.

## 1. One-Time Setup

To initialize the Swarm cluster and deploy the Portainer dashboard, run the following command:

```bash
phoenix sync all
```

This command will:
1.  Create the necessary VMs.
2.  Initialize the Docker Swarm.
3.  Join the manager and worker nodes to the Swarm.
4.  Deploy the Portainer service to the manager node.

## 2. Managing Environments

### 2.1. Deploying a New Environment

To deploy a new, isolated environment for a specific stack, use the `phoenix swarm deploy` command:

```bash
phoenix swarm deploy <stack_name> --env <environment_name>
```

For example, to deploy a new development environment for the `thinkheads_ai_app` stack, you would run:

```bash
phoenix swarm deploy thinkheads_ai_app --env dev1
```

This will create a new, isolated environment named `dev1`, with all services, networks, and configs prefixed with `dev1_`.

### 2.2. Removing an Environment

To remove an environment, use the `phoenix swarm rm` command:

```bash
phoenix swarm rm <stack_name> --env <environment_name>
```

For example, to remove the `dev1` environment:

```bash
phoenix swarm rm thinkheads_ai_app --env dev1
```

## 3. Monitoring

The Portainer UI is available for monitoring the state of the Swarm and the various deployed environments. It should be used as a "pane of glass" for observation, not for deployments.