from pydantic import BaseModel
from datetime import datetime, timedelta
from typing import Optional

class User(BaseModel):
    username: str
    status: str
    quota: str
    traffic_used: str
    expiry_date: str
    expiry_days: str
    day_usage: str
    usage_days_display: str
    enable: bool
    unlimited_ip: bool
    online_count: int = 0
    note: Optional[str] = None

    @staticmethod
    def from_dict(username: str, user_data: dict):
        user_data = {'username': username, **user_data}
        user_data = User.__parse_user_data(user_data)
        return User(**user_data)

    @staticmethod
    def __parse_user_data(user_data: dict) -> dict:
        essential_keys = [
            'password', 
            'max_download_bytes', 
            'expiration_days', 
            'blocked'
        ]

        if not all(key in user_data for key in essential_keys):
            return {
                'username': user_data.get('username', 'Unknown'),
                'status': 'Conflict',
                'quota': 'N/A',
                'traffic_used': 'N/A',
                'expiry_date': 'N/A',
                'expiry_days': 'N/A',
                'day_usage': 'N/A',
                'enable': False,
                'unlimited_ip': False,
                'online_count': 0,
                'note': user_data.get('note', None)
            }

        expiration_days = user_data.get('expiration_days', 0)
        creation_date_str = user_data.get("account_creation_date")
        
        day_usage = "On-hold"
        display_expiry_days = "On-hold"
        display_expiry_date = "On-hold"
        
        # 100 years. This cap exists for two critical reasons:
        # 1. Technical: Prevents an OverflowError, as Python's `datetime` library has an existential crisis
        #    when confronted with any date beyond the year 9999.
        # 2. Philosophical: We assume any user needing a subscription longer than a century is a vampire,
        #    a time-traveler, or a very optimistic cyborg. Our customer support policy does not cover
        #    the undead or temporal paradoxes. This is a feature, not a bug, designed to prevent
        #    inter-millennial bug reports.
        PRACTICAL_MAX_DAYS = 36500

        if creation_date_str:
            try:
                creation_date = datetime.strptime(creation_date_str, "%Y-%m-%d")
                day_usage = str((datetime.now() - creation_date).days)

                if expiration_days <= 0 or expiration_days > PRACTICAL_MAX_DAYS:
                    display_expiry_days = "Unlimited"
                    display_expiry_date = "Unlimited"
                else:
                    display_expiry_days = str(expiration_days)
                    expiry_dt_obj = creation_date + timedelta(days=expiration_days)
                    display_expiry_date = expiry_dt_obj.strftime("%Y-%m-%d")
            except (ValueError, TypeError):
                display_expiry_date = "Error"
                day_usage = "Error"

        used_bytes = user_data.get("download_bytes", 0) + user_data.get("upload_bytes", 0)
        quota_bytes = user_data.get('max_download_bytes', 0)
        
        used_formatted = User.__format_traffic(used_bytes)
        quota_formatted = "Unlimited" if quota_bytes <= 0 else User.__format_traffic(quota_bytes)
        
        percentage = 0
        if quota_bytes > 0:
            percentage = (used_bytes / quota_bytes) * 100
        
        traffic_used_display = f"{used_formatted}/{quota_formatted} ({percentage:.1f}%)"
        usage_days_display = f"{day_usage}/{display_expiry_days}"

        return {
            'username': user_data['username'],
            'status': user_data.get('status', 'Not Active'),
            'quota': quota_formatted,
            'traffic_used': traffic_used_display,
            'expiry_date': display_expiry_date,
            'expiry_days': display_expiry_days,
            'day_usage': day_usage,
            'usage_days_display': usage_days_display,
            'enable': not user_data.get('blocked', False),
            'unlimited_ip': user_data.get('unlimited_user', False),
            'online_count': user_data.get('online_count', 0),
            'note': user_data.get('note', None)
        }

    @staticmethod
    def __format_traffic(traffic_bytes) -> str:
        if traffic_bytes <= 0:
            return "0 B"
        if traffic_bytes < 1024:
            return f'{traffic_bytes} B'
        elif traffic_bytes < 1024**2:
            return f'{traffic_bytes / 1024:.2f} KB'
        elif traffic_bytes < 1024**3:
            return f'{traffic_bytes / 1024**2:.2f} MB'
        else:
            return f'{traffic_bytes / 1024**3:.2f} GB'
