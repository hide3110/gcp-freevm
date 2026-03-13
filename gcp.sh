#!/bin/bash

# ====================================
# GCP 免费机快捷管理脚本(基于 gcp-free.sh 精简修改版)
# ====================================

set -u

# ---------- 默认变量 ----------
DEFAULT_VPC_NAME="default"
DEFAULT_VM_NAME="hide217"
DEFAULT_MACHINE_TYPE="e2-micro"
DEFAULT_DISK_SIZE="30GB"
DEFAULT_IMAGE_PROJECT="debian-cloud"
DEFAULT_IMAGE_FAMILY="debian-12"
DEFAULT_SSH_PORT="56013"
DEFAULT_FREE_ZONE="us-west1-b"

PROJECT=""
VPC_NAME="$DEFAULT_VPC_NAME"
ZONE=""
NAME=""

FW_RULE_V4IN=""
FW_RULE_V4OUT=""

# 同一个项目只检查一次 API
API_READY_PROJECT=""

# ---------- 颜色 ----------
GREEN="\033[92m"
YELLOW="\033[93m"
RED="\033[91m"
CYAN="\033[96m"
RESET="\033[0m"

# ---------- 免费层区域/可用区 ----------
FREE_REGION_NAMES=(
    "Oregon"
    "Iowa"
    "South Carolina"
)

FREE_REGION_ZONES_1=("us-west1-a" "us-west1-b" "us-west1-c")
FREE_REGION_ZONES_2=("us-central1-a" "us-central1-b" "us-central1-c" "us-central1-f")
FREE_REGION_ZONES_3=("us-east1-b" "us-east1-c" "us-east1-d")

# ---------- 基础检查 ----------
check_gcloud() {
    if ! command -v gcloud >/dev/null 2>&1; then
        echo -e "${RED}[错误] 未检测到 gcloud,请先安装并登录 Google Cloud SDK。${RESET}"
        exit 1
    fi
}

# ---------- 自动获取当前项目 ----------
auto_get_project() {
    PROJECT=$(gcloud config get-value project 2>/dev/null | tr -d '\r')
    if [ -z "$PROJECT" ] || [ "$PROJECT" = "(unset)" ]; then
        return 1
    fi
    return 0
}

# ---------- 显示当前项目 ----------
show_current_project() {
    if auto_get_project; then
        echo -e "当前默认项目: ${CYAN}${PROJECT}${RESET}"
    else
        echo -e "当前默认项目: ${YELLOW}(未设置)${RESET}"
    fi
}

# ---------- 自动启用 API（同一项目只检查一次） ----------
ensure_required_apis() {
    if ! auto_get_project; then
        echo -e "${YELLOW}[提示] 当前未设置默认项目,无法启用 API。${RESET}"
        return 1
    fi

    if [ "${API_READY_PROJECT:-}" = "$PROJECT" ]; then
        return 0
    fi

    local apis=("compute.googleapis.com")
    local api enabled

    echo "------------------------------------"
    echo ">>> 检查并自动启用所需 API ..."
    for api in "${apis[@]}"; do
        enabled=$(gcloud services list --enabled --project="$PROJECT" \
            --filter="config.name:${api}" \
            --format="value(config.name)" 2>/dev/null)

        if [ "$enabled" = "$api" ]; then
            echo -e "${GREEN}已启用: $api${RESET}"
        else
            echo -e "${YELLOW}正在启用: $api${RESET}"
            gcloud services enable "$api" --project="$PROJECT"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}启用成功: $api${RESET}"
            else
                echo -e "${RED}[错误] 启用失败: $api${RESET}"
                return 1
            fi
        fi
    done
    echo "------------------------------------"

    API_READY_PROJECT="$PROJECT"
    return 0
}

# ---------- 创建项目 ----------
create_project_interactive() {
    echo -e "\n>>> 准备创建新项目..."
    read -p "请输入新的项目 ID(全局唯一): " new_project_id
    if [ -z "$new_project_id" ]; then
        echo -e "${YELLOW}[错误] 项目 ID 不能为空。${RESET}"
        return 1
    fi

    read -p "请输入项目名称(可留空默认同项目ID): " new_project_name
    new_project_name=${new_project_name:-$new_project_id}

    gcloud projects create "$new_project_id" --name="$new_project_name"
    if [ $? -ne 0 ]; then
        echo -e "${RED}[错误] 项目创建失败。${RESET}"
        return 1
    fi

    PROJECT="$new_project_id"
    echo -e "${GREEN}>>> 项目创建成功: $PROJECT${RESET}"

    read -p "是否将其设置为默认项目?(Y/n): " set_choice
    if [[ -z "$set_choice" || "$set_choice" == "y" || "$set_choice" == "Y" ]]; then
        gcloud config set project "$PROJECT" >/dev/null
        if [ $? -eq 0 ]; then
            API_READY_PROJECT=""
            echo -e "${GREEN}>>> 默认项目已设置为: $PROJECT${RESET}"
            ensure_required_apis
        fi
    fi
    echo
    return 0
}

