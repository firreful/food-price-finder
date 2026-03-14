from flask import Flask, render_template, jsonify, request
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
        cursor.execute('''
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
        ''')
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS price_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                product_id INTEGER NOT NULL,
                price REAL NOT NULL,
                recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY(product_id) REFERENCES products(id)
            )
        ''')
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS latest_prices (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                product_id INTEGER NOT NULL UNIQUE,
                price REAL NOT NULL,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY(product_id) REFERENCES products(id)
            )
        ''')
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

products_db = {
    'safeway': [
        {'name': 'Fuji Apples', 'price': 4.99, 'category': 'produce', 'unit': '3 lb bag'},
        {'name': 'Gala Apples', 'price': 4.49, 'category': 'produce', 'unit': '3 lb bag'},
        {'name': 'Bananas', 'price': 1.29, 'category': 'produce', 'unit': 'per lb'},
        {'name': 'Strawberries', 'price': 3.99, 'category': 'produce', 'unit': '1 lb'},
        {'name': 'Blueberries', 'price': 5.99, 'category': 'produce', 'unit': '1 lb'},
        {'name': 'Carrots', 'price': 1.99, 'category': 'produce', 'unit': '2 lb bag'},
        {'name': 'Broccoli', 'price': 2.49, 'category': 'produce', 'unit': 'head'},
        {'name': 'Cauliflower', 'price': 2.99, 'category': 'produce', 'unit': 'head'},
        {'name': 'Bell Peppers', 'price': 1.99, 'category': 'produce', 'unit': 'each'},
        {'name': 'Tomatoes', 'price': 3.99, 'category': 'produce', 'unit': 'per lb'},
        {'name': 'Cucumbers', 'price': 1.49, 'category': 'produce', 'unit': 'each'},
        {'name': 'Lettuce', 'price': 2.99, 'category': 'produce', 'unit': 'head'},
        {'name': '2% Milk', 'price': 3.49, 'category': 'dairy', 'unit': '2L'},
        {'name': 'Greek Yogurt', 'price': 5.99, 'category': 'dairy', 'unit': '650g'},
        {'name': 'Cheddar Cheese', 'price': 6.99, 'category': 'dairy', 'unit': '200g'},
        {'name': 'Butter', 'price': 6.49, 'category': 'dairy', 'unit': '454g'},
        {'name': 'Eggs', 'price': 3.49, 'category': 'dairy', 'unit': 'Dozen'},
        {'name': 'Chicken Breast', 'price': 9.99, 'category': 'meat', 'unit': 'per lb'},
        {'name': 'Ground Beef', 'price': 8.99, 'category': 'meat', 'unit': 'per lb'},
        {'name': 'Salmon Fillet', 'price': 14.99, 'category': 'meat', 'unit': 'per lb'},
        {'name': 'Whole Wheat Bread', 'price': 3.49, 'category': 'bakery', 'unit': 'loaf'},
        {'name': 'Croissants', 'price': 4.99, 'category': 'bakery', 'unit': '4-pack'},
        {'name': 'Orange Juice', 'price': 3.99, 'category': 'beverages', 'unit': '1L'},
        {'name': 'Coffee', 'price': 7.99, 'category': 'beverages', 'unit': '400g'},
    ],
    'walmart': [
        {'name': 'Gala Apples', 'price': 3.97, 'category': 'produce', 'unit': '3 lb bag'},
        {'name': 'Bananas', 'price': 0.67, 'category': 'produce', 'unit': 'per lb'},
        {'name': 'Strawberries', 'price': 3.47, 'category': 'produce', 'unit': '1 lb'},
        {'name': 'Carrots', 'price': 1.47, 'category': 'produce', 'unit': '2 lb bag'},
        {'name': 'Broccoli', 'price': 1.97, 'category': 'produce', 'unit': 'head'},
        {'name': 'Bell Peppers', 'price': 1.47, 'category': 'produce', 'unit': 'each'},
        {'name': 'Tomatoes', 'price': 2.97, 'category': 'produce', 'unit': 'per lb'},
        {'name': 'Cucumbers', 'price': 0.97, 'category': 'produce', 'unit': 'each'},
        {'name': 'Lettuce', 'price': 1.97, 'category': 'produce', 'unit': 'head'},
        {'name': 'Great Value 2% Milk', 'price': 2.97, 'category': 'dairy', 'unit': '2L'},
        {'name': 'Greek Yogurt', 'price': 3.97, 'category': 'dairy', 'unit': '650g'},
        {'name': 'Cheddar Cheese', 'price': 3.97, 'category': 'dairy', 'unit': '200g'},
        {'name': 'Butter', 'price': 4.97, 'category': 'dairy', 'unit': '454g'},
        {'name': 'Great Value Eggs', 'price': 2.47, 'category': 'dairy', 'unit': 'Dozen'},
        {'name': 'Chicken Breast', 'price': 7.47, 'category': 'meat', 'unit': 'per lb'},
        {'name': 'Ground Beef', 'price': 6.97, 'category': 'meat', 'unit': 'per lb'},
        {'name': 'Salmon Fillet', 'price': 11.97, 'category': 'meat', 'unit': 'per lb'},
        {'name': 'Wonder Bread', 'price': 1.97, 'category': 'bakery', 'unit': 'loaf'},
        {'name': 'Croissants', 'price': 2.97, 'category': 'bakery', 'unit': '4-pack'},
        {'name': 'Orange Juice', 'price': 2.47, 'category': 'beverages', 'unit': '1.89L'},
        {'name': 'Coffee', 'price': 5.97, 'category': 'beverages', 'unit': '400g'},
    ],
    'saveonfoods': [
        {'name': 'Jonagold Apples', 'price': 4.49, 'category': 'produce', 'unit': '3 lb bag'},
        {'name': 'Bananas', 'price': 0.99, 'category': 'produce', 'unit': 'per lb'},
        {'name': 'Strawberries', 'price': 4.99, 'category': 'produce', 'unit': '1 lb'},
        {'name': 'Carrots', 'price': 2.49, 'category': 'produce', 'unit': '2 lb bag'},
        {'name': 'Broccoli', 'price': 2.99, 'category': 'produce', 'unit': 'head'},
        {'name': 'Bell Peppers', 'price': 2.49, 'category': 'produce', 'unit': 'each'},
        {'name': 'Tomatoes', 'price': 3.49, 'category': 'produce', 'unit': 'per lb'},
        {'name': 'Cucumbers', 'price': 1.99, 'category': 'produce', 'unit': 'each'},
        {'name': 'Lettuce', 'price': 2.49, 'category': 'produce', 'unit': 'head'},
        {'name': 'Lucerne 2% Milk', 'price': 3.29, 'category': 'dairy', 'unit': '2L'},
        {'name': 'Fage Greek Yogurt', 'price': 4.99, 'category': 'dairy', 'unit': '650g'},
        {'name': 'Black Diamond Cheese', 'price': 5.99, 'category': 'dairy', 'unit': '200g'},
        {'name': 'Lactantia Butter', 'price': 5.99, 'category': 'dairy', 'unit': '454g'},
        {'name': 'Brown Eggs', 'price': 5.99, 'category': 'dairy', 'unit': 'Dozen'},
        {'name': 'Boneless Chicken Breast', 'price': 10.99, 'category': 'meat', 'unit': 'per lb'},
        {'name': 'Ground Beef', 'price': 9.99, 'category': 'meat', 'unit': 'per lb'},
        {'name': 'Salmon Fillet', 'price': 14.99, 'category': 'meat', 'unit': 'per lb'},
        {'name': 'Artisan Bread', 'price': 3.99, 'category': 'bakery', 'unit': 'loaf'},
        {'name': 'Butter Croissants', 'price': 5.99, 'category': 'bakery', 'unit': '4-pack'},
        {'name': 'Fresh Orange Juice', 'price': 4.99, 'category': 'beverages', 'unit': '1L'},
        {'name': 'Premium Coffee', 'price': 8.99, 'category': 'beverages', 'unit': '400g'},
    ]
}

