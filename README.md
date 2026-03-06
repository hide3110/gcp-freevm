# gcp-freevm脚本
这个 Bash 脚本可以帮助你在google shell中快速部署 debian 12 系统的 us free vm。

### 通过一键脚本自定义安装
自定义变量参数：
$PROJECT 为你 google 的 project 名称,如 p-xfenshx ；
$ZONE 为创建机器的区域，如 us-west1-b ；
$NAME 为创建的实例名称名称，如 us-free ；
```bash
PROJECT=p-xfenshx ZONE=us-west1-b NAME=us-free bash <(curl -fsSL https://raw.githubusercontent.com/hide3110/gcp-freevm/main/gcp.sh)
```

## 详细说明
- 默认安装 debian 12 系统，可自定版本安装，需要自行修改配置文件
