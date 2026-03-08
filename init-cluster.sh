#!/bin/bash
# Script tự động tạo cụm K3s cho TMCP

VM_NAME="tmcp-server"

echo "1. Đang tạo máy ảo Multipass (2 Core, 4GB RAM, 20GB Disk)..."
multipass launch -n $VM_NAME -c 2 -m 4G -d 20G 24.04

echo "2. Đang cài đặt K3s lên máy ảo..."
multipass exec $VM_NAME -- bash -c "curl -sfL https://get.k3s.io | sh -"

echo "3. Lấy IP của máy ảo..."
VM_IP=$(multipass info $VM_NAME | grep IPv4 | awk '{print $2}')
echo "IP của máy ảo là: $VM_IP"

echo "4. Kéo file Kubeconfig về Mac và đổi IP..."
multipass exec $VM_NAME -- sudo cat /etc/rancher/k3s/k3s.yaml > ~/.kube/tmcp_config
sed -i '' "s/127.0.0.1/$VM_IP/g" ~/.kube/tmcp_config

echo "5. Cấu hình biến môi trường trên Mac..."
export KUBECONFIG=~/.kube/tmcp_config
echo "Cụm K3s đã sẵn sàng! Chạy lệnh: export KUBECONFIG=~/.kube/tmcp_config"
