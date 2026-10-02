from datetime import datetime
from zoneinfo import ZoneInfo

APP_TIMEZONE = ZoneInfo("Asia/Shanghai")


def app_date(value: datetime):
    return value.astimezone(APP_TIMEZONE).date()
