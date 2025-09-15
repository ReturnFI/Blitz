import os
import subprocess
from enum import Enum
from datetime import datetime
import json
from typing import Any, Optional
from dotenv import dotenv_values

import traffic

DEBUG = False
SCRIPT_DIR = '/etc/hysteria/core/scripts'
CONFIG_FILE = '/etc/hysteria/config.json'
CONFIG_ENV_FILE = '/etc/hysteria/.configs.env'
WEBPANEL_ENV_FILE = '/etc/hysteria/core/scripts/webpanel/.env'
NORMALSUB_ENV_FILE = '/etc/hysteria/core/scripts/normalsub/.env'
NODES_JSON_PATH = "/etc/hysteria/nodes.json"


class Command(Enum):
    '''Contains path to command's script'''
    INSTALL_HYSTERIA2 = os.path.join(SCRIPT_DIR, 'hysteria2', 'install.sh')
    UNINSTALL_HYSTERIA2 = os.path.join(SCRIPT_DIR, 'hysteria2', 'uninstall.py')
    UPDATE_HYSTERIA2 = os.path.join(SCRIPT_DIR, 'hysteria2', 'update.py')
    RESTART_HYSTERIA2 = os.path.join(SCRIPT_DIR, 'hysteria2', 'restart.py')
    CHANGE_PORT_HYSTERIA2 = os.path.join(SCRIPT_DIR, 'hysteria2', 'change_port.py')
    CHANGE_SNI_HYSTERIA2 = os.path.join(SCRIPT_DIR, 'hysteria2', 'change_sni.py')
    GET_USER = os.path.join(SCRIPT_DIR, 'hysteria2', 'get_user.py')
    ADD_USER = os.path.join(SCRIPT_DIR, 'hysteria2', 'add_user.py')
    BULK_USER = os.path.join(SCRIPT_DIR, 'hysteria2', 'bulk_users.py')
    EDIT_USER = os.path.join(SCRIPT_DIR, 'hysteria2', 'edit_user.py')
    RESET_USER = os.path.join(SCRIPT_DIR, 'hysteria2', 'reset_user.py')
    REMOVE_USER = os.path.join(SCRIPT_DIR, 'hysteria2', 'remove_user.py')
    SHOW_USER_URI = os.path.join(SCRIPT_DIR, 'hysteria2', 'show_user_uri.py')
    WRAPPER_URI = os.path.join(SCRIPT_DIR, 'hysteria2', 'wrapper_uri.py')
    IP_ADD = os.path.join(SCRIPT_DIR, 'hysteria2', 'ip.py')
    NODE_MANAGER = os.path.join(SCRIPT_DIR, 'hysteria2', 'node.py')
    MANAGE_OBFS = os.path.join(SCRIPT_DIR, 'hysteria2', 'manage_obfs.py')
    MASQUERADE_SCRIPT = os.path.join(SCRIPT_DIR, 'hysteria2', 'masquerade.py')
    EXTRA_CONFIG_SCRIPT = os.path.join(SCRIPT_DIR, 'hysteria2', 'extra_config.py')
    TRAFFIC_STATUS = 'traffic.py'  # won't be called directly (it's a python module)
    UPDATE_GEO = os.path.join(SCRIPT_DIR, 'hysteria2', 'update_geo.py')
    LIST_USERS = os.path.join(SCRIPT_DIR, 'hysteria2', 'list_users.py')
    SERVER_INFO = os.path.join(SCRIPT_DIR, 'hysteria2', 'server_info.py')
    BACKUP_HYSTERIA2 = os.path.join(SCRIPT_DIR, 'hysteria2', 'backup.py')
    RESTORE_HYSTERIA2 = os.path.join(SCRIPT_DIR, 'hysteria2', 'restore.py')
    INSTALL_TELEGRAMBOT = os.path.join(SCRIPT_DIR, 'telegrambot', 'runbot.py')
    SHELL_SINGBOX = os.path.join(SCRIPT_DIR, 'singbox', 'singbox_shell.sh')
    SHELL_WEBPANEL = os.path.join(SCRIPT_DIR, 'webpanel', 'webpanel_shell.sh')
    INSTALL_NORMALSUB = os.path.join(SCRIPT_DIR, 'normalsub', 'normalsub.sh')
    INSTALL_TCP_BRUTAL = os.path.join(SCRIPT_DIR, 'tcp-brutal', 'install.py')
    INSTALL_WARP = os.path.join(SCRIPT_DIR, 'warp', 'install.py')
    UNINSTALL_WARP = os.path.join(SCRIPT_DIR, 'warp', 'uninstall.py')
    CONFIGURE_WARP = os.path.join(SCRIPT_DIR, 'warp', 'configure.py')
    STATUS_WARP = os.path.join(SCRIPT_DIR, 'warp', 'status.py')
    SERVICES_STATUS = os.path.join(SCRIPT_DIR, 'services_status.sh')
    VERSION = os.path.join(SCRIPT_DIR, 'hysteria2', 'version.py')
    LIMIT_SCRIPT = os.path.join(SCRIPT_DIR, 'hysteria2', 'limit.sh')
    KICK_USER_SCRIPT = os.path.join(SCRIPT_DIR, 'hysteria2', 'kickuser.py')