# ---------- 选择项目 ----------
select_project() {
    echo -e "\n>>> 正在获取账号下的项目列表..."
    local projects_data
    projects_data=$(gcloud projects list --format="value(projectId,name)" 2>/dev/null)

    if [ -z "$projects_data" ]; then
        echo -e "${YELLOW}[提示] 当前账号下没有查询到项目。${RESET}"
        read -p "是否现在创建新项目?(y/N): " create_choice
        if [[ "$create_choice" == "y" || "$create_choice" == "Y" ]]; then
            create_project_interactive
            return $?
        fi
        return 1
    fi

    local pids=()
    local i=1
    local pid pname

    echo "------------------------------------"
    echo "发现以下项目,请选择:"
    while read -r pid pname; do
        [ -z "$pid" ] && continue
        pids+=("$pid")
        echo -e "  [$i] 项目ID: ${CYAN}$pid${RESET} | 项目名: $pname"
        ((i++))
    done <<< "$projects_data"
    echo "  [c] 创建新项目"
    echo "  [0] 返回主菜单"
    echo "------------------------------------"

    local choice
    while true; do
        read -p "请输入对应编号: " choice
        if [[ "$choice" == "0" ]]; then
            return 1
        elif [[ "$choice" == "c" || "$choice" == "C" ]]; then
            create_project_interactive
            return $?
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
            PROJECT="${pids[$((choice-1))]}"
            echo -e "${GREEN}>>> 已选择项目: $PROJECT${RESET}"
            return 0
        else
            echo -e "${YELLOW}[错误] 输入无效,请重试。${RESET}"
        fi
    done
}

# ---------- 构建防火墙规则名（仅 IPv4） ----------
build_firewall_rule_names() {
    local vpc="$1"
    FW_RULE_V4IN="${vpc}-v4in"
    FW_RULE_V4OUT="${vpc}-v4out"
}

# ---------- 清洗资源名 ----------
sanitize_name() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

# ---------- 结算账号ID格式化 ----------
normalize_billing_account_id() {
    local raw="$1"
    echo "${raw#billingAccounts/}"
}

# ---------- 免费机区域选择 ----------
select_free_zone() {
    echo "------------------------------------"
    echo "【免费层级可选区域】"
    echo "  [1] Oregon"
    echo "      - us-west1-a"
    echo "      - us-west1-b  (默认)"
    echo "      - us-west1-c"
    echo "  [2] Iowa"
    echo "      - us-central1-a"
    echo "      - us-central1-b"
    echo "      - us-central1-c"
    echo "      - us-central1-f"
    echo "  [3] South Carolina"
    echo "      - us-east1-b"
    echo "      - us-east1-c"
    echo "      - us-east1-d"
    echo "------------------------------------"

    local region_choice
    read -p "请选择区域编号 [默认: 1]: " region_choice
    region_choice=${region_choice:-1}

    local zones=()
    case "$region_choice" in
        1) zones=("${FREE_REGION_ZONES_1[@]}") ;;
        2) zones=("${FREE_REGION_ZONES_2[@]}") ;;
        3) zones=("${FREE_REGION_ZONES_3[@]}") ;;
        *)
            echo -e "${YELLOW}[提示] 输入无效,已默认使用 Oregon。${RESET}"
            zones=("${FREE_REGION_ZONES_1[@]}")
            region_choice=1
            ;;
    esac

    echo "------------------------------------"
    echo "可用区列表:"
    local i=1
    local z
    for z in "${zones[@]}"; do
        echo "  [$i] $z"
        ((i++))
    done
    echo "------------------------------------"

    local zone_choice
    local default_zone_index=1

    # Oregon 默认 us-west1-b => 第2项
    if [ "$region_choice" = "1" ]; then
        default_zone_index=2
    fi

    read -p "请选择可用区编号 [默认: ${default_zone_index}]: " zone_choice
    zone_choice=${zone_choice:-$default_zone_index}

    if [[ "$zone_choice" =~ ^[0-9]+$ ]] && [ "$zone_choice" -ge 1 ] && [ "$zone_choice" -le "${#zones[@]}" ]; then
        ZONE="${zones[$((zone_choice-1))]}"
    else
        ZONE="${zones[$((default_zone_index-1))]}"
        echo -e "${YELLOW}[提示] 输入无效,已使用默认可用区: $ZONE${RESET}"
    fi

    echo -e "${GREEN}>>> 已选择可用区: $ZONE${RESET}"
}

