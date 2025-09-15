#!/usr/bin/env python3

import init_paths
import sys
import os
from db.database import db

def remove_users(usernames):
    if db is None:
        return 1, "Error: Database connection failed. Please ensure MongoDB is running."

    if not usernames:
        return 1, "Error: No usernames provided for removal."

    try:
        result = db.delete_users(usernames)
        
        if result.deleted_count > 0:
            return 0, f"{result.deleted_count} user(s) removed successfully."
        else:
            return 1, "Error: No matching users found for removal."

    except Exception as e:
        return 1, f"An error occurred while removing users: {e}"

def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <username1> [username2] ...")
        sys.exit(1)

    usernames = [username.lower() for username in sys.argv[1:]]
    exit_code, message = remove_users(usernames)
    print(message)
    sys.exit(exit_code)

if __name__ == "__main__":
    main()