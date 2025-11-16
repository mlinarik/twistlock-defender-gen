#!/usr/bin/env bash
set -euo pipefail

# Interactive multi-OS-friendly installer for a single-container Prisma Cloud Defender
# - Designed for Linux/macOS (uses Docker)
# - Prompts for all common options and builds a `docker run` command for review

print_header() {
  echo "----------------------------------------"
  echo "Prisma Cloud Defender - Interactive Installer"
  echo "----------------------------------------"
}

confirm() {
  # yes/no prompt. returns 0 for yes
  local prompt="$1"
  local default=${2:-}
  local resp
  if [ -n "$default" ]; then
    read -rp "$prompt [$default]: " resp
    resp=${resp:-$default}
  else
    read -rp "$prompt [y/N]: " resp
  fi
  case "${resp,,}" in
    y|yes) return 0;;
    *) return 1;;
  esac
}

check_prereqs() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker is not installed or not in PATH. Install Docker or enable Docker Desktop and re-run."
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "Warning: Docker appears not to be running or your user lacks permission. You may need to run this script with sudo or start Docker."
  fi
}

main() {
  print_header
  check_prereqs

  echo "This script can either build a docker run command or generate Kubernetes/OpenShift manifests for a single-container Defender."
  echo
  PS="docker"
  if confirm "Generate Kubernetes/OpenShift manifests instead of a docker run command?" "n"; then
    # choose target platform
    echo "Select target platform:"
    select opt in kubernetes openshift; do
      case $opt in
        kubernetes) PS="kubernetes"; break;;
        openshift) PS="openshift"; break;;
      esac
    done
  fi

  read -rp "Defender container image URI (example: registry.prismacloud.io/defender:latest) : " IMAGE
  IMAGE=${IMAGE:-}
  if [ -z "$IMAGE" ]; then
    echo "You must provide the container image URI. Exiting."
    exit 1
  fi

  read -rp "Defender deployment name [tw-defender]: " NAME
  NAME=${NAME:-tw-defender}

  read -rp "Prisma access token / Defender registration token (or leave empty to set later): " TOKEN

  # common options
  read -rp "Namespace to use (k8s) [prismacloud]: " NAMESPACE
  NAMESPACE=${NAMESPACE:-prismacloud}

  if [ "$PS" = "docker" ]; then
    # docker flow preserved from before (kept simple)
    if confirm "Do you need to login to a private registry?" "n"; then
      read -rp "Registry username: " REG_USER
      read -rsp "Registry password: " REG_PASS
      echo
      echo "Logging in to registry..."
      echo "$REG_PASS" | docker login --username "$REG_USER" --password-stdin || { echo "Registry login failed"; exit 1; }
    fi

    if confirm "Run container with --privileged (required for some runtime protections)?" "y"; then
      PRIVILEGED='--privileged'
    else
      PRIVILEGED=''
    fi

    if confirm "Use host networking (--network host)?" "y"; then
      NET_OPTS='--network host'
    else
      NET_OPTS=''
    fi

    # volumes (allow multiple)
    VOLUMES=()
    while confirm "Add a bind mount (host path -> container path)?" "n"; do
      read -rp "Host path: " HP
      read -rp "Container path: " CP
      VOLUMES+=("-v" "${HP}:${CP}")
    done

    ENVS=()
    if [ -n "$TOKEN" ]; then
      ENVS+=("-e" "DEFENDER_TOKEN=${TOKEN}")
    else
      if confirm "Set DEFENDER_TOKEN environment variable now?" "n"; then
        read -rp "DEFENDER_TOKEN: " T
        ENVS+=("-e" "DEFENDER_TOKEN=${T}")
      fi
    fi

    while confirm "Add another environment variable (KEY=VALUE)?" "n"; do
      read -rp "Env (KEY=VALUE): " KV
      ENVS+=("-e" "$KV")
    done

    read -rp "Restart policy (default: unless-stopped): " RESTART
    RESTART=${RESTART:-unless-stopped}

    DOCKER_CMD=(docker run -d --name "$NAME" --restart "$RESTART")
    if [ -n "$PRIVILEGED" ]; then DOCKER_CMD+=("$PRIVILEGED"); fi
    if [ -n "$NET_OPTS" ]; then DOCKER_CMD+=("$NET_OPTS"); fi
    for v in "${VOLUMES[@]}"; do DOCKER_CMD+=("$v"); done
    for e in "${ENVS[@]}"; do DOCKER_CMD+=("$e"); done
    DOCKER_CMD+=("$IMAGE")

    echo
    echo "--- Generated docker run command ---"
    printf '%q ' "${DOCKER_CMD[@]}"
    echo

    if confirm "Execute the above command now?" "y"; then
      if ! "${DOCKER_CMD[@]}"; then
        echo "docker run failed. Inspect Docker logs and the command above."
        exit 1
      fi
      echo "Container started."
    else
      echo "Skipping execution. You can run the printed command manually."
    fi

    # systemd support
    if [ -d /run/systemd/system ] && confirm "Create a small systemd service to ensure the container starts on boot?" "y"; then
      SERVICE_FILE="/etc/systemd/system/${NAME}.service"
      echo "Writing systemd unit to ${SERVICE_FILE}"
      sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=Prisma Cloud Defender container (${NAME})