# region Custom Exceptions


class HysteriaError(Exception):
    '''Base class for Hysteria-related exceptions.'''
    pass


class CommandExecutionError(HysteriaError):
    '''Raised when a command execution fails.'''
    pass


class InvalidInputError(HysteriaError):
    '''Raised when the provided input is invalid.'''
    pass


class PasswordGenerationError(HysteriaError):
    '''Raised when password generation fails.'''
    pass


class ScriptNotFoundError(HysteriaError):
    '''Raised when a required script is not found.'''
    pass

# region Utils


def run_cmd(command: list[str]) -> str:
    '''
    Runs a command and returns its stdout if successful.
    Raises CommandExecutionError if the command fails (non-zero exit code) or cannot be found.
    '''
    if DEBUG:
        print(f"Executing command: {' '.join(command)}")
    try:
        process = subprocess.run(command, capture_output=True, text=True, shell=False, check=False)

        if process.returncode != 0:
            error_output = process.stderr.strip() if process.stderr.strip() else process.stdout.strip()
            if not error_output:
                error_output = f"Command exited with status {process.returncode} without specific error message."
            
            detailed_error_message = f"Command '{' '.join(command)}' failed with exit code {process.returncode}: {error_output}"
            raise CommandExecutionError(detailed_error_message)

        return process.stdout.strip() if process.stdout else ""

    except FileNotFoundError as e:
        raise ScriptNotFoundError(f"Script or command not found: {command[0]}. Original error: {e}")
    except subprocess.TimeoutExpired as e: 
        raise CommandExecutionError(f"Command '{' '.join(command)}' timed out. Original error: {e}")
    except OSError as e: 
        raise CommandExecutionError(f"OS error while trying to run command '{' '.join(command)}': {e}")


def generate_password() -> str:
    '''
    Generates a random password using pwgen for user.
    Could raise subprocess.CalledProcessError
    '''
    try:
        return subprocess.check_output(['pwgen', '-s', '32', '1'], shell=False).decode().strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        try:
            return subprocess.check_output(['cat', '/proc/sys/kernel/random/uuid'], shell=False).decode().strip()
        except Exception as e:
            raise PasswordGenerationError(f"Failed to generate password: {e}")

# endregion

# region APIs

# region Hysteria


def install_hysteria2(port: int, sni: str):
    '''
    Installs Hysteria2 on the given port and uses the provided or default SNI value.
    '''
    run_cmd(['bash', Command.INSTALL_HYSTERIA2.value, str(port), sni])


def uninstall_hysteria2():
    '''Uninstalls Hysteria2.'''
    run_cmd(['python3', Command.UNINSTALL_HYSTERIA2.value])


def update_hysteria2():
    '''Updates Hysteria2.'''
    run_cmd(['python3', Command.UPDATE_HYSTERIA2.value])


def restart_hysteria2():
    '''Restarts Hysteria2.'''
    run_cmd(['python3', Command.RESTART_HYSTERIA2.value])


def get_hysteria2_port() -> int | None:
    '''
    Retrieves the port for Hysteria2.
    '''
    # read json config file and return port, example valaue of 'listen' field: '127.0.0.1:8080'
    config = get_hysteria2_config_file()
    port = config['listen'].split(':')
    if len(port) > 1:
        return int(port[1])
    return None