# ---------- 选择已有实例 ----------
select_existing_vm() {
    echo -e "\n>>> 正在扫描当前项目下的实例..."
    if ! auto_get_project; then
        echo -e "${YELLOW}[提示] 当前未设置默认项目。${RESET}"
        return 1
    fi

    local instances_data
    instances_data=$(gcloud compute instances list --project="$PROJECT" --format="value(name,zone.basename())" 2>/dev/null)

    if [ -z "$instances_data" ]; then
        echo -e "${YELLOW}[提示] 当前项目下没有找到任何实例。${RESET}"
        return 1
    fi

    local names=()
    local zones=()
    local i=1
    local name zone

    echo "------------------------------------"
    echo "发现以下实例,请选择要操作的机器:"
    while read -r name zone; do
        [ -z "$name" ] && continue
        names+=("$name")
        zones+=("$zone")
        echo -e "  [$i] 实例名: ${CYAN}$name${RESET} (可用区: $zone)"
        ((i++))
    done <<< "$instances_data"

    echo "  [0] 取消操作并返回主菜单"
    echo "------------------------------------"

    local choice
    while true; do
        read -p "请输入对应的数字 [0-$((i-1))]: " choice
        if [[ "$choice" == "0" ]]; then
            echo "操作已取消。"
            return 1
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
            NAME="${names[$((choice-1))]}"
            ZONE="${zones[$((choice-1))]}"
            echo -e "${GREEN}>>> 已锁定目标: $NAME ($ZONE)${RESET}"
            return 0
        else
            echo -e "${YELLOW}[错误] 输入无效,请重新输入数字。${RESET}"
        fi
    done
}

# ---------- 功能1:查看项目 ----------
func_view_projects() {
    echo -e "\n>>> 查看账号下所有项目..."
    gcloud projects list
    echo
}

# ---------- 功能2:设置默认项目 ----------
func_set_default_project() {
    echo -e "\n>>> 设置默认项目..."
    if ! select_project; then return; fi

    gcloud config set project "$PROJECT"
    if [ $? -eq 0 ]; then
        API_READY_PROJECT=""
        echo -e "${GREEN}>>> 默认项目已设置为: $PROJECT${RESET}"
        ensure_required_apis
    else
        echo -e "${RED}[错误] 设置默认项目失败。${RESET}"
    fi
    echo
}

# ---------- 功能3:创建免费机 ----------
func_create_vm() {
    echo -e "\n>>> 准备创建免费机..."
    if ! auto_get_project >/dev/null 2>&1; then
        echo -e "${YELLOW}[提示] 请先设置默认项目。${RESET}"
        if ! select_project; then return; fi
        gcloud config set project "$PROJECT" >/dev/null
        API_READY_PROJECT=""
    fi

    if ! ensure_required_apis; then
        echo -e "${RED}[错误] API 启用失败,无法继续。${RESET}"
        return
    fi

    select_free_zone

    read -p "请输入新实例名称 [默认: ${DEFAULT_VM_NAME}]: " NAME
    NAME=${NAME:-$DEFAULT_VM_NAME}

    echo "------------------------------------"
    echo ">>> 将使用如下配置:"
    echo "  项目:      $PROJECT"
    echo "  可用区:    $ZONE"
    echo "  实例名:    $NAME"
    echo "  机型:      $DEFAULT_MACHINE_TYPE"
    echo "  网络层级:  STANDARD"
    echo "  磁盘大小:  $DEFAULT_DISK_SIZE"
    echo "  磁盘类型:  pd-standard"
    echo "  网络:      default"
    echo "  预配模型:  STANDARD"
    echo "------------------------------------"

    gcloud compute instances create "$NAME" \
        --project="$PROJECT" \
        --zone="$ZONE" \
        --machine-type="$DEFAULT_MACHINE_TYPE" \
        --network-interface=network=default,network-tier=STANDARD \
        --boot-disk-size="$DEFAULT_DISK_SIZE" \
        --boot-disk-type=pd-standard" \
        --image-project="$DEFAULT_IMAGE_PROJECT" \
        --image-family="$DEFAULT_IMAGE_FAMILY"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}>>> 实例 $NAME 创建完成!${RESET}\n"
    else
        echo -e "${RED}[错误] 实例创建失败,请检查配额、区域库存或 API 状态。${RESET}\n"
    fi
}

