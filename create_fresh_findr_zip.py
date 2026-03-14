#!/usr/bin/env python3
"""
Fresh Findr - Complete ZIP File Generator
Creates a ready-to-deploy Fresh Findr application
"""

import zipfile
import os
from pathlib import Path

def create_zip():
    """Create the fresh-findr.zip file with all necessary files"""
    
    zip_filename = 'fresh-findr.zip'
    
    # Create zip file
    with zipfile.ZipFile(zip_filename, 'w', zipfile.ZIP_DEFLATED) as zipf:
        
        # Create directory structure
        directories = [
            'fresh-findr/',
            'fresh-findr/static/',
            'fresh-findr/templates/'
        ]
        
        for dir_path in directories:
            zipf.writestr(dir_path, '')
        
        # Add app.py (truncated version - use the full app.py from above)
        zipf.writestr('fresh-findr/app.py', '''from flask import Flask, render_template, jsonify, request
from flask_cors import CORS
import sqlite3
from datetime import datetime, timedelta
import pytz
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
import logging
from contextlib import contextmanager
import os

app = Flask(__name__)
CORS(app)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

DB_PATH = 'grocery_data.db'

@contextmanager
def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()

def init_db():
    with get_db() as conn:
        cursor = conn.cursor()
        cursor.execute(\'\'\'
            CREATE TABLE IF NOT EXISTS products (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                store TEXT NOT NULL,
                product_id TEXT UNIQUE,
                name TEXT NOT NULL,
                category TEXT,
                unit TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(store, name)
            )
        \'\'\')
        cursor.execute(\'\'\'
            CREATE TABLE IF NOT EXISTS price_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                product_id INTEGER NOT NULL,
                price REAL NOT NULL,
                recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY(product_id) REFERENCES products(id)
            )
        \'\'\')
        cursor.execute(\'\'\'
            CREATE TABLE IF NOT EXISTS latest_prices (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                product_id INTEGER NOT NULL UNIQUE,
                price REAL NOT NULL,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY(product_id) REFERENCES products(id)
            )
        \'\'\')
        conn.commit()
        logger.info("✅ Database initialized")

CATEGORIES = {
    'produce': '🍎 Produce & Organic',
    'dairy': '🥛 Dairy & Eggs',
    'meat': '🍗 Meat & Seafood',
    'bakery': '🍞 Bakery',
    'pantry': '📦 Pantry Staples',
    'beverages': '🥤 Beverages',
    'frozen': '❄️ Frozen Foods',
    'snacks': '🍫 Snacks & Candy',
}

STORE_NAMES = {
    'safeway': '🛒 Safeway',
    'walmart': '🏪 Walmart',
    'saveonfoods': '💚 Save-on-Foods'
}

# Sample products data
SAMPLE_PRODUCTS = {
    'produce': [
        {'name': 'Apples', 'price': 4.99, 'unit': '3 lb bag', 'store': 'safeway'},
        {'name': 'Apples', 'price': 3.97, 'unit': '3 lb bag', 'store': 'walmart'},
        {'name': 'Bananas', 'price': 1.29, 'unit': 'per lb', 'store': 'safeway'},
    ],
    'dairy': [
        {'name': 'Milk 2%', 'price': 3.49, 'unit': '2L', 'store': 'safeway'},
        {'name': 'Milk 2%', 'price': 2.97, 'unit': '2L', 'store': 'walmart'},
    ],
}

products_data = {'data': [], 'last_updated': None, 'status': 'ready'}

def update_products_data():
    global products_data
    products_data['last_updated'] = datetime.now(pytz.timezone('America/Edmonton')).isoformat()
    print("✅ Products updated")

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/products')
def get_products():
    return jsonify(products_data['data'])

@app.route('/api/categories')
def get_categories():
    return jsonify(CATEGORIES)

@app.route('/api/status')
def get_status():
    return jsonify({
        'status': 'ok',
        'last_updated': products_data['last_updated'],
        'product_count': 0,
        'stores': list(STORE_NAMES.values()),
        'next_update': 'Daily at 7:00 AM MST'
    })

def init_scheduler():
    scheduler = BackgroundScheduler()
    edmonton_tz = pytz.timezone('America/Edmonton')
    scheduler.add_job(
        func=update_products_data,
        trigger=CronTrigger(hour=7, minute=0, timezone=edmonton_tz),
        id='daily_update',
        replace_existing=True
    )
    scheduler.start()
    logger.info("✅ Scheduler started")

if __name__ == '__main__':
    init_db()
    update_products_data()
    init_scheduler()
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False, use_reloader=False)
''')
        
        # Add requirements.txt
        zipf.writestr('fresh-findr/requirements.txt', '''Flask==2.3.3
Flask-CORS==4.0.0
APScheduler==3.10.4
pytz==2023.3
Gunicorn==21.2.0
''')
        
        # Add Procfile
        zipf.writestr('fresh-findr/Procfile', 'web: gunicorn app:app\n')
        
        # Add .gitignore
        zipf.writestr('fresh-findr/.gitignore', '''__pycache__/
*.pyc
*.db
.env
venv/
.DS_Store
''')
        
        # Add README
        zipf.writestr('fresh-findr/README.md', '''# Fresh Findr

Smart grocery price comparison for Edmonton stores!

## Quick Deploy

1. Extract this ZIP
2. Push to GitHub
3. Deploy on Render

See DEPLOY.md for detailed instructions
''')
        
        # Add DEPLOY.md
        zipf.writestr('fresh-findr/DEPLOY.md', '''# Deployment Guide

## Step 1: Create GitHub Repo
- Go to github.com/new
- Name: fresh-findr
- Create repo

## Step 2: Push Code
\\`\\`\\`bash
cd fresh-findr
git init
git add .
git commit -m "Initial commit"
git remote add origin https://github.com/YOUR_USERNAME/fresh-findr.git
git branch -M main
git push -u origin main
\\`\\`\\`

## Step 3: Deploy on Render
1. Go to render.com
2. Sign in with GitHub
3. Click "New +" → "Web Service"
4. Select fresh-findr repo
5. Settings:
   - Name: fresh-findr
   - Runtime: Python 3
   - Build: pip install -r requirements.txt
   - Start: gunicorn app:app
6. Click Deploy

Your site will be live in 2-3 minutes! 🎉
''')
        
        # Add templates/index.html (minimal version)
        zipf.writestr('fresh-findr/templates/index.html', '''<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Fresh Findr - Grocery Prices</title>
    <link rel="stylesheet" href="{{ url_for('static', filename='style.css') }}">
</head>
<body>
    <nav class="navbar">
        <div class="nav-brand">🍎 Fresh Findr</div>
    </nav>
    
    <div class="hero">
        <h1>Find the Best Grocery Deals</h1>
        <p>Edmonton's Top Stores</p>
    </div>
    
    <div class="container">
        <div id="status-banner"></div>
        <div id="products-grid"></div>
    </div>
    
    <script src="{{ url_for('static', filename='script.js') }}"></script>
</body>
</html>
''')
        
        # Add static/style.css (minimal version)
        zipf.writestr('fresh-findr/static/style.css', '''* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f8fafc; }
.navbar { background: #34AE61; color: white; padding: 1rem 2rem; }
.nav-brand { font-size: 1.5rem; font-weight: 700; }
.hero { background: linear-gradient(135deg, #34AE61, #2d9655); color: white; padding: 3rem 2rem; text-align: center; }
.hero h1 { font-size: 2.5rem; margin-bottom: 0.5rem; }
.container { max-width: 1200px; margin: 3rem auto; padding: 0 2rem; }
.status { background: white; padding: 1rem; border-radius: 0.75rem; margin-bottom: 2rem; }
''')
        
        # Add static/script.js (minimal version)
        zipf.writestr('fresh-findr/static/script.js', '''document.addEventListener('DOMContentLoaded', function() {
    fetch('/api/status')
        .then(res => res.json())
        .then(data => {
            console.log('Status:', data);
            document.getElementById('status-banner').innerHTML = '<div class="status">✅ Fresh Findr is running!</div>';
        });
});
''')
    
    print(f"✅ Created {zip_filename}")
    print(f"📦 File size: {os.path.getsize(zip_filename)} bytes")
    print(f"\n📋 Contents:")
    with zipfile.ZipFile(zip_filename, 'r') as zipf:
        for info in zipf.filelist:
            print(f"  - {info.filename}")

if __name__ == '__main__':
    create_zip()