def change_hysteria2_port(port: int):
    '''
    Changes the port for Hysteria2.
    '''
    run_cmd(['python3', Command.CHANGE_PORT_HYSTERIA2.value, str(port)])


def get_hysteria2_sni() -> str | None:
    '''
    Retrieves the SNI for Hysteria2.
    '''
    env_vars = dotenv_values(CONFIG_ENV_FILE)
    return env_vars.get('SNI')


def change_hysteria2_sni(sni: str):
    '''
    Changes the SNI for Hysteria2.
    '''
    run_cmd(['python3', Command.CHANGE_SNI_HYSTERIA2.value, sni])


def backup_hysteria2():
    '''Backups Hysteria configuration.  Raises an exception on failure.'''
    try:
        run_cmd(['python3', Command.BACKUP_HYSTERIA2.value])
    except subprocess.CalledProcessError as e:
        raise Exception(f"Backup failed: {e}")
    except Exception as ex:
        raise


def restore_hysteria2(backup_file_path: str):
    '''Restores Hysteria configuration from the given backup file.'''
    try:
        run_cmd(['python3', Command.RESTORE_HYSTERIA2.value, backup_file_path])
    except subprocess.CalledProcessError as e:
        raise Exception(f"Restore failed: {e}")
    except Exception as ex:
        raise


def enable_hysteria2_obfs():
    '''Generates 'obfs' in Hysteria2 configuration.'''
    run_cmd(['python3', Command.MANAGE_OBFS.value, '--generate'])


def disable_hysteria2_obfs():
    '''Removes 'obfs' from Hysteria2 configuration.'''
    run_cmd(['python3', Command.MANAGE_OBFS.value, '--remove'])

def check_hysteria2_obfs():
    '''Removes 'obfs' from Hysteria2 configuration.'''
    result = subprocess.run(["python3", Command.MANAGE_OBFS.value, "--check"], check=True, capture_output=True, text=True)
    return result.stdout.strip()

def enable_hysteria2_masquerade(domain: str):
    '''Enables masquerade for Hysteria2.'''
    run_cmd(['python3', Command.MASQUERADE_SCRIPT.value, '1', domain])


def disable_hysteria2_masquerade():
    '''Disables masquerade for Hysteria2.'''
    run_cmd(['python3', Command.MASQUERADE_SCRIPT.value, '2'])


def get_hysteria2_config_file() -> dict[str, Any]:
    with open(CONFIG_FILE, 'r') as f:
        return json.loads(f.read())


def set_hysteria2_config_file(data: dict[str, Any]):
    content = json.dumps(data, indent=4)

    with open(CONFIG_FILE, 'w') as f:
        f.write(content)
# endregion

# region User


def list_users() -> dict[str, dict[str, Any]] | None:
    '''
    Lists all users.
    '''
    if res := run_cmd(['python3', Command.LIST_USERS.value]):
        return json.loads(res)


def get_user(username: str) -> dict[str, Any] | None:
    '''
    Retrieves information about a specific user.
    '''
    if res := run_cmd(['python3', Command.GET_USER.value, '-u', str(username)]):
        return json.loads(res)


def add_user(username: str, traffic_limit: int, expiration_days: int, password: str | None, creation_date: str | None, unlimited: bool):
    '''
    Adds a new user with the given parameters, respecting positional argument requirements.
    '''
    command = ['python3', Command.ADD_USER.value, username, str(traffic_limit), str(expiration_days)]

    if unlimited:
        final_password = password if password else generate_password()
        final_creation_date = creation_date if creation_date else datetime.now().strftime('%Y-%m-%d')
        command.extend([final_password, final_creation_date, 'true'])
    elif creation_date:
        final_password = password if password else generate_password()
        command.extend([final_password, creation_date])
    elif password:
        command.append(password)
        
    run_cmd(command)

def bulk_user_add(traffic_gb: float, expiration_days: int, count: int, prefix: str, start_number: int, unlimited: bool):
    """
    Executes the bulk user creation script with specified parameters.
    """
    command = [
        'python3', 
        Command.BULK_USER.value,
        '--traffic-gb', str(traffic_gb),
        '--expiration-days', str(expiration_days),
        '--count', str(count),
        '--prefix', prefix,
        '--start-number', str(start_number)
    ]

    if unlimited:
        command.append('--unlimited')
        
    run_cmd(command)

