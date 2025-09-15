import qrcode
import io
import json
from telebot import types
from utils.command import *
from utils.common import *


def escape_markdown(text):
    return str(text).replace('_', '\\_').replace('*', '\\*').replace('`', '\\`')

@bot.callback_query_handler(func=lambda call: call.data == "cancel_show_user")
def handle_cancel_show_user(call):
    bot.edit_message_text("Operation canceled.", chat_id=call.message.chat.id, message_id=call.message.message_id)
    create_main_markup(call.message)

@bot.message_handler(func=lambda message: is_admin(message.from_user.id) and message.text == '🔍 Show User')
def show_user(message):
    markup = types.InlineKeyboardMarkup()
    cancel_button = types.InlineKeyboardButton("❌ Cancel", callback_data="cancel_show_user")
    markup.add(cancel_button)
    
    msg = bot.reply_to(message, "Enter username:", reply_markup=markup)
    bot.register_next_step_handler(msg, process_show_user)

def process_show_user(message):
    username_input = message.text.strip().lower()
    bot.send_chat_action(message.chat.id, 'typing')
    command = f"python3 {CLI_PATH} list-users"
    result = run_cli_command(command)

    try:
        users_list = json.loads(result)
        existing_users = {user['username'].lower(): user['username'] for user in users_list}

        if username_input not in existing_users:
            bot.reply_to(message, f"Username '{escape_markdown(message.text.strip())}' does not exist. Please enter a valid username.")
            return

        actual_username = existing_users[username_input]
    except (json.JSONDecodeError, KeyError):
        bot.reply_to(message, "Error retrieving or parsing user list. Please try again later.")
        return

    command = f"python3 {CLI_PATH} get-user -u \"{actual_username}\""
    user_result = run_cli_command(command)

    try:
        user_details = json.loads(user_result)
        
        upload_bytes = user_details.get('upload_bytes')
        download_bytes = user_details.get('download_bytes')
        status = user_details.get('status', 'Unknown')

        if upload_bytes is None or download_bytes is None:
            traffic_message = "*Traffic Data:*\nUser not active or no traffic data available."
        else:
            upload_gb = upload_bytes / (1024 ** 3)
            download_gb = download_bytes / (1024 ** 3)
            totalusage = upload_gb + download_gb
            
            traffic_message = (
                f"🔼 Upload: {upload_gb:.2f} GB\n"
                f"🔽 Download: {download_gb:.2f} GB\n"
                f"📊 Total Usage: {totalusage:.2f} GB\n"
                f"🌐 Status: {status}"
            )
    except json.JSONDecodeError:
        bot.reply_to(message, "Failed to parse user details. The command output may be malformed.")
        return

    display_username = escape_markdown(actual_username)

    formatted_details = (
        f"\n🆔 Name: {display_username}\n"
        f"📊 Traffic Limit: {user_details.get('max_download_bytes', 0) / (1024 ** 3):.2f} GB\n"
        f"📅 Days: {user_details.get('expiration_days', 'N/A')}\n"
        f"⏳ Creation: {user_details.get('account_creation_date', 'N/A')}\n"
        f"💡 Blocked: {user_details.get('blocked', 'N/A')}\n\n"
        f"{traffic_message}"
    )

    combined_command = f"python3 {CLI_PATH} show-user-uri -u \"{actual_username}\" -ip 4 -s -n"
    combined_result = run_cli_command(combined_command)

    uri_v4 = ""
    normal_sub_link = ""

    lines = combined_result.strip().split('\n')
    for i, line in enumerate(lines):
        if line.strip() == "IPv4:":
            if i + 1 < len(lines) and lines[i+1].strip().startswith("hy2://"):
                uri_v4 = lines[i+1].strip()
        elif line.strip() == "Normal-SUB Sublink:":
            if i + 1 < len(lines) and (lines[i+1].strip().startswith("http://") or lines[i+1].strip().startswith("https://")):
                normal_sub_link = lines[i+1].strip()

    qr_link = normal_sub_link if normal_sub_link else uri_v4
    if not qr_link:
        bot.reply_to(message, "No valid URI or Subscription link found for this user.")
        return
        
    qr_img = qrcode.make(qr_link)
    bio = io.BytesIO()
    qr_img.save(bio, 'PNG')
    bio.seek(0)
    
    markup = types.InlineKeyboardMarkup(row_width=3)
    markup.add(types.InlineKeyboardButton("🔄 Reset User", callback_data=f"reset_user:{actual_username}"),
               types.InlineKeyboardButton("🌐 IPv6-URI", callback_data=f"ipv6_uri:{actual_username}"))
    markup.add(types.InlineKeyboardButton("✏️ Edit Username", callback_data=f"edit_username:{actual_username}"),
               types.InlineKeyboardButton("📶 Edit Traffic", callback_data=f"edit_traffic:{actual_username}"))
    markup.add(types.InlineKeyboardButton("📅 Edit Expiration", callback_data=f"edit_expiration:{actual_username}"),
               types.InlineKeyboardButton("🔑 Renew Password", callback_data=f"renew_password:{actual_username}"))
    markup.add(types.InlineKeyboardButton("🕒 Renew Creation Date", callback_data=f"renew_creation:{actual_username}"),
               types.InlineKeyboardButton("⛔ Block User", callback_data=f"block_user:{actual_username}"))

    caption = formatted_details
    if uri_v4:
        caption += f"\n\n*IPv4 URI:*\n`{uri_v4}`"
    if normal_sub_link:
        caption += f"\n\n*Normal SUB:*\n`{normal_sub_link}`"

    bot.send_photo(
        message.chat.id,
        bio,
        caption=caption,
        reply_markup=markup,
        parse_mode="Markdown"
    )