After=docker.service
Requires=docker.service

[Service]
Restart=always
ExecStart=/usr/bin/docker start -a ${NAME}
ExecStop=/usr/bin/docker stop -t 30 ${NAME}

[Install]
WantedBy=multi-user.target
EOF
      echo "Reloading systemd and enabling service..."
      sudo systemctl daemon-reload
      sudo systemctl enable --now "${NAME}.service"
      echo "Service enabled. Use 'sudo systemctl status ${NAME}.service' to check."
    fi

    echo "Done. If Defender requires additional registration steps, complete them in the Prisma Cloud UI."
    return 0
  fi

  # Kubernetes / OpenShift manifest generation
  echo "Generating manifests for: $PS"
  OUTDIR="manifests/${PS}-${NAME}"
  mkdir -p "$OUTDIR"

  SA_NAME="${NAME}-sa"
  CR_NAME="${NAME}-clusterrole"
  DS_NAME="${NAME}-daemonset"

  # Namespace
  cat >"${OUTDIR}/00-namespace.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
EOF

  # ServiceAccount
  cat >"${OUTDIR}/01-serviceaccount.yaml" <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SA_NAME}
  namespace: ${NAMESPACE}
EOF

  # ClusterRole (minimal permissions placeholder - adjust as needed)
  cat >"${OUTDIR}/02-clusterrole.yaml" <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${CR_NAME}
rules:
  - apiGroups: [""]
    resources: ["pods","nodes","namespaces","secrets"]
    verbs: ["get","list","watch"]
  - apiGroups: ["" ]
    resources: ["nodes/proxy"]
    verbs: ["get"]
EOF

  # ClusterRoleBinding
  cat >"${OUTDIR}/03-clusterrolebinding.yaml" <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ${NAME}-binding
subjects:
  - kind: ServiceAccount
    name: ${SA_NAME}
    namespace: ${NAMESPACE}
roleRef:
  kind: ClusterRole
  name: ${CR_NAME}
  apiGroup: rbac.authorization.k8s.io
EOF

  # DaemonSet
  cat >"${OUTDIR}/04-daemonset.yaml" <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ${DS_NAME}
  namespace: ${NAMESPACE}
spec:
  selector:
    matchLabels:
      app: ${NAME}
  template:
    metadata:
      labels:
        app: ${NAME}
    spec:
      serviceAccountName: ${SA_NAME}
      hostPID: true
      hostNetwork: true
      tolerations:
        - operator: "Exists"
      containers:
        - name: ${NAME}
          image: ${IMAGE}
          imagePullPolicy: IfNotPresent
          securityContext:
            privileged: true
          env:
            - name: DEFENDER_TOKEN
              value: "${TOKEN}"
          volumeMounts:
            - name: dockersock
              mountPath: /var/run/docker.sock
      volumes:
        - name: dockersock
          hostPath:
            path: /var/run/docker.sock
            type: Socket
EOF

  if [ "$PS" = "openshift" ]; then
    cat >"${OUTDIR}/05-openshift-notes.txt" <<EOF
OpenShift notes:
- You may need to add the service account to the 'privileged' SCC:
  oc adm policy add-scc-to-user privileged -z ${SA_NAME} -n ${NAMESPACE}
- If running on OpenShift 4.x, ensure the cluster-wide policies allow the daemonset to use host networking and privileged containers.
EOF
  fi

  echo "Manifests generated in: ${OUTDIR}"
  echo "Apply them with: kubectl apply -f ${OUTDIR} (or 'oc apply -f' for OpenShift)"
  echo "Review RBAC and privileged settings before applying in production."
}

main "$@"
