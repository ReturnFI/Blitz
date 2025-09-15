#!/usr/bin/env python3

import argparse
import json
import sys
import os
from hysteria2_api import Hysteria2Client, Hysteria2Error

from init_paths import *
from paths import *


def get_api_secret(config_path: str) -> str:
    if not os.path.exists(config_path):
        raise FileNotFoundError(f"Configuration file not found: {config_path}")

    try:
        with open(config_path, 'r', encoding='utf-8') as f:
            config_data = json.load(f)

        traffic_stats = config_data.get('trafficStats')
        if not isinstance(traffic_stats, dict):
             raise KeyError("Key 'trafficStats' not found or is not a dictionary in config")

        secret = traffic_stats.get('secret')
        if not secret:
            raise ValueError("Value for 'trafficStats.secret' not found or is empty in config")

        return secret

    except json.JSONDecodeError as e:
        raise json.JSONDecodeError(f"Error parsing JSON file: {config_path} - {e.msg}", e.doc, e.pos)
    except KeyError as e:
         raise KeyError(f"Missing expected key {e} in {config_path}")


def main():
    parser = argparse.ArgumentParser(
        description="Kick one or more Hysteria2 users via the API.",
        usage="%(prog)s <username1> [username2] ..."
    )
    parser.add_argument(
        "usernames",
        nargs='+',
        help="The username(s) (Auth identity) to kick."
    )
    args = parser.parse_args()
    usernames_to_kick = args.usernames

    try:
        api_secret = get_api_secret(CONFIG_FILE)
        # print(api_secret)
        # print(f"Kicking user: {username_to_kick}")

        client = Hysteria2Client(
            base_url=API_BASE_URL,
            secret=api_secret
        )

        client.kick_clients(usernames_to_kick)
        sys.exit(0)

    except (FileNotFoundError, KeyError, ValueError, json.JSONDecodeError) as e:
        print(f"Configuration Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Hysteria2Error as e:
        print(f"API Error kicking users: {e}", file=sys.stderr)
        sys.exit(1)
    except ConnectionError as e:
         print(f"Connection Error: Could not connect to API at {API_BASE_URL}. Is it running? Details: {e}", file=sys.stderr)
         sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()