def edit_user(username: str, new_username: str | None, new_traffic_limit: int | None, new_expiration_days: int | None, renew_password: bool, renew_creation_date: bool, blocked: bool | None, unlimited_ip: bool | None):
    '''
    Edits an existing user's details by calling the new edit_user.py script with named flags.
    '''
    if not username:
        raise InvalidInputError('Error: username is required')

    command_args = ['python3', Command.EDIT_USER.value, username]

    if new_username:
        command_args.extend(['--new-username', new_username])

    if new_traffic_limit is not None:
        if new_traffic_limit < 0:
            raise InvalidInputError('Error: traffic limit must be a non-negative number.')
        command_args.extend(['--traffic-gb', str(new_traffic_limit)])

    if new_expiration_days is not None:
        if new_expiration_days < 0:
            raise InvalidInputError('Error: expiration days must be a non-negative number.')
        command_args.extend(['--expiration-days', str(new_expiration_days)])
        
    if renew_password:
        password = generate_password()
        command_args.extend(['--password', password])
        
    if renew_creation_date:
        creation_date = datetime.now().strftime('%Y-%m-%d')
        command_args.extend(['--creation-date', creation_date])
        
    if blocked is not None:
        command_args.extend(['--blocked', 'true' if blocked else 'false'])
        
    if unlimited_ip is not None:
        command_args.extend(['--unlimited', 'true' if unlimited_ip else 'false'])

    run_cmd(command_args)


def reset_user(username: str):
    '''
    Resets a user's configuration.
    '''
    run_cmd(['python3', Command.RESET_USER.value, username])


def remove_users(usernames: list[str]):
    '''
    Removes one or more users by username.
    '''
    if not usernames:
        return
    run_cmd(['python3', Command.REMOVE_USER.value, *usernames])

def kick_users_by_name(usernames: list[str]):
    '''Kicks one or more users by username.'''
    if not usernames:
        raise InvalidInputError('Username(s) must be provided to kick.')
    script_path = Command.KICK_USER_SCRIPT.value
    if not os.path.exists(script_path):
        raise ScriptNotFoundError(f"Kick user script not found at: {script_path}")
    try:
        subprocess.run(['python3', script_path, *usernames], check=True)
    except subprocess.CalledProcessError as e:
        raise CommandExecutionError(f"Failed to execute kick user script: {e}")
        
# TODO: it's better to return json
def show_user_uri(username: str, qrcode: bool, ipv: int, all: bool, singbox: bool, normalsub: bool) -> str | None:
    '''
    Displays the URI for a user, with options for QR code and other formats.
    '''
    command_args = ['python3', Command.SHOW_USER_URI.value, '-u', username]
    if qrcode:
        command_args.append('-qr')
    if all:
        command_args.append('-a')
    else:
        command_args.extend(['-ip', str(ipv)])
    if singbox:
        command_args.append('-s')
    if normalsub:
        command_args.append('-n')
    return run_cmd(command_args)

def show_user_uri_json(usernames: list[str]) -> list[dict[str, Any]] | None:
    '''
    Displays the URI for a list of users in JSON format.
    '''
    script_path = Command.WRAPPER_URI.value
    if not os.path.exists(script_path):
        raise ScriptNotFoundError(f"Wrapper URI script not found at: {script_path}")
    try:
        process = subprocess.run(['python3', script_path, *usernames], capture_output=True, text=True, check=True)
        return json.loads(process.stdout)
    except subprocess.CalledProcessError as e:
        raise CommandExecutionError(f"Failed to execute wrapper URI script: {e}\nError: {e.stderr}")
    except FileNotFoundError:
        raise ScriptNotFoundError(f'Script not found: {script_path}')
    except json.JSONDecodeError:
        raise CommandExecutionError(f"Failed to decode JSON output from script: {script_path}\nOutput: {process.stdout if 'process' in locals() else 'No output'}") # Add process check
    except Exception as e:
        raise HysteriaError(f'An unexpected error occurred: {e}')
        
# endregion

# region Server


