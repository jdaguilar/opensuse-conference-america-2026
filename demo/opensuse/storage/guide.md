# Guide: Filestash + Apache Ozone Setup & Troubleshooting

This guide summarizes the setup process and key troubleshooting steps for connecting Filestash to Apache Ozone's S3 Gateway in a local Kubernetes environment.

## 1. Deployment Overview

- **Apache Ozone**: Deployed via Helm using the official charts.
- **Filestash**: Deployed via a Kubernetes manifest (`filestash.yaml`).
- **Namespace**: `data-storage`

## 2. Setup with Automation Scripts

For a consistent installation, use the provided bash scripts. It is recommended to run these from the `demo/opensuse/` directory.

### Step 1: Initialize Helm Repositories
Ensure all necessary Helm charts are available:
```bash
./scripts/install-repos.sh
```

### Step 2: Deploy Storage (Ozone & Filestash)
This script handles the namespace creation, Ozone Helm installation, and Filestash manifest application:
```bash
./scripts/install-storage.sh
```

## 3. Configuration Details

### Admin Password Reset
If you forget the Filestash admin password, you can reset it by adding the `ADMIN_PASSWORD` environment variable to the deployment with a bcrypt hash.

**bcrypt hash for "admin":**
`$2b$12$bHy0tCbZjCkjPCCodiMO0epdlOvoZie5qHBFZADoBXIRGVSXoXSfy`

```yaml
env:
  - name: ADMIN_PASSWORD
    value: "$2b$12$bHy0tCbZjCkjPCCodiMO0epdlOvoZie5qHBFZADoBXIRGVSXoXSfy"
```

### Ozone S3 Connectivity
To connect Filestash to Ozone, use the following parameters in the Admin Panel (`/admin`):

| Parameter | Value |
| :--- | :--- |
| **Backend** | `S3` |
| **Endpoint** | `http://ozone-s3g-rest:9878` |
| **Access Key** | `hadoop` |
| **Secret Key** | `ozone` (or any string if security is disabled) |
| **S3 Path Style** | **Enabled** (Required) |

## 3. Troubleshooting & Gotchas

### Common Service Name Mismatch
> [!IMPORTANT]
> In most Helm-based Ozone deployments, the S3 Gateway service is named **`ozone-s3g-rest`**, not just `ozone-s3g`. Using the wrong service name will result in connection timeouts or resolution errors.

### Security Mode
If `ozone s3 getsecret` fails with an error about security being disabled, you are in **Unsecure Mode**. In this mode:
- Use `hadoop` as the Access Key.
- Any value works for the Secret Key.

### Initializing Buckets
Ozone S3 typically expects a volume named `s3v`. You can manually create a bucket to verify the connection:
```bash
kubectl exec -n data-storage ozone-om-0 -- ozone sh bucket create /s3v/filestash-data
```

## 4. Verification Commands

Check if the S3 Gateway is reachable from the Filestash pod:
```bash
kubectl exec -n data-storage deployment/filestash -- curl -v http://ozone-s3g-rest:9878/
```

Confirm buckets are visible in Ozone:
```bash
kubectl exec -n data-storage ozone-om-0 -- ozone sh bucket list /s3v
```
