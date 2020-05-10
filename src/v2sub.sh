#!/bin/bash
export LC_ALL=C
export LANG=C
export LANGUAGE=en_US.UTF-8

branch="master"

if [[ $(/usr/bin/id -u) -ne 0 ]]; then
  sudoCmd="sudo"
else
  sudoCmd=""
fi

# copied from v2ray official script
# colour code
RED="31m"      # Error message
GREEN="32m"    # Success message
YELLOW="33m"   # Warning message
BLUE="36m"     # Info message
# colour function
colorEcho(){
  echo -e "\033[${1}${@:2}\033[0m" 1>& 2
}

#copied & modified from atrandys trojan scripts
#copy from 秋水逸冰 ss scripts
if [[ -f /etc/redhat-release ]]; then
  release="centos"
  systemPackage="yum"
  #colorEcho ${RED} "unsupported OS"
  #exit 0
elif cat /etc/issue | grep -Eqi "debian"; then
  release="debian"
  systemPackage="apt-get"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
  release="ubuntu"
  systemPackage="apt-get"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
  release="centos"
  systemPackage="yum"
  #colorEcho ${RED} "unsupported OS"
  #exit 0
elif cat /proc/version | grep -Eqi "debian"; then
  release="debian"
  systemPackage="apt-get"
elif cat /proc/version | grep -Eqi "ubuntu"; then
  release="ubuntu"
  systemPackage="apt-get"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
  release="centos"
  systemPackage="yum"
  #colorEcho ${RED} "unsupported OS"
  #exit 0
fi

read_json() {
  # jq [key] [path-to-file]
  ${sudoCmd} jq --raw-output $2 $1 2>/dev/null | tr -d '\n'
} ## read_json [path-to-file] [key]

write_json() {
  # jq [key = value] [path-to-file]
  jq -r "$2 = $3" $1 > tmp.$$.json && ${sudoCmd} mv tmp.$$.json $1 && sleep 1
} ## write_json [path-to-file] [key = value]

urlencode() {
  local length="${#1}"
  for (( i = 0; i < length; i++ )); do
      local c="${1:i:1}"
      case $c in
          [a-zA-Z0-9.~_-]) printf "$c" ;;
          *) printf "$c" | xxd -p -c1 | while read x;do printf "%%%s" "$x";done
      esac
  done
}

# a trick to redisplay menu option
show_menu() {
  echo ""
  echo "1) 生成订阅"
  echo "2) 更新订阅"
  echo "3) 显示订阅"
}

continue_prompt() {
  read -p "继续其他操作 (yes/no)? " choice
  case "${choice}" in
    y|Y|[yY][eE][sS] ) show_menu ;;
    * ) exit 0;;
  esac
}

get_docker() {
  if [ ! -x "$(command -v docker)" ]; then
    curl -sL https://get.docker.com/ | ${sudoCmd} bash
  fi
}

set_proxy() {
  ${sudoCmd} /bin/cp /etc/tls-shunt-proxy/config.yaml /etc/tls-shunt-proxy/config.yaml.bak 2>/dev/null
  wget -q https://raw.githubusercontent.com/phlinhng/v2ray-tcp-tls-web/${branch}/config/config.yaml -O /tmp/config_new.yaml

  if [[ $(read_json /usr/local/etc/v2script/config.json '.v2ray.installed') == "true" ]]; then
    sed -i "s/FAKEV2DOMAIN/$(read_json /usr/local/etc/v2script/config.json '.v2ray.tlsHeader')/g" /tmp/config_new.yaml
    sed -i "s/##V2RAY@//g" /tmp/config_new.yaml
  fi

  if [[ $(read_json /usr/local/etc/v2script/config.json '.sub.api.installed') == "true" ]]; then
    sed -i "s/FAKEAPIDOMAIN/$(read_json /usr/local/etc/v2script/config.json '.sub.api.tlsHeader')/g" /tmp/config_new.yaml
    sed -i "s/##SUBAPI@//g" /tmp/config_new.yaml
  fi

  if [[ $(read_json /usr/local/etc/v2script/config.json '.mtproto.installed') == "true" ]]; then
    sed -i "s/FAKEMTDOMAIN/$(read_json /usr/local/etc/v2script/config.json '.mtproto.fakeTlsHeader')/g" /tmp/config_new.yaml
    sed -i "s/##MTPROTO@//g" /tmp/config_new.yaml
  fi

  ${sudoCmd} /bin/cp -f /tmp/config_new.yaml /etc/tls-shunt-proxy/config.yaml
}