def traffic_status(no_gui=False, display_output=True):
    if no_gui:
        data = traffic.traffic_status(no_gui=True)
        traffic.kick_expired_users()
    else:
        data = traffic.traffic_status(no_gui=True if not display_output else no_gui)
    
    return data


# Next Update:
# TODO: it's better to return json
# TODO: After json todo need fix Telegram Bot and WebPanel
def server_info() -> str | None:
    '''Retrieves server information.'''
    return run_cmd(['python3', Command.SERVER_INFO.value])


def get_ip_address() -> tuple[str | None, str | None]:
    '''
    Retrieves the IP address from the .configs.env file.
    '''
    env_vars = dotenv_values(CONFIG_ENV_FILE)

    return env_vars.get('IP4'), env_vars.get('IP6')


def add_ip_address():
    '''
    Adds IP addresses from the environment to the .configs.env file.
    '''
    run_cmd(['python3', Command.IP_ADD.value, 'add'])


def edit_ip_address(ipv4: str, ipv6: str):
    '''
    Edits the IP address configuration based on provided IPv4 and/or IPv6 addresses.

    :param ipv4: The new IPv4 address to be configured. If provided, the IPv4 address will be updated.
    :param ipv6: The new IPv6 address to be configured. If provided, the IPv6 address will be updated.
    :raises InvalidInputError: If neither ipv4 nor ipv6 is provided.
    '''

    if not ipv4 and not ipv6:
        raise InvalidInputError('Error: --edit requires at least one of --ipv4 or --ipv6.')
    if ipv4:
        run_cmd(['python3', Command.IP_ADD.value, 'edit', '-4', ipv4])
    if ipv6:
        run_cmd(['python3', Command.IP_ADD.value, 'edit', '-6', ipv6])

def add_node(name: str, ip: str):
    """
    Adds a new external node.
    """
    return run_cmd(['python3', Command.NODE_MANAGER.value, 'add', '--name', name, '--ip', ip])

def delete_node(name: str):
    """
    Deletes an external node by name.
    """
    return run_cmd(['python3', Command.NODE_MANAGER.value, 'delete', '--name', name])

def list_nodes():
    """
    Lists all configured external nodes.
    """
    return run_cmd(['python3', Command.NODE_MANAGER.value, 'list'])

def update_geo(country: str):
    '''
    Updates geographic data files based on the specified country.
    '''
    script_path = Command.UPDATE_GEO.value
    try:
        subprocess.run(['python3', script_path, country.lower()], check=True)
    except subprocess.CalledProcessError as e:
        raise CommandExecutionError(f'Failed to update geo files: {e}')
    except FileNotFoundError:
        raise ScriptNotFoundError(f'Script not found: {script_path}')
    except Exception as e:
        raise HysteriaError(f'An unexpected error occurred: {e}')

def add_extra_config(name: str, uri: str) -> str:
    """Adds an extra proxy configuration."""
    return run_cmd(['python3', Command.EXTRA_CONFIG_SCRIPT.value, 'add', '--name', name, '--uri', uri])


def delete_extra_config(name: str) -> str:
    """Deletes an extra proxy configuration."""
    return run_cmd(['python3', Command.EXTRA_CONFIG_SCRIPT.value, 'delete', '--name', name])


def list_extra_configs() -> str:
    """Lists all extra proxy configurations."""
    return run_cmd(['python3', Command.EXTRA_CONFIG_SCRIPT.value, 'list'])


def get_extra_config(name: str) -> dict[str, Any] | None:
    """Gets a specific extra proxy configuration."""
    if res := run_cmd(['python3', Command.EXTRA_CONFIG_SCRIPT.value, 'get', '--name', name]):
        return json.loads(res)

# endregion

# region Advanced Menu


def install_tcp_brutal():
    '''Installs TCP Brutal.'''
    run_cmd(['python3', Command.INSTALL_TCP_BRUTAL.value])


def install_warp():
    '''Installs WARP.'''
    run_cmd(['python3', Command.INSTALL_WARP.value])


def uninstall_warp():
    '''Uninstalls WARP.'''
    run_cmd(['python3', Command.UNINSTALL_WARP.value])