# ---------- 功能4:查看防火墙规则 ----------
func_view_firewall() {
    echo -e "\n>>> 准备获取当前项目的防火墙规则..."
    if ! auto_get_project; then
        echo -e "${YELLOW}[提示] 请先设置默认项目。${RESET}"
        return
    fi

    if ! ensure_required_apis; then
        return
    fi

    read -p "请输入要查看的 VPC 名称 [默认: ${DEFAULT_VPC_NAME}]: " VPC_NAME
    VPC_NAME=${VPC_NAME:-$DEFAULT_VPC_NAME}
    build_firewall_rule_names "$VPC_NAME"

    echo "------------------------------------"
    echo "-> 正在获取 VPC [$VPC_NAME] 的防火墙规则..."
    echo

    local firewall_data
    firewall_data=$(gcloud compute firewall-rules list \
        --project="$PROJECT" \
        --filter="network~.*/${VPC_NAME}$" \
        --format="table(name:label=规则名,network.basename():label=网络,direction:label=方向,priority:label=优先级,disabled:label=禁用,sourceRanges.list():label=源范围,destinationRanges.list():label=目标范围,allowed[].map().firewall_rule().list():label=允许,denied[].map().firewall_rule().list():label=拒绝)" \
        2>/dev/null)

    if [ -z "$firewall_data" ] || [[ "$firewall_data" != *"规则名"* ]]; then
        echo -e "${YELLOW}[提示] 在 VPC [$VPC_NAME] 下没有查询到防火墙规则。${RESET}"
        echo -e "${YELLOW}[提示] 如需创建,可使用菜单 5 设置以下规则:${RESET}"
        echo -e "        ${CYAN}${FW_RULE_V4IN}${RESET}"
        echo -e "        ${CYAN}${FW_RULE_V4OUT}${RESET}\n"
        return
    fi

    echo -e "${GREEN}【 VPC ${VPC_NAME} 的防火墙规则列表 】${RESET}"
    echo "$firewall_data"
    echo -e "==========================================================\n"
}

# ---------- 功能5:设置防火墙规则（仅 IPv4） ----------
func_setup_firewall() {
    echo -e "\n>>> 准备设置防火墙规则..."
    if ! auto_get_project; then
        echo -e "${YELLOW}[提示] 请先设置默认项目。${RESET}"
        return
    fi

    if ! ensure_required_apis; then
        return
    fi

    read -p "请输入目标 VPC 名称 [默认: ${DEFAULT_VPC_NAME}]: " VPC_NAME
    VPC_NAME=${VPC_NAME:-$DEFAULT_VPC_NAME}
    build_firewall_rule_names "$VPC_NAME"

    echo "------------------------------------"
    echo "-> 检查目标 VPC 是否存在..."
    if ! gcloud compute networks describe "$VPC_NAME" --project="$PROJECT" >/dev/null 2>&1; then
        echo -e "${RED}[错误] VPC [$VPC_NAME] 不存在。${RESET}"
        return
    fi

    echo "-> 正在创建 IPv4 入站规则 (${FW_RULE_V4IN})..."
    if gcloud compute firewall-rules describe "$FW_RULE_V4IN" --project="$PROJECT" >/dev/null 2>&1; then
        echo -e "${YELLOW}[提示] 规则 ${FW_RULE_V4IN} 已存在,跳过。${RESET}"
    else
        gcloud compute firewall-rules create "$FW_RULE_V4IN" \
            --project="$PROJECT" \
            --direction=INGRESS \
            --priority=1000 \
            --network="$VPC_NAME" \
            --action=ALLOW \
            --rules=all \
            --source-ranges=0.0.0.0/0
        [ $? -eq 0 ] && echo -e "${GREEN}>>> ${FW_RULE_V4IN} 创建成功${RESET}" || echo -e "${RED}[错误] ${FW_RULE_V4IN} 创建失败${RESET}"
    fi

    echo "-> 正在创建 IPv4 出站规则 (${FW_RULE_V4OUT})..."
    if gcloud compute firewall-rules describe "$FW_RULE_V4OUT" --project="$PROJECT" >/dev/null 2>&1; then
        echo -e "${YELLOW}[提示] 规则 ${FW_RULE_V4OUT} 已存在,跳过。${RESET}"
    else
        gcloud compute firewall-rules create "$FW_RULE_V4OUT" \
            --project="$PROJECT" \
            --direction=EGRESS \
            --priority=1000 \
            --network="$VPC_NAME" \
            --action=ALLOW \
            --rules=all \
            --destination-ranges=0.0.0.0/0
        [ $? -eq 0 ] && echo -e "${GREEN}>>> ${FW_RULE_V4OUT} 创建成功${RESET}" || echo -e "${RED}[错误] ${FW_RULE_V4OUT} 创建失败${RESET}"
    fi

    echo -e "${GREEN}>>> 防火墙规则设置完成!${RESET}\n"
}

