连接 SSH 后，全新系统复制下面这行命令运行即可：

apt update -y && apt install -y wget && wget -O install.sh https://raw.githubusercontent.com/wwfemg/vps-kit/main/install.sh && bash install.sh

如果忘记，记得用这个查询：vp

连接 SSH 后，如果安装完依赖直接使用下面这条命令：

wget -O install.sh https://raw.githubusercontent.com/wwfemg/vps-kit/main/install.sh && bash install.sh