def configure_warp(all_state: str | None = None, 
                   popular_sites_state: str | None = None, 
                   domestic_sites_state: str | None = None, 
                   block_adult_sites_state: str | None = None):
    '''
    Configures WARP with various options. States are 'on' or 'off'.
    '''
    cmd_args = [
        'python3', Command.CONFIGURE_WARP.value
    ]
    if all_state:
        cmd_args.extend(['--set-all', all_state])
    if popular_sites_state:
        cmd_args.extend(['--set-popular-sites', popular_sites_state])
    if domestic_sites_state:
        cmd_args.extend(['--set-domestic-sites', domestic_sites_state])
    if block_adult_sites_state:
        cmd_args.extend(['--set-block-adult', block_adult_sites_state])

    if len(cmd_args) == 2: 
        print("No WARP configuration options provided to cli_api.configure_warp.")
        return 

    run_cmd(cmd_args)


def warp_status() -> str | None:
    '''Checks the status of WARP.'''
    return run_cmd(['python3', Command.STATUS_WARP.value])


def start_telegram_bot(token: str, adminid: str):
    '''Starts the Telegram bot.'''
    if not token or not adminid:
        raise InvalidInputError('Error: Both --token and --adminid are required for the start action.')
    run_cmd(['python3', Command.INSTALL_TELEGRAMBOT.value, 'start', token, adminid])


def stop_telegram_bot():
    '''Stops the Telegram bot.'''
    run_cmd(['python3', Command.INSTALL_TELEGRAMBOT.value, 'stop'])


def start_singbox(domain: str, port: int):
    '''Starts Singbox.'''
    if not domain or not port:
        raise InvalidInputError('Error: Both --domain and --port are required for the start action.')
    run_cmd(['bash', Command.SHELL_SINGBOX.value, 'start', domain, str(port)])


def stop_singbox():
    '''Stops Singbox.'''
    run_cmd(['bash', Command.SHELL_SINGBOX.value, 'stop'])


def start_normalsub(domain: str, port: int):
    '''Starts NormalSub.'''
    if not domain or not port:
        raise InvalidInputError('Error: Both --domain and --port are required for the start action.')
    run_cmd(['bash', Command.INSTALL_NORMALSUB.value, 'start', domain, str(port)])

def edit_normalsub_subpath(new_subpath: str):
    '''Edits the subpath for NormalSub service.'''
    if not new_subpath:
        raise InvalidInputError('Error: New subpath cannot be empty.')
    if not new_subpath.isalnum():
        raise InvalidInputError('Error: New subpath must contain only alphanumeric characters (a-z, A-Z, 0-9).')
    
    run_cmd(['bash', Command.INSTALL_NORMALSUB.value, 'edit_subpath', new_subpath])

def get_normalsub_subpath() -> str | None:
    '''Retrieves the current SUBPATH for the NormalSub service from its .env file.'''
    try:
        if not os.path.exists(NORMALSUB_ENV_FILE):
            return None 
        
        env_vars = dotenv_values(NORMALSUB_ENV_FILE)
        return env_vars.get('SUBPATH')
    except Exception as e:
        print(f"Error reading NormalSub .env file: {e}")
        return None

def stop_normalsub():
    '''Stops NormalSub.'''
    run_cmd(['bash', Command.INSTALL_NORMALSUB.value, 'stop'])


def start_webpanel(domain: str, port: int, admin_username: str, admin_password: str, expiration_minutes: int, debug: bool, decoy_path: str):
    '''Starts WebPanel.'''
    if not domain or not port or not admin_username or not admin_password or not expiration_minutes:
        raise InvalidInputError('Error: Both --domain and --port are required for the start action.')
    run_cmd(
        ['bash', Command.SHELL_WEBPANEL.value, 'start',
         domain, str(port), admin_username, admin_password, str(expiration_minutes), str(debug).lower(), str(decoy_path)]
    )


def stop_webpanel():
    '''Stops WebPanel.'''
    run_cmd(['bash', Command.SHELL_WEBPANEL.value, 'stop'])

def setup_webpanel_decoy(domain: str, decoy_path: str):
    '''Sets up or updates the decoy site for the web panel.'''
    if not domain or not decoy_path:
        raise InvalidInputError('Error: Both domain and decoy_path are required.')
    run_cmd(['bash', Command.SHELL_WEBPANEL.value, 'decoy', domain, decoy_path])