# ---------- 功能6:动/静态 IPv4 切换 ----------
func_toggle_ip_mode() {
    echo -e "\n>>> 准备进行 IPv4 动/静态切换..."
    if ! auto_get_project; then
        echo -e "${YELLOW}[提示] 请先设置默认项目。${RESET}"
        return
    fi

    if ! ensure_required_apis; then
        return
    fi

    if ! select_existing_vm; then
        return
    fi

    local nic_name access_config_name current_ip network_tier region static_addr_name
    nic_name=$(gcloud compute instances describe "$NAME" \
        --project="$PROJECT" \
        --zone="$ZONE" \
        --format="value(networkInterfaces[0].name)" 2>/dev/null)

    access_config_name=$(gcloud compute instances describe "$NAME" \
        --project="$PROJECT" \
        --zone="$ZONE" \
        --format="value(networkInterfaces[0].accessConfigs[0].name)" 2>/dev/null)

    current_ip=$(gcloud compute instances describe "$NAME" \
        --project="$PROJECT" \
        --zone="$ZONE" \
        --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)

    network_tier=$(gcloud compute instances describe "$NAME" \
        --project="$PROJECT" \
        --zone="$ZONE" \
        --format="value(networkInterfaces[0].accessConfigs[0].networkTier)" 2>/dev/null)

    region="${ZONE%-*}"
    network_tier=${network_tier:-STANDARD}

    if [ -z "$nic_name" ] || [ -z "$access_config_name" ]; then
        echo -e "${RED}[错误] 未检测到实例的外部 IPv4 配置,无法切换。${RESET}"
        return
    fi

    static_addr_name=$(gcloud compute addresses list \
        --project="$PROJECT" \
        --regions="$region" \
        --filter="address=${current_ip}" \
        --format="value(name)" 2>/dev/null | head -n1)

    echo "------------------------------------"
    echo "实例名: $NAME"
    echo "可用区: $ZONE"
    echo "区域: $region"
    echo "当前公网IPv4: ${current_ip:-无}"
    if [ -n "$static_addr_name" ]; then
        echo "当前IPv4类型: 静态IP ($static_addr_name)"
    else
        echo "当前IPv4类型: 动态IP"
    fi
    echo "网络层级: $network_tier"
    echo "------------------------------------"
    echo "请选择操作:"
    echo "  [1] 动态IP -> 静态IP"
    echo "  [2] 静态IP -> 动态IP"
    echo "  [0] 返回主菜单"

    local choice
    read -p "请输入编号 [0-2]: " choice

    case "$choice" in
        1)
            if [ -z "$current_ip" ]; then
                echo -e "${RED}[错误] 当前实例没有公网 IPv4,无法直接转为静态。${RESET}"
                return
            fi

            if [ -n "$static_addr_name" ]; then
                echo -e "${YELLOW}[提示] 当前公网 IPv4 已经是静态IP,无需转换。${RESET}"
                return
            fi

            local new_addr_name
            new_addr_name=$(sanitize_name "${NAME}-${region}-ipv4")
            if gcloud compute addresses describe "$new_addr_name" --project="$PROJECT" --region="$region" >/dev/null 2>&1; then
                new_addr_name="${new_addr_name}-$(date +%s)"
            fi

            echo "-> 正在将当前动态 IPv4 保留为静态地址: $new_addr_name"
            gcloud compute addresses create "$new_addr_name" \
                --project="$PROJECT" \
                --region="$region" \
                --addresses="$current_ip" \
                --network-tier="$network_tier"

            if [ $? -eq 0 ]; then
                echo -e "${GREEN}>>> 已成功切换为静态IP: $current_ip (资源名: $new_addr_name)${RESET}"
            else
                echo -e "${RED}[错误] 动态IP 转 静态IP 失败。${RESET}"
            fi
            ;;
        2)
            if [ -z "$current_ip" ]; then
                echo -e "${RED}[错误] 当前实例没有公网 IPv4。${RESET}"
                return
            fi

            if [ -z "$static_addr_name" ]; then
                echo -e "${YELLOW}[提示] 当前公网 IPv4 已经是动态IP,无需转换。${RESET}"
                return
            fi

            echo -e "${YELLOW}[警告] 静态IP 转为动态IP 时,公网 IPv4 可能会发生变化。${RESET}"
            read -p "确认继续吗?(y/N): " confirm_change
            if [[ "$confirm_change" != "y" && "$confirm_change" != "Y" ]]; then
                echo "已取消。"
                return
            fi

            echo "-> 正在移除当前外部访问配置..."
            gcloud compute instances delete-access-config "$NAME" \
                --project="$PROJECT" \
                --zone="$ZONE" \
                --access-config-name="$access_config_name" \
                --network-interface="$nic_name"

            if [ $? -ne 0 ]; then
                echo -e "${RED}[错误] 删除旧访问配置失败,操作终止。${RESET}"
                return
            fi

            echo "-> 正在重新添加动态公网 IPv4 ..."
            gcloud compute instances add-access-config "$NAME" \
                --project="$PROJECT" \
                --zone="$ZONE" \
                --access-config-name="$access_config_name" \
                --network-interface="$nic_name" \
                --network-tier="$network_tier"

            if [ $? -ne 0 ]; then
                echo -e "${RED}[错误] 添加动态公网 IPv4 失败,请手动检查实例网络配置。${RESET}"
                return
            fi

            echo "-> 正在释放旧静态IP资源: $static_addr_name"
            gcloud compute addresses delete "$static_addr_name" \
                --project="$PROJECT" \
                --region="$region" \
                --quiet

            echo -e "${GREEN}>>> 已切换为动态IP。${RESET}"
            ;;
        0)
            echo "已取消。"
            ;;
        *)
            echo -e "${YELLOW}[错误] 输入无效。${RESET}"
            ;;
    esac

    echo
}