install_api() {
  if [[ $(read_json /usr/local/etc/v2script/config.json '.sub.enabled') == "true" ]]; then
    read -p "用于API的域名 (出于安全考虑，请使用和v2Ray不同的子域名): " api_domain
    if [[ $(read_json /usr/local/etc/v2script/config.json '.v2ray.installed') == "true" ]]; then
      if [[ $(read_json /usr/local/etc/v2script/config.json '.v2ray.tlsHeader') == "${api_domain}" ]]; then
        colorEcho ${RED} "域名 ${api_domain} 与现有v2Ray域名相同"
        show_menu
        return 1
      fi
    fi
    ${sudoCmd} ${systemPackage} install curl -y -qq
    get_docker
    docker run -d -p 127.0.0.1:25500:25500 tindy2013/subconverter:latest
    write_json /usr/local/etc/v2script/config.json ".sub.api.installed" "true"
    write_json /usr/local/etc/v2script/config.json ".sub.api.tlsHeader" "\"${api_domain}\""
    set_proxy
    ${sudoCmd} systemctl restart tls-shunt-proxy
    colorEcho ${GREEN} "subscription manager api has been set up."
  else
    colorEcho ${YELLOW} "你还没有生成订阅连接"
  fi
}

generate_link() {
  if [ ! -d "/usr/bin/v2ray" ]; then
    colorEcho ${RED} "尚末安装v2Ray"
    return 1
  elif [ ! -f "/usr/local/etc/v2script/config.json" ]; then
    colorEcho ${RED} "配置文件不存在"
    return 1
  fi

  if [[ $(read_json /usr/local/etc/v2script/config.json '.sub.enabled') != "true" ]]; then
    write_json /usr/local/etc/v2script/config.json '.sub.enabled' "true"
  fi

  if [[ "$(read_json /usr/local/etc/v2script/config.json '.sub.uri')" != "" ]]; then
    ${sudoCmd} rm -f /var/www/html/$(read_json /usr/local/etc/v2script/config.json '.sub.uri')
    write_json /usr/local/etc/v2script/config.json '.sub.uri' \"\"
  fi

  #${sudoCmd} ${systemPackage} install uuid-runtime coreutils jq -y
  uuid="$(read_json /etc/v2ray/config.json '.inbounds[0].settings.clients[0].id')"
  V2_DOMAIN="$(read_json /usr/local/etc/v2script/config.json '.v2ray.tlsHeader')"

  read -p "输入节点名称[留空则使用默认值]: " remark

  if [ -z "${remark}" ]; then
    remark="${V2_DOMAIN}:443"
  fi

  json="{\"add\":\"${V2_DOMAIN}\",\"aid\":\"0\",\"host\":\"\",\"id\":\"${uuid}\",\"net\":\"\",\"path\":\"\",\"port\":\"443\",\"ps\":\"${remark}\",\"tls\":\"tls\",\"type\":\"none\",\"v\":\"2\"}"

  uri="$(printf "${json}" | base64)"
  sub="$(printf "vmess://${uri}" | tr -d '\n' | base64)"

  randomName="$(uuidgen | sed -e 's/-//g' | tr '[:upper:]' '[:lower:]' | head -c 16)" #random file name for subscription
  write_json /usr/local/etc/v2script/config.json '.sub.uri' "\"${randomName}\""

  printf "${sub}" | tr -d '\n' | ${sudoCmd} tee /var/www/html/$(read_json /usr/local/etc/v2script/config.json '.sub.uri') >/dev/null
  echo "https://${V2_DOMAIN}/${randomName}" | tr -d '\n' && printf "\n"
}

