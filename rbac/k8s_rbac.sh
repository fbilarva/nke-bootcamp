#!/bin/bash
#
# ------------------------------------------------------------------------------------------------------------------------
#
# Developers and contributors: Fabiano Verni <fabiano.verni@nutanix.com> and Franklin de Jesus Ribeiro <fjribeiro.ps@anp.gov.br>
# Change History: 2.0 - 1 Jan 2024, 1.0 -  1 Oct 2023          
# Summary: k8s_rbac.sh is a simple script to generate kubeconfig and ca.crt by namespace, service account, and rbac roles associated between them.
# Disclaimer: Roles can be adjusted according to the company's needs.
# Compatible software version(s): ALL Linux version with jq package installed.
# Brief syntax usage: bash k8s_rbac.sh <service_account_name> <namespace>
#
# ------------------------------------------------------------------------------------------------------------------------
#

set -e
set -o pipefail

# Add user to k8s using service account, no RBAC (must create RBAC after this script)
if [[ -z "$1" ]] || [[ -z "$2" ]]; then
 echo "Attention!!! The Kubeconfig and Cert files will be create kuberepo directory"
 echo "usage: $0 <service_account_name> <namespace>"
 exit 1
fi

SERVICE_ACCOUNT_NAME=$1
NAMESPACE="$2"
KUBECFG_FILE_NAME="kuberepo/${SERVICE_ACCOUNT_NAME}config"
CERTCFG_FILE_NAME="kuberepo/${SERVICE_ACCOUNT_NAME}.crt"
TARGET_FOLDER="kuberepo"


create_target_folder() {
    echo -n "Creating target directory to hold files in ${TARGET_FOLDER}..."
    mkdir -p "${TARGET_FOLDER}"
    printf "done"
}

create_namespace() {
    echo -e "\\nCreating a namespace in ${NAMESPACE} namespace: ${NAMESPACE}"
    kubectl create namespace "${NAMESPACE}"
    echo "Created Namespace: ${NAMESPACE}"
}


create_service_account() {
    echo -e "\\nCreating a service account in ${NAMESPACE} namespace: ${SERVICE_ACCOUNT_NAME}"
    kubectl create serviceaccount "${SERVICE_ACCOUNT_NAME}" --namespace "${NAMESPACE}"

## Added Role creation. In resources and verbs, they can be changed to suit.
    cat <<EOF | kubectl create -f -
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  namespace: ${NAMESPACE}
  name: ${SERVICE_ACCOUNT_NAME}
rules:
- apiGroups: [""]
  resources: ["pods", "pods/exec", "pods/log"]
  verbs: ["get", "list", "create", "delete", "exec", "logs", "watch"]
EOF

## Added the creation of RoleBinding. What made it work was the addition of the kind: ServiceAccount field
    cat <<EOF | kubectl create -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: ${NAMESPACE}
  name: ${SERVICE_ACCOUNT_NAME}
subjects:
- kind: User
  name: ${SERVICE_ACCOUNT_NAME}
  apiGroup: rbac.authorization.k8s.io
- kind: ServiceAccount
  name: ${SERVICE_ACCOUNT_NAME}
roleRef:
  kind: Role
  name: ${SERVICE_ACCOUNT_NAME}
  apiGroup: rbac.authorization.k8s.io
EOF
   cat <<EOF | kubectl create -f -
apiVersion: v1
kind: Secret
type: kubernetes.io/service-account-token
metadata:
 name: ${SERVICE_ACCOUNT_NAME}
 namespace: ${NAMESPACE}
 annotations:
   kubernetes.io/service-account.name: ${SERVICE_ACCOUNT_NAME}
EOF
}

get_secret_name_from_service_account() {
    echo -e "\\nGetting secret of service account ${SERVICE_ACCOUNT_NAME} on ${NAMESPACE}"
    SECRET_NAME=$(kubectl get sa "${SERVICE_ACCOUNT_NAME}" --namespace="${NAMESPACE}" -o json | jq -r .metadata.name)
    echo "Secret name: ${SECRET_NAME}" 
}

extract_ca_crt_from_secret() {
    echo -e -n "\\nExtracting ca.crt from secret..."
    kubectl get secret --namespace "${NAMESPACE}" "${SECRET_NAME}" -o json | jq -r '.data["ca.crt"]' | base64 -d > "${CERTCFG_FILE_NAME}"
    printf "done"
}

get_user_token_from_secret() {
    echo -e -n "\\nGetting user token from secret..."
    USER_TOKEN=$(kubectl get secret --namespace "${NAMESPACE}" "${SECRET_NAME}" -o json | jq -r '.data["token"]' | base64 -d)
    printf "done"
}

set_kube_config_values() {
    context=$(kubectl config current-context)
    echo -e "\\nSetting current context to: $context"

    CLUSTER_NAME=$(kubectl config get-contexts "$context" | awk '{print $3}' | tail -n 1)
    echo "Cluster name: ${CLUSTER_NAME}"

    ENDPOINT=$(kubectl config view \
    -o jsonpath="{.clusters[?(@.name == \"${CLUSTER_NAME}\")].cluster.server}")
    echo "Endpoint: ${ENDPOINT}"

    # Set up the config
    echo -e "\\nPreparing ${KUBECFG_FILE_NAME}"
    echo -n "Setting a cluster entry in kubeconfig..."
    kubectl config set-cluster "${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}" \
    --server="${ENDPOINT}" \
    --certificate-authority="${CERTCFG_FILE_NAME}" \
    --embed-certs=true

    echo -n "Setting token credentials entry in kubeconfig..."
    kubectl config set-credentials \
    "${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}" \
    --token="${USER_TOKEN}"

    echo -n "Setting a context entry in kubeconfig..."
    kubectl config set-context \
    "${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}" \
    --cluster="${CLUSTER_NAME}" \
    --user="${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --namespace="${NAMESPACE}"

    echo -n "Setting the current-context in the kubeconfig file..."
    kubectl config use-context "${SERVICE_ACCOUNT_NAME}-${NAMESPACE}-${CLUSTER_NAME}" \
    --kubeconfig="${KUBECFG_FILE_NAME}"
}

create_target_folder
create_namespace
create_service_account
get_secret_name_from_service_account
extract_ca_crt_from_secret
get_user_token_from_secret
set_kube_config_values

echo -e "\\nAll done! Test with:"
echo "KUBECONFIG=${KUBECFG_FILE_NAME} kubectl get pods"
echo "you should not have any permissions by default - you have just created the authentication part"
echo "You will need to create RBAC permissions"
echo "Attention!!! The Kubeconfig and Cert files are in create kuberepo directory"
ls -la ${TARGET_FOLDER}/${NAMESPACE}*
kubectl get role -n ${NAMESPACE} ${SERVICE_ACCOUNT_NAME} -o yaml