# ---------- 功能7:更换 Debian 12 镜像源 ----------
func_change_apt_source() {
    echo -e "\n>>> 准备更换 Debian 12 镜像源..."
    if ! select_existing_vm; then return; fi

    gcloud compute ssh "$NAME" \
        --project="$PROJECT" \
        --zone="$ZONE" \
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
        echo -e "${GREEN}>>> Debian 12 镜像源更换成功!${RESET}"
    else
        echo -e "${YELLOW}>>> 镜像源更换出现错误,请检查网络连接。${RESET}"
    fi
    echo
}

# ---------- 功能8:一键配置 SSH ----------
func_setup_ssh() {
    echo -e "\n>>> 准备配置 SSH 环境..."
    if ! select_existing_vm; then return; fi

    local ROOT_PASS ROOT_PASS_CONFIRM
    while true; do
        read -s -p "请设置新的 Root 密码 (输入时不可见): " ROOT_PASS
        echo
        read -s -p "请再次输入密码以确认: " ROOT_PASS_CONFIRM
        echo
        if [ "$ROOT_PASS" = "$ROOT_PASS_CONFIRM" ]; then
            if [ -z "$ROOT_PASS" ]; then
                echo -e "${YELLOW}[错误] 密码不能为空,请重试!${RESET}"
            else
                break
            fi
        else
            echo -e "${YELLOW}[错误] 两次输入的密码不一致,请重试!${RESET}"
        fi
    done

    gcloud compute ssh "$NAME" \
        --project="$PROJECT" \
        --zone="$ZONE" \
        --command="sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config && \
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/g' /etc/ssh/sshd_config && \
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config && \
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true && \
sudo sed -i 's/^#\?Port.*/Port ${DEFAULT_SSH_PORT}/g' /etc/ssh/sshd_config && \
echo \"root:${ROOT_PASS}\" | sudo chpasswd && \
sudo systemctl restart ssh || sudo systemctl restart sshd"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}>>> SSH 配置成功!${RESET}"
        echo -e ">>> 用户名: ${CYAN}root${RESET}"
        echo -e ">>> 端口: ${CYAN}${DEFAULT_SSH_PORT}${RESET}"
    else
        echo -e "${YELLOW}>>> SSH 配置过程中可能出现错误,请检查网络连接。${RESET}"
    fi
    echo
}

# ---------- 功能9:查看当前项目下所有实例信息 ----------
func_view_vm() {
    echo -e "\n>>> 准备扫描当前项目下的所有实例信息..."
    if ! auto_get_project; then
        echo -e "${YELLOW}[提示] 请先设置默认项目。${RESET}"
        return
    fi

    if ! ensure_required_apis; then
        return
    fi

    echo "------------------------------------"
    echo -e "${GREEN}【 实例详细信息列表 】${RESET}"

    local instances_data
    instances_data=$(gcloud compute instances list \
        --project="$PROJECT" \
        --format="value(name,zone.basename())" 2>/dev/null)

    if [ -z "$instances_data" ]; then
        echo -e "${YELLOW}[提示] 当前项目下没有实例。${RESET}"
        echo
        return
    fi

    local name zone
    while read -r name zone; do
        [ -z "$name" ] && continue

        local status
        local public_ipv4
        local disk_gb
        local image_name
        local network_tier

        status=$(gcloud compute instances describe "$name" \
            --project="$PROJECT" \
            --zone="$zone" \
            --format="value(status)" 2>/dev/null)

        public_ipv4=$(gcloud compute instances describe "$name" \
            --project="$PROJECT" \
            --zone="$zone" \
            --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)

        disk_gb=$(gcloud compute instances describe "$name" \
            --project="$PROJECT" \
            --zone="$zone" \
            --format="value(disks[0].diskSizeGb)" 2>/dev/null)

        image_name=$(gcloud compute instances describe "$name" \
            --project="$PROJECT" \
            --zone="$zone" \
            --format="value(disks[0].licenses[0].basename())" 2>/dev/null)

        network_tier=$(gcloud compute instances describe "$name" \
            --project="$PROJECT" \
            --zone="$zone" \
            --format="value(networkInterfaces[0].accessConfigs[0].networkTier)" 2>/dev/null)

        public_ipv4=${public_ipv4:-"-"}
        disk_gb=${disk_gb:-"-"}
        image_name=${image_name:-"-"}
        status=${status:-"-"}
        network_tier=${network_tier:-STANDARD}

        echo "实例名称: $name"
        echo "可用区: $zone"
        echo "公网IPv4: $public_ipv4"
        echo "磁盘GB: $disk_gb"
        echo "系统: $image_name"
        echo "网络层级: $network_tier"
        echo "状态: $status"
        echo "=========================================================="
    done <<< "$instances_data"

    echo
}