update_link() {
  if [ ! -d "/usr/bin/v2ray" ]; then
    colorEcho ${RED} "尚末安装v2Ray"
    return 1
  elif [ ! -f "/usr/local/etc/v2script/config.json" ]; then
    colorEcho ${RED} "配置文件不存在"
    return 1
  fi

  if [[ $(read_json /usr/local/etc/v2script/config.json '.sub.enabled') == "true" ]]; then
    uuid="$(read_json /etc/v2ray/config.json '.inbounds[0].settings.clients[0].id')"
    V2_DOMAIN="$(read_json /usr/local/etc/v2script/config.json '.v2ray.tlsHeader')"
    currentRemark="$(read_json /usr/local/etc/v2script/config.json '.sub.nodes[0]' | base64 -d | sed 's/^vmess:\/\///g' | base64 -d | jq --raw-output '.ps' | tr -d '\n')"
    read -p "输入节点名称[留空则使用默认值]: " remark

    if [ -z "${remark}" ]; then
      remark=currentRemark
    fi

    json="{\"add\":\"${V2_DOMAIN}\",\"aid\":\"0\",\"host\":\"\",\"id\":\"${uuid}\",\"net\":\"\",\"path\":\"\",\"port\":\"443\",\"ps\":\"${remark}\",\"tls\":\"tls\",\"type\":\"none\",\"v\":\"2\"}"
    uri="$(printf "${json}" | base64)"
    sub="$(printf "vmess://${uri}" | tr -d '\n' | base64)"

    printf "${sub}" | tr -d '\n' | ${sudoCmd} tee /var/www/html/$(read_json /usr/local/etc/v2script/config.json '.sub.uri') >/dev/null
    echo "https://${V2_DOMAIN}/$(read_json /usr/local/etc/v2script/config.json '.sub.uri')" | tr -d '\n' && printf "\n"

    colorEcho ${GREEN} "更新订阅完成"
  else
    generate_link
  fi
}

display_link_main() {
  V2_DOMAIN="$(read_json /usr/local/etc/v2script/config.json '.v2ray.tlsHeader')"
  echo "https://${V2_DOMAIN}/$(read_json /usr/local/etc/v2script/config.json '.sub.uri')" | tr -d '\n' && printf "\n"
}

display_link() {
  if [ ! -d "/usr/bin/v2ray" ]; then
    colorEcho ${RED} "尚末安装v2Ray"
    return 1
  elif [ ! -f "/usr/local/etc/v2script/config.json" ]; then
    colorEcho ${RED} "配置文件不存在"
    return 1
  fi

  if [[ "$(read_json /usr/local/etc/v2script/config.json '.sub.api.installed')" == "true" ]]; then
    mainSub="https://$(read_json /usr/local/etc/v2script/config.json '.v2ray.tlsHeader')/$(read_json /usr/local/etc/v2script/config.json '.sub.uri')"
    mainSubEncoded="$(urlencode ${mainSub})"
    apiPrefix="https://$(read_json /usr/local/etc/v2script/config.json '.sub.api.tlsHeader')/sub?url=${mainSubEncoded}&target="

    colorEcho ${YELLOW} "v2RayNG / Shadowrocket / Pharos Pro"
    printf "${mainSub}" | tr -d '\n' && printf "\n\n"

    colorEcho ${YELLOW} "Clash"
    printf "${apiPrefix}clash" | tr -d '\n' && printf "\n\n"

    colorEcho ${YELLOW} "ClashR"
    printf "${apiPrefix}clashr" | tr -d '\n' && printf "\n\n"

    colorEcho ${YELLOW} "Quantumult"
    printf "${apiPrefix}quan" | tr -d '\n' && printf "\n\n"

    colorEcho ${YELLOW} "QuantumultX"
    printf "${apiPrefix}quanx" | tr -d '\n' && printf "\n\n"
    
    colorEcho ${YELLOW} "Loon"
    printf "${apiPrefix}loon" | tr -d '\n' && printf "\n"
  elif [[ $(read_json /usr/local/etc/v2script/config.json '.sub.enabled') == "true" ]]; then
    colorEcho ${YELLOW} "若您使用v2RayNG/Shdowrocket/Pharos Pro以外的客戶端, 需要安装订阅管理API"
    read -p "是否安装 (yes/no)? " choice
    case "${choice}" in
      y|Y|[yY][eE][sS] ) install_api;;
      * ) display_link_main;;
    esac
  else
    colorEcho ${YELLOW} "你还没有生成订阅连接, 请先运行\"1) 生成订阅\""
  fi
}

menu() {
  colorEcho ${YELLOW} "v2Ray TCP+TLS+WEB subscription manager v1.0"
  colorEcho ${YELLOW} "author: phlinhng"
  echo ""

  PS3="选择操作[输入任意值或按Ctrl+C退出]: "
  COLUMNS=39
  options=("生成订阅" "更新订阅" "显示订阅")
  select opt in "${options[@]}"
  do
    case "${opt}" in
      "生成订阅") generate_link && continue_prompt ;;
      "更新订阅") update_link && continue_prompt ;;
      "显示订阅") display_link && continue_prompt ;;
      *) break;;
    esac
  done

}

menu