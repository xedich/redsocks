#!/bin/bash
chisel_server="${1}"
docker_ipv4=$(ip -f inet addr show eth0 | grep -Po 'inet \K[\d.]+')
proxy_ip="${docker_ipv4:-127.0.0.1}"
proxy_port=1080
proxy_type="socks5"

if [ -z "$chisel_server" ]; then
    echo "Chisel server cannot be empty"
    exit 1
fi

echo "Creating redsocks configuration file using proxy ${proxy_ip}:${proxy_port}..."
sed -e "s|\${proxy_ip}|${proxy_ip}|" \
    -e "s|\${proxy_port}|${proxy_port}|" \
    -e "s|\${proxy_type}|${proxy_type}|" \
    /etc/redsocks.tmpl > /tmp/redsocks.conf

echo "Generated configuration:"
cat /tmp/redsocks.conf

echo "Activating iptables rules..."
/usr/local/bin/redsocks-fw.sh start

pid=0

# SIGUSR1 handler
usr_handler() {
  echo "usr_handler"
}

# SIGTERM-handler
term_handler() {
    if [ $pid -ne 0 ]; then
        echo "Term signal catched. Shutdown redsocks and disable iptables rules..."
        kill -SIGTERM "$pid"
        wait "$pid"
        /usr/local/bin/redsocks-fw.sh stop
    fi
    exit 143; # 128 + 15 -- SIGTERM
}

# setup handlers
trap 'kill ${!}; usr_handler' SIGUSR1
trap 'kill ${!}; term_handler' SIGTERM

echo "Starting redsocks..."
/usr/sbin/redsocks -c /tmp/redsocks.conf &
pid="$!"

/usr/local/bin/chisel-install.sh
chisel client "$chisel_server" 0.0.0.0:1080:socks
