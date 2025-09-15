from dotenv import load_dotenv
from telebot import types
from utils.command import *

@bot.message_handler(func=lambda message: is_admin(message.from_user.id) and message.text == '🖥️ Server Info')
def server_info(message):
    command = f"python3 {CLI_PATH} server-info"
    result = run_cli_command(command)
    bot.send_chat_action(message.chat.id, 'typing')
    bot.reply_to(message, result)