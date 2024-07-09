#!/usr/bin/bash

DRIVER=$(kubectl get sc -o=jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io\/is-default-class=="true")].provisioner}')
VERSION=$(kubectl -n ntnx-system get deployment nutanix-csi-controller -o jsonpath='{.spec.template.spec.containers[?(@.name=="nutanix-csi-plugin")].image}' | cut -f 2 -d 'v')
SNAP=$(kubectl -n ntnx-system get deployment csi-snapshot-controller -o jsonpath='{.metadata.name}' 2> /dev/null)

echo "You are using CSI driver v$VERSION with driver name $DRIVER\n"

if [[ $SNAP = "csi-snapshot-controller" ]]
then
    echo "Your Karbon cluster already support Snapshot Capability"
    exit
fi

if [[ $DRIVER = "csi.nutanix.com" && ( $VERSION = "2.3.1" || $VERSION = "2.2.0" ) ]]
then
    kubectl apply -f https://github.com/nutanix/csi-plugin/releases/download/v$VERSION/snapshot-crd-$VERSION.yaml
    kubectl apply -f https://github.com/nutanix/csi-plugin/releases/download/v$VERSION/karbon-fix-snapshot-$VERSION.yaml
elif [[ $DRIVER = "com.nutanix.csi" && ( $VERSION = "2.3.1" || $VERSION = "2.2.0" ) ]]
then
    kubectl apply -f https://github.com/nutanix/csi-plugin/releases/download/v$VERSION/snapshot-crd-$VERSION.yaml
    kubectl apply -f https://github.com/nutanix/csi-plugin/releases/download/v$VERSION/karbon-fix-snapshot-$VERSION-rev.yaml
else
    echo "**************************************************************************"
    echo "* Untested configuration. Upgrade your Karbon cluster or contact support *"
    echo "**************************************************************************\n"
fi