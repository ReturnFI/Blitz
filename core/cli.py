#!/usr/bin/env python3

import typing
import click
import cli_api
import json


def pretty_print(data: typing.Any):
    if isinstance(data, dict) or isinstance(data, list):
        print(json.dumps(data, indent=4))
        return

    print(data)


@click.group()
def cli():
    pass

# region Hysteria2


@cli.command('install-hysteria2')
@click.option('--port', '-p', required=True, help='Port for Hysteria2', type=int)
@click.option('--sni', '-s', required=False, default='bts.com', help='SNI for Hysteria2 (default: bts.com)', type=str)
def install_hysteria2(port: int, sni: str):
    try:
        cli_api.install_hysteria2(port, sni)
        click.echo(f'Hysteria2 installed successfully on port {port} with SNI {sni}.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('uninstall-hysteria2')
def uninstall_hysteria2():
    try:
        cli_api.uninstall_hysteria2()
        click.echo('Hysteria2 uninstalled successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('update-hysteria2')
def update_hysteria2():
    try:
        cli_api.update_hysteria2()
        click.echo('Hysteria2 updated successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('restart-hysteria2')
def restart_hysteria2():
    try:
        cli_api.restart_hysteria2()
        click.echo('Hysteria2 restarted successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('change-hysteria2-port')
@click.option('--port', '-p', required=True, help='New port for Hysteria2', type=int)
def change_hysteria2_port(port: int):
    try:
        cli_api.change_hysteria2_port(port)
        click.echo(f'Hysteria2 port changed to {port} successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('change-hysteria2-sni')
@click.option('--sni', '-s', required=True, help='New SNI for Hysteria2', type=str)
def change_hysteria2_sni(sni: str):
    try:
        cli_api.change_hysteria2_sni(sni)
        click.echo(f'Hysteria2 SNI changed to {sni} successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('backup-hysteria')
def backup_hysteria2():
    try:
        cli_api.backup_hysteria2()
        click.echo('Hysteria configuration backed up successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)

@cli.command('restore-hysteria2')
@click.argument('backup_file_path', type=click.Path(exists=True, file_okay=True, dir_okay=False, readable=True))
def restore_hysteria2(backup_file_path):
    """Restores Hysteria configuration from a backup ZIP file."""
    try:
        cli_api.restore_hysteria2(backup_file_path)
        click.echo('Hysteria configuration restored successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)

# endregion

# region User


@cli.command('list-users')
def list_users():
    try:
        res = cli_api.list_users()
        if res:
            pretty_print(res)
        else:
            click.echo('No users found.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('get-user')
@click.option('--username', '-u', required=True, help='Username for the user to get', type=str)
def get_user(username: str):
    try:
        if res := cli_api.get_user(username):
            pretty_print(res)
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('add-user')
@click.option('--username', '-u', required=True, help='Username for the new user', type=str)
@click.option('--traffic-limit', '-t', required=True, help='Traffic limit for the new user in GB', type=int)
@click.option('--expiration-days', '-e', required=True, help='Expiration days for the new user', type=int)
@click.option('--password', '-p', required=False, help='Password for the user', type=str)
@click.option('--creation-date', '-c', required=False, help='Creation date for the user (YYYY-MM-DD)', type=str)
@click.option('--unlimited', is_flag=True, default=False, help='Exempt user from IP limit checks.')
def add_user(username: str, traffic_limit: int, expiration_days: int, password: str, creation_date: str, unlimited: bool):
    try:
        cli_api.add_user(username, traffic_limit, expiration_days, password, creation_date, unlimited)
        click.echo(f"User '{username}' added successfully.")
    except Exception as e:
        click.echo(f'{e}', err=True)

@cli.command('bulk-user-add')
@click.option('--traffic-gb', '-t', required=True, help='Traffic limit for each user in GB.', type=float)
@click.option('--expiration-days', '-e', required=True, help='Expiration duration for each user in days.', type=int)
@click.option('--count', '-c', required=True, help='Number of users to create.', type=int)
@click.option('--prefix', '-p', required=True, help='Prefix for usernames.', type=str)
@click.option('--start-number', '-s', default=1, help='Starting number for username suffix.', type=int)
@click.option('--unlimited', is_flag=True, default=False, help='Flag to mark users as unlimited (exempt from IP limits).')
def bulk_user_add(traffic_gb: float, expiration_days: int, count: int, prefix: str, start_number: int, unlimited: bool):
    """Adds multiple users in bulk."""
    try:
        cli_api.bulk_user_add(traffic_gb, expiration_days, count, prefix, start_number, unlimited)
        click.echo(f"Successfully initiated the creation of {count} users with prefix '{prefix}'.")
    except Exception as e:
        click.echo(f'Error during bulk user addition: {e}', err=True)

@cli.command('edit-user')
@click.option('--username', '-u', required=True, help='Username for the user to edit', type=str)
@click.option('--new-username', '-nu', required=False, help='New username for the user', type=str)
@click.option('--new-traffic-limit', '-nt', required=False, help='Traffic limit for the new user in GB', type=int)
@click.option('--new-expiration-days', '-ne', required=False, help='Expiration days for the new user', type=int)
@click.option('--renew-password', '-rp', is_flag=True, help='Renew password for the user')
@click.option('--renew-creation-date', '-rc', is_flag=True, help='Renew creation date for the user')
@click.option('--blocked/--unblocked', 'blocked', '-b', default=None, help='Block or unblock the user.')
@click.option('--unlimited-ip/--limited-ip', 'unlimited_ip', default=None, help='Set user to be exempt from or subject to IP limits.')
def edit_user(username: str, new_username: str, new_traffic_limit: int, new_expiration_days: int, renew_password: bool, renew_creation_date: bool, blocked: bool | None, unlimited_ip: bool | None):
    try:
        cli_api.kick_user_by_name(username)
        cli_api.traffic_status(display_output=False)
        cli_api.edit_user(username, new_username, new_traffic_limit, new_expiration_days,
                          renew_password, renew_creation_date, blocked, unlimited_ip)
        click.echo(f"User '{username}' updated successfully.")
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('reset-user')
@click.option('--username', '-u', required=True, help='Username for the user to Reset', type=str)
def reset_user(username: str):
    try:
        cli_api.reset_user(username)
        click.echo(f"User '{username}' reset successfully.")
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('remove-user')
@click.argument('usernames', nargs=-1, required=True)
def remove_user(usernames: tuple[str]):
    """Removes one or more users."""
    if not usernames:
        click.echo("No usernames provided.", err=True)
        return
        
    try:
        usernames_list = list(usernames)
        cli_api.kick_users_by_name(usernames_list)
        cli_api.traffic_status(display_output=False)
        cli_api.remove_users(usernames_list)
        click.echo(f"Users '{', '.join(usernames)}' removed successfully.")
    except Exception as e:
        click.echo(f'{e}', err=True)

@cli.command('kick-user')
@click.argument('usernames', nargs=-1, required=True)
def kick_user(usernames: tuple[str]):
    """Kicks one or more users by username."""
    if not usernames:
        click.echo("No usernames provided.", err=True)
        return
        
    try:
        cli_api.kick_users_by_name(list(usernames))
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('show-user-uri')
@click.option('--username', '-u', required=True, help='Username for the user to show the URI', type=str)
@click.option('--qrcode', '-qr', is_flag=True, help='Generate QR code for the URI')
@click.option('--ipv', '-ip', type=click.IntRange(4, 6), default=4, help='IP version (4 or 6)')
@click.option('--all', '-a', is_flag=True, help='Show both IPv4 and IPv6 URIs and generate QR codes for both if requested')
@click.option('--singbox', '-s', is_flag=True, help='Generate Singbox sublink if Singbox service is active')
@click.option('--normalsub', '-n', is_flag=True, help='Generate Normal sublink if normalsub service is active')
def show_user_uri(username: str, qrcode: bool, ipv: int, all: bool, singbox: bool, normalsub: bool):
    try:
        res = cli_api.show_user_uri(username, qrcode, ipv, all, singbox, normalsub)
        if res:
            click.echo(res)
        else:
            click.echo(f"URI for user '{username}' could not be generated.")
    except Exception as e:
        click.echo(f'{e}', err=True)

@cli.command('show-user-uri-json')
@click.argument('usernames', nargs=-1, required=True)
def show_user_uri_json(usernames: list[str]):
    """
    Displays URI information in JSON format for a list of users.
    """
    try:
        res = cli_api.show_user_uri_json(usernames)
        if res:
            pretty_print(res)
        else:
            click.echo('No user URIs could be generated.')
    except Exception as e:
        click.echo(f'{e}', err=True)

# endregion

# region Server


@cli.command('traffic-status')
@click.option('--no-gui', is_flag=True, help='Retrieve traffic data without displaying output and kick expired users')
def traffic_status(no_gui):
    try:
        cli_api.traffic_status(no_gui=no_gui)
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('server-info')
def server_info():
    try:
        res = cli_api.server_info()
        if res:
            pretty_print(res)
        else:
            click.echo('Server information not available.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('manage_obfs')
@click.option('--remove', '-r', is_flag=True, help="Remove 'obfs' from config.json.")
@click.option('--generate', '-g', is_flag=True, help="Generate new 'obfs' in config.json.")
@click.option('--check', '-c', is_flag=True, help="Check 'obfs' status in config.json.")
def manage_obfs(remove: bool, generate: bool, check: bool):
    try:
        options_selected = sum([remove, generate, check])
        if options_selected == 0:
            raise click.UsageError('Error: You must use either --remove, --generate, or --check.')
        if options_selected > 1:
            raise click.UsageError('Error: You can only use one of --remove, --generate, or --check at a time.')

        if generate:
            cli_api.enable_hysteria2_obfs()
            click.echo('OBFS enabled successfully.')
        elif remove:
            cli_api.disable_hysteria2_obfs()
            click.echo('OBFS disabled successfully.')
        elif check:
            status_output = cli_api.check_hysteria2_obfs()
            click.echo(status_output)
            
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('ip-address')
@click.option('--edit', is_flag=True, help='Edit IP addresses manually.')
@click.option('-4', '--ipv4', type=str, help='Specify the new IPv4 address.')
@click.option('-6', '--ipv6', type=str, help='Specify the new IPv6 address.')
def ip_address(edit: bool, ipv4: str, ipv6: str):
    '''
    Manage IP addresses in .configs.env.
    - Use without options to add auto-detected IPs.
    - Use --edit with -4 or -6 to manually update IPs.
    '''
    try:
        if not edit:
            cli_api.add_ip_address()
            click.echo('IP addresses added successfully.')
            return

        if not ipv4 and not ipv6:
            raise click.UsageError('Error: You must specify either -4 or -6')

        cli_api.edit_ip_address(ipv4, ipv6)
        click.echo('IP address configuration updated successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.group()
def node():
    """Manage external node IPs for multi-server setups."""
    pass

@node.command('add')
@click.option('--name', required=True, type=str, help='A unique name for the node (e.g., "Node-DE").')
@click.option('--ip', required=True, type=str, help='The public IP address of the node.')
def add_node(name, ip):
    """Add a new external node."""
    try:
        output = cli_api.add_node(name, ip)
        click.echo(output.strip())
    except Exception as e:
        click.echo(f'{e}', err=True)

@node.command('delete')
@click.option('--name', required=True, type=str, help='The name of the node to delete.')
def delete_node(name):
    """Delete an external node by its name."""
    try:
        output = cli_api.delete_node(name)
        click.echo(output.strip())
    except Exception as e:
        click.echo(f'{e}', err=True)

@node.command('list')
def list_nodes():
    """List all configured external nodes."""
    try:
        output = cli_api.list_nodes()
        click.echo(output.strip())
    except Exception as e:
        click.echo(f'{e}', err=True)

@cli.command('update-geo')
@click.option('--country', '-c',
              type=click.Choice(['iran', 'china', 'russia'], case_sensitive=False),
              default='iran',
              help='Select country for geo files (default: iran)')
def update_geo(country: str):
    try:
        cli_api.update_geo(country)
        click.echo(f'Geo files for {country} updated successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('masquerade')
@click.option('--remove', '-r', is_flag=True, help="Remove 'masquerade' from config.json.")
@click.option('--enable', '-e', metavar='<domain>', type=str, help="Enable 'masquerade' in config.json with the specified domain.")
def masquerade(remove: bool, enable: str):
    '''Manage 'masquerade' in Hysteria2 configuration.'''
    try:
        if not remove and not enable:
            raise click.UsageError('Error: You must use either --remove or --enable')
        if remove and enable:
            raise click.UsageError('Error: You cannot use both --remove and --enable at the same time')

        if enable:
            cli_api.enable_hysteria2_masquerade(enable)
            click.echo('Masquerade enabled successfully.')
        elif remove:
            cli_api.disable_hysteria2_masquerade()
            click.echo('Masquerade disabled successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)

@cli.group('extra-config')
def extra_config():
    """Manage extra proxy configurations for subscription links."""
    pass


@extra_config.command('add')
@click.option('--name', required=True, help='A unique name for the configuration.')
@click.option('--uri', required=True, help='The proxy URI (vmess, vless, ss, trojan).')
def add_extra_config(name: str, uri: str):
    """Add a new extra proxy configuration."""
    try:
        output = cli_api.add_extra_config(name, uri)
        click.echo(output)
    except Exception as e:
        click.echo(f'{e}', err=True)


@extra_config.command('delete')
@click.option('--name', required=True, help='The name of the configuration to delete.')
def delete_extra_config(name: str):
    """Delete an extra proxy configuration."""
    try:
        output = cli_api.delete_extra_config(name)
        click.echo(output)
    except Exception as e:
        click.echo(f'{e}', err=True)


@extra_config.command('list')
def list_extra_configs():
    """List all extra proxy configurations."""
    try:
        output = cli_api.list_extra_configs()
        click.echo(output)
    except Exception as e:
        click.echo(f'{e}', err=True)


@extra_config.command('get')
@click.option('--name', required=True, help='The name of the configuration to retrieve.')
def get_extra_config(name: str):
    """Get a specific extra proxy configuration."""
    try:
        res = cli_api.get_extra_config(name)
        if res:
            pretty_print(res)
    except Exception as e:
        click.echo(f'{e}', err=True)

# endregion

# region Advanced Menu


@cli.command('install-tcp-brutal')
def install_tcp_brutal():
    try:
        cli_api.install_tcp_brutal()
        click.echo('TCP Brutal installed successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('install-warp')
def install_warp():
    try:
        cli_api.install_warp()
        click.echo('WARP installed successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('uninstall-warp')
def uninstall_warp():
    try:
        cli_api.uninstall_warp()
        click.echo('WARP uninstalled successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('configure-warp')
@click.option('--set-all', 'set_all_traffic', type=click.Choice(['on', 'off']), help='Set WARP for all connections (on/off)', required=False)
@click.option('--set-popular-sites', type=click.Choice(['on', 'off']), help='Set WARP for popular sites (on/off)', required=False)
@click.option('--set-domestic-sites', type=click.Choice(['on', 'off']), help='Set behavior for domestic sites (on=WARP, off=REJECT)', required=False)
@click.option('--set-block-adult-sites', type=click.Choice(['on', 'off']), help='Set block adult content (on/off)', required=False)
def configure_warp_cmd(set_all_traffic: str | None, 
                       set_popular_sites: str | None, 
                       set_domestic_sites: str | None, 
                       set_block_adult_sites: str | None):
    if not any([set_all_traffic, set_popular_sites, set_domestic_sites, set_block_adult_sites]):
        click.echo("Error: At least one configuration option must be provided to configure-warp.", err=True)
        click.echo("Use --help for more information.")
        return

    try:
        cli_api.configure_warp(
            all_state=set_all_traffic, 
            popular_sites_state=set_popular_sites, 
            domestic_sites_state=set_domestic_sites, 
            block_adult_sites_state=set_block_adult_sites
        )
        click.echo('WARP configuration update process initiated.')
    except Exception as e:
        click.echo(f'Error configuring WARP: {e}', err=True)

@cli.command('warp-status')
def warp_status():
    try:
        res = cli_api.warp_status()
        if res:
            pretty_print(res)
        else:
            click.echo('WARP status not available.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('telegram')
@click.option('--action', '-a', required=True, help='Action to perform: start or stop', type=click.Choice(['start', 'stop'], case_sensitive=False))
@click.option('--token', '-t', required=False, help='Token for running the telegram bot', type=str)
@click.option('--adminid', '-aid', required=False, help='Telegram admins ID for running the telegram bot', type=str)
def telegram(action: str, token: str, adminid: str):
    try:
        if action == 'start':
            if not token or not adminid:
                raise click.UsageError('Error: Both --token and --adminid are required for the start action.')
            cli_api.start_telegram_bot(token, adminid)
            click.echo(f'Telegram bot started successfully.')
        elif action == 'stop':
            cli_api.stop_telegram_bot()
            click.echo(f'Telegram bot stopped successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('singbox')
@click.option('--action', '-a', required=True, help='Action to perform: start or stop', type=click.Choice(['start', 'stop'], case_sensitive=False))
@click.option('--domain', '-d', required=False, help='Domain name for SSL', type=str)
@click.option('--port', '-p', required=False, help='Port number for Singbox service', type=int)
def singbox(action: str, domain: str, port: int):
    try:
        if action == 'start':
            if not domain or not port:
                raise click.UsageError('Error: Both --domain and --port are required for the start action.')
            cli_api.start_singbox(domain, port)
            click.echo(f'Singbox started successfully.')
        elif action == 'stop':
            cli_api.stop_singbox()
            click.echo(f'Singbox stopped successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('normal-sub')
@click.option('--action', '-a', required=True, 
              type=click.Choice(['start', 'stop', 'edit_subpath'], case_sensitive=False),
              help='Action to perform: start, stop, or edit_subpath')
@click.option('--domain', '-d', required=False, help='Domain name for SSL (for start action)', type=str)
@click.option('--port', '-p', required=False, help='Port number for NormalSub service (for start action)', type=int)
@click.option('--subpath', '-sp', required=False, help='New subpath (alphanumeric, for edit_subpath action)', type=str)
def normalsub(action: str, domain: str, port: int, subpath: str):
    try:
        if action == 'start':
            if not domain or not port:
                raise click.UsageError('Error: Both --domain and --port are required for the start action.')
            cli_api.start_normalsub(domain, port)
            click.echo(f'NormalSub started successfully.')
        elif action == 'stop':
            cli_api.stop_normalsub()
            click.echo(f'NormalSub stopped successfully.')
        elif action == 'edit_subpath':
            if not subpath:
                raise click.UsageError('Error: --subpath is required for the edit_subpath action.')
            cli_api.edit_normalsub_subpath(subpath)
            click.echo(f'NormalSub subpath updated to {subpath} successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('webpanel')
@click.option('--action', '-a', required=True, help='Action to perform: start or stop', type=click.Choice(['start', 'stop'], case_sensitive=False))
@click.option('--domain', '-d', required=False, help='Domain name for SSL', type=str)
@click.option('--port', '-p', required=False, help='Port number for WebPanel service', type=int)
@click.option('--admin-username', '-au', required=False, help='Admin username for WebPanel', type=str)
@click.option('--admin-password', '-ap', required=False, help='Admin password for WebPanel', type=str)
@click.option('--expiration-minutes', '-e', required=False, help='Expiration minutes for WebPanel session', type=int, default=20)
@click.option('--debug', '-g', is_flag=True, help='Enable debug mode for WebPanel', default=False)
@click.option('--decoy-path', '-dp', required=False, type=click.Path(exists=True, file_okay=False, dir_okay=True, readable=True), help='Optional path to serve as a decoy site (only for start action)') # Add decoy_path option
def webpanel(action: str, domain: str, port: int, admin_username: str, admin_password: str, expiration_minutes: int, debug: bool, decoy_path: str | None): # Add decoy_path parameter
    """Manages the Hysteria Web Panel service."""
    try:
        if action == 'start':
            if not domain or not port or not admin_username or not admin_password:
                raise click.UsageError('Error: the --domain, --port, --admin-username, and --admin-password are required for the start action.')
            
            cli_api.start_webpanel(domain, port, admin_username, admin_password, expiration_minutes, debug, decoy_path) 

            services_status = cli_api.get_services_status()
            if not services_status:
                raise click.Abort('Error: WebPanel services status not available.')
            if not services_status.get('hysteria-webpanel.service'):
                raise click.Abort('Error: hysteria-webpanel.service service is not running.')
            if not services_status.get('hysteria-caddy.service'):
                raise click.Abort('Error: hysteria-caddy.service service is not running.')

            url = cli_api.get_webpanel_url()
            click.echo(f'Hysteria web panel is now running. The service is accessible on: {url}')
            if decoy_path:
                click.echo(f'Decoy site configured using path: {decoy_path}')
        elif action == 'stop':
            if decoy_path: 
                 click.echo('Warning: --decoy-path option is ignored for the stop action.', err=True)
            cli_api.stop_webpanel()
            click.echo(f'WebPanel stopped successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)

@cli.command('setup-webpanel-decoy')
@click.option('--domain', '-d', required=True, help='Domain name associated with the web panel', type=str)
@click.option('--decoy-path', '-dp', required=True, type=click.Path(exists=True, file_okay=False, dir_okay=True, readable=True), help='Path to the directory containing the decoy website files (e.g., /var/www/html)')
def setup_webpanel_decoy(domain: str, decoy_path: str):
    """Sets up or updates the decoy site for the running Web Panel."""
    try:
        cli_api.setup_webpanel_decoy(domain, decoy_path)
        click.echo(f'Web Panel decoy site configured successfully for domain {domain} using path {decoy_path}.')
        click.echo('Note: Caddy service was restarted.')
    except Exception as e:
        click.echo(f'{e}', err=True)

@cli.command('stop-webpanel-decoy')
def stop_webpanel_decoy():
    """Stops the decoy site functionality for the Web Panel."""
    try:
        cli_api.stop_webpanel_decoy()
        click.echo(f'Web Panel decoy site stopped and configuration removed successfully.')
        click.echo('Note: Caddy service was restarted.')
    except Exception as e:
        click.echo(f'{e}', err=True)

@cli.command('get-webpanel-url')
def get_web_panel_url():
    try:
        url = cli_api.get_webpanel_url()
        click.echo(f'Hysteria web panel is now running. The service is accessible on: {url}')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('get-webpanel-api-token')
def get_web_panel_api_token():
    try:
        token = cli_api.get_webpanel_api_token()
        click.echo(f'WebPanel API token: {token}')
    except Exception as e:
        click.echo(f'{e}', err=True)

@cli.command('reset-webpanel-creds')
@click.option('--new-username', '-u', required=False, help='New admin username for WebPanel', type=str)
@click.option('--new-password', '-p', required=False, help='New admin password for WebPanel', type=str)
def reset_webpanel_creds(new_username: str | None, new_password: str | None):
    """Resets the WebPanel admin username and/or password."""
    try:
        if not new_username and not new_password:
            raise click.UsageError('Error: You must provide either --new-username or --new-password, or both.')
        
        cli_api.reset_webpanel_credentials(new_username, new_password)
        
        message_parts = []
        if new_username:
            message_parts.append(f"username to '{new_username}'")
        if new_password:
            message_parts.append("password")
        
        click.echo(f'WebPanel admin {" and ".join(message_parts)} updated successfully.')
        click.echo('WebPanel service has been restarted.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('get-webpanel-services-status')
def get_web_panel_services_status():
    try:
        if services_status := cli_api.get_services_status():
            webpanel_status = services_status.get('hysteria-webpanel.service', False)
            caddy_status = services_status.get('hysteria-caddy.service', False)
            print(f"hysteria-webpanel.service: {'Active' if webpanel_status else 'Inactive'}")
            print(f"hysteria-caddy.service: {'Active' if caddy_status else 'Inactive'}")
        else:
            click.echo('Error: Services status not available.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('get-services-status')
def get_services_status():
    try:
        if services_status := cli_api.get_services_status():
            for service, status in services_status.items():
                click.echo(f"{service}: {'Active' if status else 'Inactive'}")
        else:
            click.echo('Error: Services status not available.')
    except Exception as e:
        click.echo(f'{e}', err=True)


@cli.command('show-version')
def show_version():
    """Displays the currently installed version of the panel."""
    try:
        if version_info := cli_api.show_version():
             click.echo(version_info)
        else:
            click.echo("Error retrieving version")
    except Exception as e:
        click.echo(f"An unexpected error occurred: {e}", err=True)


@cli.command('check-version')
def check_version():
    """Checks if the current version is up-to-date and displays changelog if not."""
    try:
        if version_info := cli_api.check_version():
            click.echo(version_info)
        else:
            click.echo("Error retrieving version")
    except Exception as e:
        click.echo(f"An unexpected error occurred: {e}", err=True)

@cli.command('start-ip-limit')
def start_ip_limit():
    """Starts the IP limiter service."""
    try:
        cli_api.start_ip_limiter()
        click.echo('IP Limiter service started successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)

@cli.command('stop-ip-limit')
def stop_ip_limit():
    """Stops the IP limiter service."""
    try:
        cli_api.stop_ip_limiter()
        click.echo('IP Limiter service stopped successfully.')
    except Exception as e:
        click.echo(f'{e}', err=True)

@cli.command('config-ip-limit')
@click.option('--block-duration', '-bd', type=int, help='New block duration in seconds')
@click.option('--max-ips', '-mi', type=int, help='New maximum IPs per user')
def config_ip_limit(block_duration: int, max_ips: int):
    """Configures the IP limiter service parameters."""
    try:
        cli_api.config_ip_limiter(block_duration, max_ips)
        click.echo('IP Limiter configuration updated successfully.')
        if block_duration is not None:
            click.echo(f'  Block Duration: {block_duration} seconds')
        if max_ips is not None:
            click.echo(f'  Max IPs per user: {max_ips}')
    except Exception as e:
        click.echo(f'{e}', err=True)

# endregion


if __name__ == '__main__':
    cli()