products_data = {'data': [], 'last_updated': None, 'status': 'ready'}

def organize_products():
    organized = {}
    
    for store, items in products_db.items():
        for product in items:
            name = product['name'].lower()
            
            if name not in organized:
                organized[name] = {
                    'name': product['name'],
                    'category': product['category'],
                    'prices': {}
                }
            
            organized[name]['prices'][STORE_NAMES[store]] = {
                'price': product['price'],
                'unit': product.get('unit', 'each'),
                'store': store
            }
    
    products_list = []
    for product_name, product_info in organized.items():
        if product_info['prices']:
            lowest_price = min(p['price'] for p in product_info['prices'].values())
            best_store = [s for s, p in product_info['prices'].items() if p['price'] == lowest_price][0]
            
            products_list.append({
                'name': product_info['name'],
                'category': product_info['category'],
                'prices': product_info['prices'],
                'lowest_price': lowest_price,
                'best_store': best_store
            })
    
    return sorted(products_list, key=lambda x: x['name'])

def update_products_data():
    global products_data
    products_data['data'] = organize_products()
    edmonton_tz = pytz.timezone('America/Edmonton')
    products_data['last_updated'] = datetime.now(edmonton_tz).isoformat()
    logger.info(f"✅ Updated {len(products_data['data'])} products")

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/products')
def get_products():
    category = request.args.get('category', 'all')
    search = request.args.get('search', '').lower()
    
    filtered = products_data['data']
    
    if category != 'all':
        filtered = [p for p in filtered if p['category'] == category]
    
    if search:
        filtered = [p for p in filtered if search in p['name'].lower()]
    
    return jsonify(filtered)

@app.route('/api/categories')
def get_categories():
    return jsonify(CATEGORIES)

@app.route('/api/status')
def get_status():
    return jsonify({
        'status': products_data['status'],
        'last_updated': products_data['last_updated'],
        'product_count': len(products_data['data']),
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
        name='Daily update',
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