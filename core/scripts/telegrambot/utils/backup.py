import telebot
import subprocess
import qrcode
import io
import json
import os
import shlex
import re
from dotenv import load_dotenv
from telebot import types
from utils.command import *


@bot.message_handler(func=lambda message: is_admin(message.from_user.id) and message.text == '💾 Backup Server')
def backup_server(message):
    bot.reply_to(message, "Starting backup. This may take a few moments...")
    bot.send_chat_action(message.chat.id, 'typing')
    
    backup_command = f"python3 {CLI_PATH} backup-hysteria"
    result = run_cli_command(backup_command)

    if "Error" in result:
        bot.reply_to(message, f"Backup failed: {result}")
    else:
        bot.reply_to(message, "Backup completed successfully!")

    
    try:
        files = [f for f in os.listdir(BACKUP_DIRECTORY) if f.endswith('.zip')]
        files.sort(key=lambda x: os.path.getctime(os.path.join(BACKUP_DIRECTORY, x)), reverse=True)
        latest_backup_file = files[0] if files else None
    except Exception as e:
        bot.reply_to(message, f"Failed to locate the backup file: {str(e)}")
        return
    
    if latest_backup_file:
        backup_file_path = os.path.join(BACKUP_DIRECTORY, latest_backup_file)
        with open(backup_file_path, 'rb') as f:
            bot.send_document(message.chat.id, f, caption=f"Backup completed: {latest_backup_file}")
    else:
        bot.reply_to(message, "No backup file found after the backup process.")