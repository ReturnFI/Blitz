<div align="center">

[![Telegram](https://img.shields.io/badge/Telegram-Join%20Chat-26A5E4?logo=telegram&logoColor=white)](https://t.me/hysteria2_panel)
[![Docs](https://img.shields.io/badge/Docs-Read%20Now-FFA500?logo=bookstack&logoColor=white)](https://returnfi.github.io/Blitz-docs/)
[![Language](https://img.shields.io/badge/Language-Persian-009688?logo=google-translate&logoColor=white)](README-fa.md)
[![Latest Release](https://img.shields.io/badge/Release-Latest-brightgreen?logo=github)](https://github.com/ReturnFI/Blitz/releases)
[![License](https://img.shields.io/badge/License-GPL-blueviolet?logo=open-source-initiative&logoColor=white)](LICENSE)
[![Made with ❤️](https://img.shields.io/badge/Made%20with-%E2%9D%A4-red)](#)

</div>


# 🚀 Blitz Panel 🚀

<div align=center>

<img width="2150" height="1115" alt="custom_output" src="https://github.com/user-attachments/assets/2bb6ddd6-c612-4ad1-84d9-76f11cdadfdd" />

 </div>




A powerful and user-friendly management panel for Hysteria2 proxy server. Features include complete user management, traffic monitoring, WARP integration, Telegram bot support, and multiple subscription formats. Simple installation with advanced configuration options for both beginners and experienced users.


## 📋 Quick Start Guide

### One-Click Installation
```bash
bash <(curl https://raw.githubusercontent.com/ReturnFI/Blitz/main/install.sh)
```
After installation, use `hys2` to launch the management panel.

There is no need to execute the installation command again.



## 🐳 Docker Installation (Local Build)

> **Note:** This is a local build method for development and testing. A pre-built image on Docker Hub is planned for the future.

### Prerequisites

- [Docker](https://docs.docker.com/engine/install/) and [Docker Compose](https://docs.docker.com/compose/install/)

### Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/ReturnFI/Blitz.git
cd Blitz

# 2. Create and configure your environment file
cp docker/.env.example docker/.env
nano docker/.env

# 3. Build and start
docker compose up -d --build

# 4. Get the admin password and web panel URL from the logs
docker logs blitz 2>&1 | grep -E "ADMIN PASSWORD|Access at"
```

For the full list of environment variables, architecture details, common operations, and troubleshooting, see [docker/README.md](docker/README.md).

---

## 💎 Sponsorship & Support 💖


| Sponsor                  | Description                                                    | Link                                                         |
| ------------------------ | -------------------------------------------------------------- | ------------------------------------------------------------ |
| 🖥️ [**Petrosky Hosting**](https://client.petrosky.io/aff.php?aff=344) | 👉 [A hosting for your entire journey!](https://client.petrosky.io/aff.php?aff=344) | [Visit Petrosky](https://client.petrosky.io/aff.php?aff=344) |


## 💰 Crypto Donations

If you find this project helpful and want to support its development:

| Cryptocurrency | Address                                              |
| :------------- | :--------------------------------------------------- |
| **TON**        | `UQBJe1IzfLp4tk5nnhwT_saXmqlldNIzhSVPdPUKTq2YtmSh`   |
| **TRX (Tron)** | `TER9F7kmNsbb8D3iCMXs2EddTYQU7cMXGn`                 |
| **USDT (TRC20)** | `TER9F7kmNsbb8D3iCMXs2EddTYQU7cMXGn`               |

Your support means a lot and helps us improve the project continuously 💖

### 🙏 Support Disclaimer

We deeply appreciate your generosity! Please note:

* All donations are voluntary and do not grant any privileges or guarantees.
* This is an open-source project. We provide the tools and panel only — not VPN or proxy services.
* You are responsible for setting up and managing your own infrastructure.
* Always be cautious of scams. Only trust official channels.

Thank you for keeping this project alive and thriving! ❤️


## ⚠️ Disclaimer

This tool is provided for educational and research purposes only. Users are responsible for:
- Complying with local laws and regulations
- Ensuring appropriate usage of proxy servers
- Maintaining server security
- Protecting user privacy

## 🙏 Acknowledgments

- [Hysteria2 Core Team ](https://github.com/apernet/hysteria)
- Community Members
- [IamSarina](https://github.com/Iam54r1n4)

---

<p align="center">Made with ❤️</p>
