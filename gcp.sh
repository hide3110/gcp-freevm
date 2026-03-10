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

# 功能4：更换 Debian 12 镜像源
func_change_apt_source() {
    echo -e "\n>>> 准备更换 Debian 12 镜像源..."
    get_instance_vars
    
    echo "-> 正在通过 gcloud 连接并下发更新源命令..."
    echo "-> 更新过程可能需要几十秒，请耐心等待..."
    
    gcloud compute ssh $NAME \
        --project=$PROJECT \
        --zone=$ZONE \
        --command="sudo bash -c 'cat > /etc/apt/sources.list.d/debian.sources <<EOF && rm -rf /var/lib/apt/lists/* && apt update
Types: deb deb-src
URIs: http://mirrors.mit.edu/debian
Suites: bookworm bookworm-updates bookworm-backports
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb deb-src
URIs: http://mirrors.ocf.berkeley.edu/debian-security
Suites: bookworm-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF'"

    if [ $? -eq 0 ]; then
        echo -e "\033[92m>>> Debian 12 镜像源已成功更换为 MIT/Berkeley 节点并刷新！\033[0m"
    else
        echo -e "\033[93m>>> 镜像源更换出现错误，请检查实例状态或网络连接。\033[0m"
    fi
    echo -e "\n"
}

# 功能5：一键配置 SSH
func_setup_ssh() {
    echo -e "\n>>> 准备配置 SSH 环境..."
    get_instance_vars
    
    echo "===================================="
    while true; do
        read -s -p "请设置新的 Root 密码 (输入时不可见): " ROOT_PASS
        echo
        read -s -p "请再次输入密码以确认: " ROOT_PASS_CONFIRM
        echo
        if [ "$ROOT_PASS" = "$ROOT_PASS_CONFIRM" ]; then
            if [ -z "$ROOT_PASS" ]; then
                echo -e "\033[93m[错误] 密码不能为空，请重试！\033[0m"
            else
                break
            fi
        else
            echo -e "\033[93m[错误] 两次输入的密码不一致，请重试！\033[0m"
        fi
    done
    echo "------------------------------------"
    echo "-> 正在通过 gcloud 连接并下发配置命令..."
    
    gcloud compute instances describe $NAME --project=$PROJECT --zone=$ZONE --format="value(status)" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "\033[93m[错误] 实例 $NAME 不存在或未运行，请先创建实例！\033[0m"
        return
    fi
    
    gcloud compute ssh $NAME \
        --project=$PROJECT \
        --zone=$ZONE \
        --command="sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config && sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/g' /etc/ssh/sshd_config && sudo sed -i 's/^#\?Port.*/Port 56013/g' /etc/ssh/sshd_config && echo \"root:${ROOT_PASS}\" | sudo chpasswd && sudo systemctl restart ssh"
    
    if [ $? -eq 0 ]; then
        echo -e "\033[92m>>> SSH 配置成功！\033[0m"
        echo -e ">>> 现在你可以使用第三方工具(如 Termius)连接了:"
        echo -e "    - 用户名: \033[96mroot\033[0m"
        echo -e "    - 密  码: \033[96m(你刚才设置的密码)\033[0m"
        echo -e "    - 端  口: \033[96m56013\033[0m"
    else
        echo -e "\033[93m>>> SSH 配置过程中可能出现错误，请检查网络连接。\033[0m"
    fi
    echo -e "\n"
}

# 功能6：全局查看当前项目下所有实例信息
func_view_vm() {
    echo -e "\n>>> 准备扫描当前项目下的所有实例信息..."
    auto_get_project
    echo "------------------------------------"
    echo "-> 正在向 GCP 请求全局数据，请稍候..."
    echo -e "\n\033[92m【 实例详细信息列表 】\033[0m"
    
    # 核心修改点：将 table 格式化字符串压缩为单行，并去除中文后的括号以防止解析错误
    gcloud compute instances list \
        --project=$PROJECT \
        --format="table(name:label=实例名称,zone.basename():label=可用区,networkInterfaces[0].accessConfigs[0].natIP:label=公网IP,disks[0].diskSizeGb:label=磁盘GB,disks[0].licenses[0].basename():label=系统,status:label=状态)"
        
    echo -e "==========================================================\n"
}

# 主菜单循环
while true; do
    echo "===================================="
    echo "        GCP 实例快捷管理脚本        "
    echo "===================================="
    echo "  1. 创建免费机"
    echo "  2. 设置防火墙规则 (入站/出站全开)"
    echo "  3. 删除实例"
    echo "  4. 更换系统镜像源 (Debian 12 专用)"
    echo "  5. 一键配置 SSH (Root密码登录/改端口56013, 建议最后执行)"
    echo "  6. 查看账号下所有实例信息"
    echo "  0. 退出脚本"
    echo "===================================="
    read -p "请输入对应的数字 [0-6]: " choice

    case $choice in
        1) func_create_vm ;;
        2) func_setup_firewall ;;
        3) func_delete_vm ;;
        4) func_change_apt_source ;;
        5) func_setup_ssh ;;
        6) func_view_vm ;;
        0) echo "已退出。"; exit 0 ;;
        *) echo -e "\n[错误] 无效的选项，请重新输入！\n" ;;
    esac
done