# ---------- 功能10:切换项目结算账号 ----------
func_switch_billing_account() {
    echo -e "\n>>> 准备切换项目结算账号..."
    if ! auto_get_project; then
        echo -e "${YELLOW}[提示] 请先设置默认项目。${RESET}"
        return
    fi

    echo "------------------------------------"
    echo -e "当前项目: ${CYAN}$PROJECT${RESET}"
    echo "-> 正在查询当前项目绑定的结算账号..."

    local current_billing_name current_billing_enabled current_billing_id
    current_billing_name=$(gcloud billing projects describe "$PROJECT" \
        --format="value(billingAccountName)" 2>/dev/null)
    current_billing_enabled=$(gcloud billing projects describe "$PROJECT" \
        --format="value(billingEnabled)" 2>/dev/null)

    if [ -n "$current_billing_name" ]; then
        current_billing_id=$(normalize_billing_account_id "$current_billing_name")
        echo "当前绑定状态: ${current_billing_enabled:-true}"
        echo -e "当前绑定结算账号: ${CYAN}$current_billing_id${RESET}"
    else
        echo -e "${YELLOW}[提示] 当前项目尚未绑定结算账号。${RESET}"
    fi

    echo "------------------------------------"
    echo "-> 正在获取账户下可见的结算账号列表..."

    local billing_data
    billing_data=$(gcloud billing accounts list \
        --format="value(name,displayName,open)" 2>/dev/null)

    if [ -z "$billing_data" ]; then
        echo -e "${RED}[错误] 未查询到任何结算账号。${RESET}"
        echo -e "${YELLOW}[提示] 可能原因: 当前账号无 Billing 权限,或当前账号下没有可用结算账号。${RESET}"
        echo
        return
    fi

    local acct_ids=()
    local acct_names=()
    local acct_status=()
    local i=1
    local full_name display_name is_open acct_id

    echo "------------------------------------"
    echo "可用结算账号列表:"
    while IFS=$'\t' read -r full_name display_name is_open; do
        [ -z "$full_name" ] && continue
        acct_id=$(normalize_billing_account_id "$full_name")
        acct_ids+=("$acct_id")
        acct_names+=("$display_name")
        acct_status+=("$is_open")
        echo -e "  [$i] 账号ID: ${CYAN}$acct_id${RESET}"
        echo "      名称:   $display_name"
        echo "      状态:   $is_open"
        ((i++))
    done <<< "$billing_data"

    echo "  [0] 返回主菜单"
    echo "------------------------------------"

    local choice
    while true; do
        read -p "请选择要绑定到当前项目的结算账号编号 [0-$((i-1))]: " choice
        if [[ "$choice" == "0" ]]; then
            echo "已取消。"
            echo
            return
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -lt "$i" ]; then
            local idx=$((choice-1))
            local selected_acct_id="${acct_ids[$idx]}"
            local selected_acct_name="${acct_names[$idx]}"

            if [ -n "${current_billing_id:-}" ] && [ "$selected_acct_id" = "$current_billing_id" ]; then
                echo -e "${YELLOW}[提示] 当前项目已经绑定到该结算账号,无需切换。${RESET}"
                echo
                return
            fi

            echo "------------------------------------"
            echo "当前项目: $PROJECT"
            echo "目标结算账号ID: $selected_acct_id"
            echo "目标结算账号名: $selected_acct_name"
            read -p "确认切换当前项目的结算账号吗?(y/N): " confirm_link

            if [[ "$confirm_link" != "y" && "$confirm_link" != "Y" ]]; then
                echo "已取消。"
                echo
                return
            fi

            gcloud billing projects link "$PROJECT" \
                --billing-account="$selected_acct_id"

            if [ $? -eq 0 ]; then
                echo -e "${GREEN}>>> 项目 [$PROJECT] 已成功切换到结算账号 [$selected_acct_id] !${RESET}"
            else
                echo -e "${RED}[错误] 结算账号切换失败。${RESET}"
                echo -e "${YELLOW}[提示] 请检查是否具有 Billing Account User / Project Billing Manager 等权限。${RESET}"
            fi
            echo
            return
        else
            echo -e "${YELLOW}[错误] 输入无效,请重试。${RESET}"
        fi
    done
}

