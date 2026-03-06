#!/bin/bash

# 自动获取项目 ID 的函数
auto_get_project() {
    # 从 gcloud 配置中提取当前项目 ID，丢弃报错信息
    PROJECT=$(gcloud config get-value project 2>/dev/null)
    
    if [ -z "$PROJECT" ]; then
        echo -e "\033[93m[警告] 无法自动识别项目 ID，请确认环境状态！\033[0m"
        read -p "请输入项目 ID (PROJECT): " PROJECT
    else
        echo -e "\033[92m>>> 已自动锁定当前项目 ID: $PROJECT\033[0m"
    fi
}

# 获取实例相关变量的函数
get_instance_vars() {
    echo "===================================="
    # 调用自动获取项目函数
    auto_get_project
    
    echo "------------------------------------"
    echo "【可用区域参考】(GCP 免费层级推荐):"
    echo "  - Oregon (俄勒冈)      : us-west1-a, us-west1-b, us-west1-c"
    echo "  - Iowa (爱荷华)        : us-central1-a, us-central1-b, us-central1-c, us-central1-f"
    echo "  - South Carolina (南卡): us-east1-b, us-east1-c, us-east1-d"
    echo "------------------------------------"
    
    # 增加提示并设置默认值
    read -p "请输入可用区 (ZONE) [直接回车默认: us-west1-b]: " ZONE
    ZONE=${ZONE:-us-west1-b}
    
    read -p "请输入实例名称 (NAME) [直接回车默认: us-free]: " NAME
    NAME=${NAME:-us-free}
    
    # 打印最终使用的参数，方便确认
    echo "------------------------------------"
    echo ">>> 将使用以下配置进行操作："
    echo ">>> 项目: $PROJECT"
    echo ">>> 区域: $ZONE"
    echo ">>> 实例: $NAME"
    echo "------------------------------------"
}

# 功能1：创建免费机
func_create_vm() {
    echo -e "\n>>> 准备创建免费机..."
    get_instance_vars
    
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
    echo "===================================="
    auto_get_project
    echo "------------------------------------"
    
    # 创建允许全站端口入站 (INGRESS) 规则
    echo "-> 正在创建入站规则 (v4in)..."
    gcloud compute firewall-rules create v4in \
        --project=$PROJECT \
        --direction=INGRESS \
        --priority=1000 \
        --network=default \
        --action=ALLOW \
        --rules=all \
        --source-ranges=0.0.0.0/0

    # 创建允许全站端口出站 (EGRESS) 规则
    echo "-> 正在创建出站规则 (v4out)..."
    gcloud compute firewall-rules create v4out \
        --project=$PROJECT \
        --direction=EGRESS \
        --priority=1000 \
        --network=default \
        --action=ALLOW \
        --rules=all \
        --destination-ranges=0.0.0.0/0
        
    echo -e ">>> 防火墙规则设置完成！\n"
}

# 功能3：删除实例
func_delete_vm() {
    echo -e "\n>>> 准备删除实例..."
    get_instance_vars
    
    gcloud compute instances delete $NAME \
        --project=$PROJECT \
        --zone=$ZONE \
        --quiet
        
    echo -e ">>> 实例 $NAME 已彻底删除！\n"
}

# 主菜单循环
while true; do
    echo "===================================="
    echo "        GCP 实例快捷管理脚本        "
    echo "===================================="
    echo "  1. 创建免费机"
    echo "  2. 设置防火墙规则 (入站/出站全开)"
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
