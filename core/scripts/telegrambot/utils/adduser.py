import qrcode
import io
import json
import re
from telebot import types
from utils.command import *
from utils.common import create_main_markup

def escape_markdown(text):
    return str(text).replace('_', '\\_').replace('*', '\\*').replace('`', '\\`')

def create_cancel_markup(back_step=None):
    markup = types.ReplyKeyboardMarkup(resize_keyboard=True, one_time_keyboard=True)
    if back_step:
        markup.row(types.KeyboardButton("⬅️ Back"))
    markup.row(types.KeyboardButton("❌ Cancel"))
    return markup

@bot.message_handler(func=lambda message: is_admin(message.from_user.id) and message.text == '➕ Add User')
def add_user(message):
    msg = bot.reply_to(message, "Enter username (only letters, numbers, and underscores are allowed):", reply_markup=create_cancel_markup())
    bot.register_next_step_handler(msg, process_add_user_step1)

def process_add_user_step1(message):
    if message.text == "❌ Cancel":
        bot.reply_to(message, "Process canceled.", reply_markup=create_main_markup())
        return

    username = message.text.strip()
    
    if not re.match("^[a-zA-Z0-9_]*$", username):
        bot.reply_to(message, "Invalid username. Only letters, numbers, and underscores are allowed. Please try again:", reply_markup=create_cancel_markup())
        bot.register_next_step_handler(message, process_add_user_step1)
        return

    if not username:
        bot.reply_to(message, "Username cannot be empty. Please enter a valid username:", reply_markup=create_cancel_markup())
        bot.register_next_step_handler(message, process_add_user_step1)
        return

    if '\n' in username or len(username) > 50:
        bot.reply_to(message, "Invalid username format. Please use a shorter username without newlines.", reply_markup=create_cancel_markup())
        bot.register_next_step_handler(message, process_add_user_step1)
        return

    command = f"python3 {CLI_PATH} list-users"
    result = run_cli_command(command)

    try:
        users_data = json.loads(result)
        existing_users = {user['username'].lower() for user in users_data}
        if username.lower() in existing_users:
            bot.reply_to(message, f"Username '{escape_markdown(username)}' already exists. Please choose a different username:", reply_markup=create_cancel_markup())
            bot.register_next_step_handler(message, process_add_user_step1)
            return
    except json.JSONDecodeError:
        if "No such file or directory" in result or result.strip() == "" or "Could not find users" in result.lower():
            pass
        else:
            bot.reply_to(message, "Error checking existing users. Please try again.", reply_markup=create_main_markup())
            return
    
    msg = bot.reply_to(message, "Enter traffic limit (GB):", reply_markup=create_cancel_markup(back_step=process_add_user_step1))
    bot.register_next_step_handler(msg, process_add_user_step2, username)

def process_add_user_step2(message, username):
    if message.text == "❌ Cancel":
        bot.reply_to(message, "Process canceled.", reply_markup=create_main_markup())
        return
    if message.text == "⬅️ Back":
        msg = bot.reply_to(message, "Enter username (only letters, numbers, and underscores are allowed):", reply_markup=create_cancel_markup())
        bot.register_next_step_handler(msg, process_add_user_step1)
        return

    try:
        traffic_limit = int(message.text.strip())
        if traffic_limit < 0:
             bot.reply_to(message, "Traffic limit cannot be negative. Please enter a valid number (GB):", reply_markup=create_cancel_markup(back_step=process_add_user_step1))
             bot.register_next_step_handler(message, process_add_user_step2, username)
             return
        msg = bot.reply_to(message, "Enter expiration days:", reply_markup=create_cancel_markup(back_step=process_add_user_step2))
        bot.register_next_step_handler(msg, process_add_user_step3, username, traffic_limit)
    except ValueError:
        bot.reply_to(message, "Invalid traffic limit. Please enter a number (GB):", reply_markup=create_cancel_markup(back_step=process_add_user_step1))
        bot.register_next_step_handler(message, process_add_user_step2, username)

def process_add_user_step3(message, username, traffic_limit):
    if message.text == "❌ Cancel":
        bot.reply_to(message, "Process canceled.", reply_markup=create_main_markup())
        return
    if message.text == "⬅️ Back":
        msg = bot.reply_to(message, "Enter traffic limit (GB):", reply_markup=create_cancel_markup(back_step=process_add_user_step1))
        bot.register_next_step_handler(msg, process_add_user_step2, username)
        return

    try:
        expiration_days = int(message.text.strip())
        if expiration_days < 0:
            bot.reply_to(message, "Expiration days cannot be negative. Please enter a valid number:", reply_markup=create_cancel_markup(back_step=process_add_user_step2))
            bot.register_next_step_handler(message, process_add_user_step3, username, traffic_limit)
            return
            
        add_user_command = f"python3 {CLI_PATH} add-user -u \"{username}\" -t {traffic_limit} -e {expiration_days}"
        add_user_feedback = run_cli_command(add_user_command).strip()

        bot.send_chat_action(message.chat.id, 'typing')
        
        uri_info_command = f"python3 {CLI_PATH} show-user-uri -u \"{username}\" -ip 4 -n -s"
        uri_info_output = run_cli_command(uri_info_command)

        direct_uri = None
        normal_sub_link = None

        lines = uri_info_output.strip().split('\n')
        for i, line in enumerate(lines):
            if line.strip() == "IPv4:":
                if i + 1 < len(lines) and lines[i+1].strip().startswith("hy2://"):
                    direct_uri = lines[i+1].strip()
            elif line.strip() == "Normal-SUB Sublink:":
                if i + 1 < len(lines) and (lines[i+1].strip().startswith("http://") or lines[i+1].strip().startswith("https://")):
                    normal_sub_link = lines[i+1].strip()

        escaped_feedback = escape_markdown(add_user_feedback)
        caption_text = f"{escaped_feedback}\n"
        link_to_generate_qr_for = None

        if normal_sub_link:
            link_to_generate_qr_for = normal_sub_link
            caption_text += f"\n*Normal Subscription Link*:\n`{normal_sub_link}`"
        elif direct_uri:
            link_to_generate_qr_for = direct_uri
            caption_text += f"\n*Hysteria2 IPv4 URI*:\n`{direct_uri}`"
        
        if link_to_generate_qr_for:
            qr_img = qrcode.make(link_to_generate_qr_for)
            bio = io.BytesIO()
            qr_img.save(bio, 'PNG')
            bio.seek(0)
            bot.send_photo(message.chat.id, photo=bio, caption=caption_text, parse_mode="Markdown", reply_markup=create_main_markup())
        else:
            caption_text += "\nCould not retrieve Hysteria2 URI or Subscription link."
            bot.send_message(message.chat.id, caption_text, parse_mode="Markdown", reply_markup=create_main_markup())

    except ValueError:
        bot.reply_to(message, "Invalid expiration days. Please enter a number:", reply_markup=create_cancel_markup(back_step=process_add_user_step2))
        bot.register_next_step_handler(message, process_add_user_step3, username, traffic_limit)
    except Exception as e:
        bot.reply_to(message, f"An unexpected error occurred: {str(e)}", reply_markup=create_main_markup())