#!/bin/bash

# 获取实例相关变量的函数
get_instance_vars() {
    echo "--------------------------------"
    read -p "请输入项目 ID (PROJECT): " PROJECT
    read -p "请输入可用区 (ZONE, 例如 us-west1-b): " ZONE
    read -p "请输入实例名称 (NAME, 例如 free-tier-vm): " NAME
    echo "--------------------------------"
}

# 功能1：创建免费机
func_create_vm() {
    echo -e "\n>>> 准备创建免费机..."
    get_instance_vars
    # 根据提供的脚本要求执行创建命令 
    gcloud compute instances create $NAME \
        --project=$PROJECT \
        --zone=$ZONE \
        --machine-type=e2-micro \
        --network-interface=network-tier=STANDARD \
        --boot-disk-size=30GB \
        --boot-disk-type=pd-standard \
        --image-project=debian-cloud \
        --image-family=debian-12
    echo -e ">>> 实例 $NAME 创建流程结束！\n"
}

# 功能2：设置防火墙规则
func_setup_firewall() {
    echo -e "\n>>> 准备设置防火墙规则..."
    
    # 创建允许全站端口入站 (INGRESS) 规则 
    echo "-> 正在创建入站规则 (v4in)..."
    gcloud compute firewall-rules create v4in \
        --direction=INGRESS \
        --priority=1000 \
        --network=default \
        --action=ALLOW \
        --rules=all \
        --source-ranges=0.0.0.0/0

    # 创建允许全站端口出站 (EGRESS) 规则 
    echo "-> 正在创建出站规则 (v4out)..."
    gcloud compute firewall-rules create v4out \
        --direction=EGRESS \
        --priority=1000 \
        --network=default \
        --action=ALLOW \
        --rules=all \
        --destination-ranges=0.0.0.0/0 [cite: 2]
        
    echo -e ">>> 防火墙规则设置完成！\n"
}

# 功能3：删除实例
func_delete_vm() {
    echo -e "\n>>> 准备删除实例..."
    get_instance_vars
    # 根据提供的脚本要求执行删除命令 [cite: 2]
    gcloud compute instances delete $NAME \
        --project=$PROJECT \
        --zone=$ZONE \
        --quiet
    echo -e ">>> 实例 $NAME 已发起删除请求！\n"
}

# 主菜单循环
while true; do
    echo "===================================="
    echo "        GCP 实例快捷管理脚本        "
    echo "===================================="
    echo "  1. 创建免费机"
    echo "  2. 设置防火墙规则 (全开)"
    echo "  3. 删除实例"
    echo "  0. 退出脚本"
    echo "===================================="
    read -p "请输入对应的数字 [0-3]: " choice

    case $choice in
        1) func_create_vm ;;
        2) func_setup_firewall ;;
        3) func_delete_vm ;;
        0) echo "已退出。"; exit 0 ;;
        *) echo -e "\n[错误] 无效的选项，请重新输入！\n" ;;
    esac
done