def stop_webpanel_decoy():
    '''Stops and removes the decoy site configuration for the web panel.'''
    run_cmd(['bash', Command.SHELL_WEBPANEL.value, 'stopdecoy'])

def get_webpanel_decoy_status() -> dict[str, Any]:
    """Checks the status of the webpanel decoy site configuration."""
    try:
        if not os.path.exists(WEBPANEL_ENV_FILE):
            return {"active": False, "path": None}

        env_vars = dotenv_values(WEBPANEL_ENV_FILE)
        decoy_path = env_vars.get('DECOY_PATH')

        if decoy_path and decoy_path.strip():
            return {"active": True, "path": decoy_path.strip()}
        else:
            return {"active": False, "path": None}
    except Exception as e:
        print(f"Error checking decoy status: {e}")
        return {"active": False, "path": None}

def get_webpanel_url() -> str | None:
    '''Gets the URL of WebPanel.'''
    return run_cmd(['bash', Command.SHELL_WEBPANEL.value, 'url'])


def get_webpanel_api_token() -> str | None:
    '''Gets the API token of WebPanel.'''
    return run_cmd(['bash', Command.SHELL_WEBPANEL.value, 'api-token'])

def reset_webpanel_credentials(new_username: str | None = None, new_password: str | None = None):
    '''Resets the WebPanel admin username and/or password.'''
    if not new_username and not new_password:
        raise InvalidInputError('Error: At least new username or new password must be provided.')

    cmd_args = ['bash', Command.SHELL_WEBPANEL.value, 'resetcreds']
    if new_username:
        cmd_args.extend(['-u', new_username])
    if new_password:
        cmd_args.extend(['-p', new_password])
    
    run_cmd(cmd_args)

def get_services_status() -> dict[str, bool] | None:
    '''Gets the status of all project services.'''
    if res := run_cmd(['bash', Command.SERVICES_STATUS.value]):
        return json.loads(res)

def show_version() -> str | None:
    """Displays the currently installed version of the panel."""
    return run_cmd(['python3', Command.VERSION.value, 'show-version'])


def check_version() -> str | None:
    """Checks if the current version is up-to-date and displays changelog if not."""
    return run_cmd(['python3', Command.VERSION.value, 'check-version'])

def start_ip_limiter():
    '''Starts the IP limiter service.'''
    run_cmd(['bash', Command.LIMIT_SCRIPT.value, 'start'])

def stop_ip_limiter():
    '''Stops the IP limiter service.'''
    run_cmd(['bash', Command.LIMIT_SCRIPT.value, 'stop'])

def config_ip_limiter(block_duration: Optional[int] = None, max_ips: Optional[int] = None):
    '''Configures the IP limiter service.'''
    if block_duration is not None and block_duration <= 0:
        raise InvalidInputError("Block duration must be greater than 0.")
    if max_ips is not None and max_ips <= 0:
        raise InvalidInputError("Max IPs must be greater than 0.")

    cmd_args = ['bash', Command.LIMIT_SCRIPT.value, 'config']
    if block_duration is not None:
        cmd_args.append(str(block_duration))
    else:
        cmd_args.append('')

    if max_ips is not None:
        cmd_args.append(str(max_ips))
    else:
        cmd_args.append('')

    run_cmd(cmd_args)

def get_ip_limiter_config() -> dict[str, int | None]:
    '''Retrieves the current IP Limiter configuration from .configs.env.'''
    try:
        if not os.path.exists(CONFIG_ENV_FILE):
            return {"block_duration": None, "max_ips": None}
        
        env_vars = dotenv_values(CONFIG_ENV_FILE)
        block_duration_str = env_vars.get('BLOCK_DURATION')
        max_ips_str = env_vars.get('MAX_IPS')
        
        block_duration = int(block_duration_str) if block_duration_str and block_duration_str.isdigit() else None
        max_ips = int(max_ips_str) if max_ips_str and max_ips_str.isdigit() else None
            
        return {"block_duration": block_duration, "max_ips": max_ips}
    except Exception as e:
        print(f"Error reading IP Limiter config from .configs.env: {e}")
        return {"block_duration": None, "max_ips": None}
# endregion