# ---------- 功能11:删除实例 ----------
func_delete_vm() {
    echo -e "\n${RED}>>> [警告] 准备执行删除实例操作...${RESET}"
    if ! select_existing_vm; then return; fi

    read -p "确定要彻底删除实例 [$NAME] 吗?(y/N): " CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        echo "已取消删除。"
        return
    fi

    gcloud compute instances delete "$NAME" \
        --project="$PROJECT" \
        --zone="$ZONE" \
        --quiet

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}>>> 实例 $NAME 已彻底删除!${RESET}\n"
    else
        echo -e "${RED}[错误] 实例删除失败。${RESET}\n"
    fi
}

# ---------- 功能12:删除 防火墙规则 ----------
func_delete_firewall_rules() {
    echo -e "\n>>> 准备删除防火墙规则..."
    if ! auto_get_project; then
        echo -e "${YELLOW}[提示] 请先设置默认项目。${RESET}"
        return
    fi

    if ! ensure_required_apis; then
        return
    fi

    read -p "请输入目标 VPC 名称 [默认: ${DEFAULT_VPC_NAME}]: " VPC_NAME
    VPC_NAME=${VPC_NAME:-$DEFAULT_VPC_NAME}
    build_firewall_rule_names "$VPC_NAME"

    echo "即将删除以下规则:"
    echo "  - $FW_RULE_V4IN"
    echo "  - $FW_RULE_V4OUT"

    read -p "确认继续吗?(y/N): " confirm_fw_del
    if [[ "$confirm_fw_del" != "y" && "$confirm_fw_del" != "Y" ]]; then
        echo "已取消。"
        return
    fi

    local rule
    for rule in "$FW_RULE_V4IN" "$FW_RULE_V4OUT"; do
        if gcloud compute firewall-rules describe "$rule" --project="$PROJECT" >/dev/null 2>&1; then
            echo "-> 删除规则: $rule"
            gcloud compute firewall-rules delete "$rule" \
                --project="$PROJECT" \
                --quiet
        else
            echo -e "${YELLOW}[提示] 规则不存在,跳过: $rule${RESET}"
        fi
    done

    echo -e "${GREEN}>>> 防火墙规则删除流程完成。${RESET}\n"
}

# ---------- 主菜单 ----------
main_menu() {
    while true; do
        echo "=============================================================="
        echo "         GCP 免费机快捷管理脚本  vFree-1.0                    "
        echo "=============================================================="
        echo "  1. 查看账号的项目"
        echo "  2. 设置默认项目"
        echo "  3. 创建免费机"
        echo "  4. 查看防火墙规则"
        echo "  5. 设置防火墙规则 (VPC前缀-v4in/v4out)"
        echo "  6. 动/静态ip切换"
        echo "  7. 更换系统镜像源 (Debian 12 专用)"
        echo "  8. 一键配置 SSH (Root密码+端口${DEFAULT_SSH_PORT})"
        echo "  9. 查看当前项目下所有实例信息"
        echo " 10. 切换项目结算账号"
        echo " 11. 删除实例"
        echo " 12. 删除 防火墙规则"
        echo "  0. 退出脚本"
        echo "=============================================================="
        show_current_project
        echo "--------------------------------------------------------------"

        read -p "请输入对应的数字 [0-12]: " choice
        case $choice in
            1) func_view_projects ;;
            2) func_set_default_project ;;
            3) func_create_vm ;;
            4) func_view_firewall ;;
            5) func_setup_firewall ;;
            6) func_toggle_ip_mode ;;
            7) func_change_apt_source ;;
            8) func_setup_ssh ;;
            9) func_view_vm ;;
            10) func_switch_billing_account ;;
            11) func_delete_vm ;;
            12) func_delete_firewall_rules ;;
            0) echo "已退出。"; exit 0 ;;
            *) echo -e "\n[错误] 无效的选项,请重新输入!\n" ;;
        esac
    done
}

# ---------- 程序入口 ----------
check_gcloud
main_menu
