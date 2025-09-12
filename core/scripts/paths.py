from pathlib import Path

BASE_DIR = Path("/etc/hysteria")

CLI_PATH = BASE_DIR / "core/cli.py"
USERS_FILE = BASE_DIR / "users.json"
TRAFFIC_FILE = BASE_DIR / "traffic_data.json"
CONFIG_FILE = BASE_DIR / "config.json"
CONFIG_ENV = BASE_DIR / ".configs.env"
NODES_JSON_PATH = BASE_DIR / "nodes.json"
EXTRA_CONFIG_PATH = BASE_DIR / "extra.json"
TELEGRAM_ENV = BASE_DIR / "core/scripts/telegrambot/.env"
SINGBOX_ENV = BASE_DIR / "core/scripts/singbox/.env"
NORMALSUB_ENV = BASE_DIR / "core/scripts/normalsub/.env"
WEBPANEL_ENV = BASE_DIR / "core/scripts/webpanel/.env"
API_BASE_URL = "http://127.0.0.1:25413"
ONLINE_API_URL = "http://127.0.0.1:25413/online"
LOCALVERSION = BASE_DIR / "VERSION"
LATESTVERSION = "https://raw.githubusercontent.com/ReturnFI/Blitz/nodb/VERSION"
LASTESTCHANGE = "https://raw.githubusercontent.com/ReturnFI/Blitz/nodb/changelog"
CONNECTIONS_FILE = BASE_DIR / "hysteria_connections.json"
BLOCK_LIST = Path("/tmp/hysteria_blocked_ips.txt")
SCRIPT_PATH = BASE_DIR / "core/scripts/hysteria2/limit.sh"