@bot.callback_query_handler(func=lambda call: call.data.startswith('edit_') or call.data.startswith('renew_') or call.data.startswith('block_') or call.data.startswith('reset_') or call.data.startswith('ipv6_'))
def handle_edit_callback(call):
    action, username = call.data.split(':')
    display_username = escape_markdown(username)

    if action == 'edit_username':
        msg = bot.send_message(call.message.chat.id, f"Enter new username for {display_username}:")
        bot.register_next_step_handler(msg, process_edit_username, username)
    elif action == 'edit_traffic':
        msg = bot.send_message(call.message.chat.id, f"Enter new traffic limit (GB) for {display_username}:")
        bot.register_next_step_handler(msg, process_edit_traffic, username)
    elif action == 'edit_expiration':
        msg = bot.send_message(call.message.chat.id, f"Enter new expiration days for {display_username}:")
        bot.register_next_step_handler(msg, process_edit_expiration, username)
    elif action == 'renew_password':
        command = f"python3 {CLI_PATH} edit-user -u \"{username}\" -rp"
        result = run_cli_command(command)
        bot.send_message(call.message.chat.id, result)
    elif action == 'renew_creation':
        command = f"python3 {CLI_PATH} edit-user -u \"{username}\" -rc"
        result = run_cli_command(command)
        bot.send_message(call.message.chat.id, result)
    elif action == 'block_user':
        markup = types.InlineKeyboardMarkup()
        markup.add(types.InlineKeyboardButton("True", callback_data=f"confirm_block:{username}:true"),
                   types.InlineKeyboardButton("False", callback_data=f"confirm_block:{username}:false"))
        bot.send_message(call.message.chat.id, f"Set block status for {display_username}:", reply_markup=markup)
    elif action == 'reset_user':
        command = f"python3 {CLI_PATH} reset-user -u \"{username}\""
        result = run_cli_command(command)
        bot.send_message(call.message.chat.id, result)
    elif action == 'ipv6_uri':
        command = f"python3 {CLI_PATH} show-user-uri -u \"{username}\" -ip 6"
        result = run_cli_command(command)
        if "Error" in result or "Invalid" in result:
            bot.send_message(call.message.chat.id, result)
            return
        
        uri_v6 = result.split('\n')[-1].strip()
        qr_v6 = qrcode.make(uri_v6)
        bio_v6 = io.BytesIO()
        qr_v6.save(bio_v6, 'PNG')
        bio_v6.seek(0)
        
        bot.send_photo(
            call.message.chat.id,
            bio_v6,
            caption=f"**IPv6 URI for {display_username}:**\n\n`{uri_v6}`",
            parse_mode="Markdown"
        )

@bot.callback_query_handler(func=lambda call: call.data.startswith('confirm_block:'))
def handle_block_confirmation(call):
    _, username, block_status = call.data.split(':')
    flag = '-b' if block_status == 'true' else '--unblocked'
    command = f"python3 {CLI_PATH} edit-user -u \"{username}\" {flag}"
    result = run_cli_command(command)
    bot.send_message(call.message.chat.id, result)

def process_edit_username(message, username):
    new_username = message.text.strip()
    command = f"python3 {CLI_PATH} edit-user -u \"{username}\" -nu \"{new_username}\""
    result = run_cli_command(command)
    bot.reply_to(message, result)

def process_edit_traffic(message, username):
    try:
        new_traffic_limit = int(message.text.strip())
        command = f"python3 {CLI_PATH} edit-user -u \"{username}\" -nt {new_traffic_limit}"
        result = run_cli_command(command)
        bot.reply_to(message, result)
    except ValueError:
        bot.reply_to(message, "Invalid traffic limit. Please enter a number.")

def process_edit_expiration(message, username):
    try:
        new_expiration_days = int(message.text.strip())
        command = f"python3 {CLI_PATH} edit-user -u \"{username}\" -ne {new_expiration_days}"
        result = run_cli_command(command)
        bot.reply_to(message, result)
    except ValueError:
        bot.reply_to(message, "Invalid expiration days. Please enter a number.")