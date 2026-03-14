from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from datetime import datetime
import pytz
import requests

def start_scheduler(app):
    """Start the background scheduler for daily price updates"""
    scheduler = BackgroundScheduler()
    
    # MST timezone
    mst = pytz.timezone('US/Mountain')
    
    # Schedule job to run daily at 7:00 AM MST
    scheduler.add_job(
        func=update_prices_job,
        trigger=CronTrigger(hour=7, minute=0, timezone=mst),
        id='daily_price_update',
        name='Daily Price Update at 7 AM MST',
        replace_existing=True
    )
    
    scheduler.start()
    print("✓ Scheduler started! Price update scheduled for 7:00 AM MST daily")

def update_prices_job():
    """Job that runs at 7 AM MST to update prices"""
    try:
        print(f"\n{'='*50}")
        print(f"🔄 Starting daily price update at {datetime.now()}")
        print(f"{'='*50}")
        
        # Simulate price update - replace with actual API calls
        from utils import fetch_and_update_prices
        fetch_and_update_prices()
        
        print(f"✓ Price update completed successfully!")
        print(f"{'='*50}\n")
    except Exception as e:
        print(f"✗ Error during price update: {str(e)}")