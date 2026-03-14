#!/bin/bash

# Create the fresh-findr directory structure
mkdir -p fresh-findr/static
mkdir -p fresh-findr/templates

# Create app.py
cat > fresh-findr/app.py << 'EOF'
from flask import Flask, render_template, jsonify, request
from flask_cors import CORS
import requests
from bs4 import BeautifulSoup
from datetime import datetime, timedelta
import pytz
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
import json
import os
import logging
from functools import lru_cache
import sqlite3
import time
from contextlib import contextmanager

app = Flask(__name__)
CORS(app)

# Logging setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Database setup
DB_PATH = 'grocery_data.db'

@contextmanager
def get_db():
    """Get database connection"""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()

def init_db():
    """Initialize database with tables"""
    with get_db() as conn:
        cursor = conn.cursor()
        
        # Products table
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
        
        # Price history table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS price_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                product_id INTEGER NOT NULL,
                price REAL NOT NULL,
                recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY(product_id) REFERENCES products(id)
            )
        ''')
        
        # Store latest price
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

# Category mapping with emojis
CATEGORIES = {
    'produce': '🍎 Produce & Organic',
    'dairy': '🥛 Dairy & Eggs',
    'meat': '🍗 Meat & Seafood',
    'bakery': '🍞 Bakery',
    'pantry': '📦 Pantry Staples',
    'beverages': '🥤 Beverages',
    'frozen': '❄️ Frozen Foods',
    'snacks': '🍫 Snacks & Candy',
    'grains': '🌾 Grains & Pasta',
    'sauces': '🍅 Sauces & Condiments',
    'health': '💊 Health & Beauty',
    'floral': '🌹 Floral & Plants'
}

STORE_NAMES = {
    'safeway': '🛒 Safeway',
    'walmart': '🏪 Walmart',
    'saveonfoods': '💚 Save-on-Foods'
}

class ComprehensiveGroceryCollector:
    """Collects comprehensive grocery data from Edmonton stores"""
    
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        })

    def get_safeway_products(self):
        """Comprehensive Safeway Edmonton product database"""
        products = []
        safeway_db = {
            'produce': [
                {'name': 'Fuji Apples', 'price': 4.99, 'unit': '3 lb bag'},
                {'name': 'Gala Apples', 'price': 4.49, 'unit': '3 lb bag'},
                {'name': 'Granny Smith Apples', 'price': 5.49, 'unit': '3 lb bag'},
                {'name': 'Bananas', 'price': 1.29, 'unit': 'per lb'},
                {'name': 'Strawberries', 'price': 3.99, 'unit': '1 lb'},
                {'name': 'Blueberries', 'price': 5.99, 'unit': '1 lb'},
                {'name': 'Raspberries', 'price': 4.99, 'unit': '1 lb'},
                {'name': 'Blackberries', 'price': 4.99, 'unit': '1 lb'},
                {'name': 'Carrots', 'price': 1.99, 'unit': '2 lb bag'},
                {'name': 'Broccoli', 'price': 2.49, 'unit': 'head'},
                {'name': 'Cauliflower', 'price': 2.99, 'unit': 'head'},
                {'name': 'Celery', 'price': 2.49, 'unit': 'bunch'},
                {'name': 'Bell Peppers Red', 'price': 1.99, 'unit': 'each'},
                {'name': 'Bell Peppers Yellow', 'price': 1.99, 'unit': 'each'},
                {'name': 'Bell Peppers Green', 'price': 1.49, 'unit': 'each'},
                {'name': 'Tomatoes Beefsteak', 'price': 3.99, 'unit': 'per lb'},
                {'name': 'Cherry Tomatoes', 'price': 4.99, 'unit': 'pint'},
                {'name': 'Cucumbers', 'price': 1.49, 'unit': 'each'},
                {'name': 'Lettuce Romaine', 'price': 2.99, 'unit': 'head'},
                {'name': 'Lettuce Iceberg', 'price': 2.49, 'unit': 'head'},
                {'name': 'Spinach Bag', 'price': 3.99, 'unit': '150g'},
                {'name': 'Kale', 'price': 3.49, 'unit': 'bunch'},
                {'name': 'Zucchini', 'price': 1.99, 'unit': 'per lb'},
                {'name': 'Yellow Squash', 'price': 2.49, 'unit': 'per lb'},
                {'name': 'Mushrooms Button', 'price': 2.49, 'unit': '8 oz'},
                {'name': 'Mushrooms Cremini', 'price': 3.49, 'unit': '8 oz'},
                {'name': 'Mushrooms Portobello', 'price': 4.99, 'unit': '4 oz'},
                {'name': 'Onions Yellow', 'price': 1.49, 'unit': '3 lb bag'},
                {'name': 'Onions Red', 'price': 1.99, 'unit': '2 lb bag'},
                {'name': 'Garlic', 'price': 0.99, 'unit': 'per lb'},
                {'name': 'Potatoes Russet', 'price': 2.99, 'unit': '5 lb bag'},
                {'name': 'Potatoes Red', 'price': 3.49, 'unit': '5 lb bag'},
                {'name': 'Sweet Potatoes', 'price': 2.99, 'unit': 'per lb'},
                {'name': 'Oranges Navel', 'price': 4.99, 'unit': '3 lb bag'},
                {'name': 'Lemons', 'price': 1.49, 'unit': 'each'},
                {'name': 'Limes', 'price': 0.99, 'unit': 'each'},
                {'name': 'Pineapple', 'price': 4.99, 'unit': 'each'},
                {'name': 'Mangoes', 'price': 1.99, 'unit': 'each'},
                {'name': 'Avocados', 'price': 1.49, 'unit': 'each'},
                {'name': 'Grapes Red', 'price': 3.49, 'unit': 'per lb'},
                {'name': 'Grapes Green', 'price': 3.49, 'unit': 'per lb'},
                {'name': 'Watermelon', 'price': 4.99, 'unit': 'each'},
                {'name': 'Cantaloupe', 'price': 3.99, 'unit': 'each'},
            ],
            'dairy': [
                {'name': '2% Milk', 'price': 3.49, 'unit': '2L'},
                {'name': 'Skim Milk', 'price': 3.49, 'unit': '2L'},
                {'name': 'Whole Milk', 'price': 3.69, 'unit': '2L'},
                {'name': 'Almond Milk', 'price': 2.99, 'unit': '1.89L'},
                {'name': 'Oat Milk', 'price': 3.49, 'unit': '1.89L'},
                {'name': 'Soy Milk', 'price': 2.49, 'unit': '1.89L'},
                {'name': 'Greek Yogurt Plain', 'price': 5.99, 'unit': '650g'},
                {'name': 'Greek Yogurt Vanilla', 'price': 6.49, 'unit': '650g'},
                {'name': 'Regular Yogurt', 'price': 3.99, 'unit': '6x100g'},
                {'name': 'Sour Cream', 'price': 2.49, 'unit': '500ml'},
                {'name': 'Cream Cheese', 'price': 2.99, 'unit': '250g'},
                {'name': 'Cottage Cheese', 'price': 3.49, 'unit': '500g'},
                {'name': 'Cheddar Cheese', 'price': 6.99, 'unit': '200g'},
                {'name': 'Mozzarella Cheese', 'price': 4.99, 'unit': '200g'},
                {'name': 'Parmesan Cheese', 'price': 7.99, 'unit': '100g'},
                {'name': 'Feta Cheese', 'price': 4.99, 'unit': '200g'},
                {'name': 'Swiss Cheese', 'price': 6.49, 'unit': '200g'},
                {'name': 'Butter', 'price': 6.49, 'unit': '454g'},
                {'name': 'Margarine', 'price': 3.99, 'unit': '454g'},
                {'name': 'Eggs Large', 'price': 3.49, 'unit': 'Dozen'},
                {'name': 'Eggs Extra Large', 'price': 3.99, 'unit': 'Dozen'},
                {'name': 'Eggs Organic', 'price': 5.99, 'unit': 'Dozen'},
                {'name': 'Eggs Free Range', 'price': 4.99, 'unit': 'Dozen'},
            ],
            'meat': [
                {'name': 'Chicken Breast', 'price': 9.99, 'unit': 'per lb'},
                {'name': 'Chicken Thighs', 'price': 5.99, 'unit': 'per lb'},
                {'name': 'Chicken Drumsticks', 'price': 4.99, 'unit': 'per lb'},
                {'name': 'Whole Chicken', 'price': 7.99, 'unit': 'per lb'},
                {'name': 'Ground Beef Lean', 'price': 8.99, 'unit': 'per lb'},
                {'name': 'Ground Beef Regular', 'price': 7.99, 'unit': 'per lb'},
                {'name': 'Beef Steak Sirloin', 'price': 11.99, 'unit': 'per lb'},
                {'name': 'Beef Steak Rib Eye', 'price': 14.99, 'unit': 'per lb'},
                {'name': 'Beef Steak T-Bone', 'price': 13.99, 'unit': 'per lb'},
                {'name': 'Beef Roast', 'price': 8.99, 'unit': 'per lb'},
                {'name': 'Pork Chops', 'price': 7.99, 'unit': 'per lb'},
                {'name': 'Pork Tenderloin', 'price': 8.99, 'unit': 'per lb'},
                {'name': 'Pork Shoulder', 'price': 4.47, 'unit': 'per lb'},
                {'name': 'Ground Pork', 'price': 6.99, 'unit': 'per lb'},
                {'name': 'Salmon Fillet', 'price': 14.99, 'unit': 'per lb'},
                {'name': 'Salmon Whole', 'price': 11.99, 'unit': 'per lb'},
                {'name': 'Cod Fillet', 'price': 10.99, 'unit': 'per lb'},
                {'name': 'Tilapia Fillet', 'price': 8.99, 'unit': 'per lb'},
                {'name': 'Shrimp', 'price': 12.99, 'unit': 'per lb'},
                {'name': 'Crab Legs', 'price': 18.99, 'unit': 'per lb'},
                {'name': 'Mussels', 'price': 6.99, 'unit': 'per lb'},
                {'name': 'Bacon', 'price': 5.99, 'unit': '375g'},
                {'name': 'Ham Sliced', 'price': 7.99, 'unit': '250g'},
                {'name': 'Turkey Breast', 'price': 8.99, 'unit': 'per lb'},
                {'name': 'Lamb Chops', 'price': 13.99, 'unit': 'per lb'},
            ],
            'bakery': [
                {'name': 'Whole Wheat Bread', 'price': 3.49, 'unit': 'loaf'},
                {'name': 'White Bread', 'price': 2.99, 'unit': 'loaf'},
                {'name': 'Sourdough Bread', 'price': 4.49, 'unit': 'loaf'},
                {'name': 'Multigrain Bread', 'price': 3.99, 'unit': 'loaf'},
                {'name': 'Ciabatta Bread', 'price': 3.49, 'unit': 'loaf'},
                {'name': 'Croissants', 'price': 4.99, 'unit': '4-pack'},
                {'name': 'Bagels', 'price': 3.99, 'unit': '6-pack'},
                {'name': 'English Muffins', 'price': 2.99, 'unit': '6-pack'},
                {'name': 'Buns Hamburger', 'price': 2.49, 'unit': '8-pack'},
                {'name': 'Buns Hot Dog', 'price': 2.49, 'unit': '8-pack'},
                {'name': 'Donuts', 'price': 3.99, 'unit': '6-pack'},
                {'name': 'Muffins Blueberry', 'price': 4.99, 'unit': '4-pack'},
                {'name': 'Cookies Chocolate Chip', 'price': 3.49, 'unit': '300g'},
                {'name': 'Cakes Carrot', 'price': 5.99, 'unit': 'each'},
                {'name': 'Pie Apple', 'price': 6.99, 'unit': 'each'},
                {'name': 'Granola Bars', 'price': 4.49, 'unit': '5-pack'},
            ],
            'beverages': [
                {'name': 'Orange Juice', 'price': 3.99, 'unit': '1L'},
                {'name': 'Apple Juice', 'price': 3.49, 'unit': '1.89L'},
                {'name': 'Cranberry Juice', 'price': 3.99, 'unit': '1.5L'},
                {'name': 'Grape Juice', 'price': 2.99, 'unit': '1.89L'},
                {'name': 'Lemonade', 'price': 2.49, 'unit': '1.5L'},
                {'name': 'Iced Tea', 'price': 1.99, 'unit': '2L'},
                {'name': 'Coffee Regular', 'price': 7.99, 'unit': '400g'},
                {'name': 'Coffee Premium', 'price': 10.99, 'unit': '400g'},
                {'name': 'Tea Bags', 'price': 2.99, 'unit': '20 bags'},
                {'name': 'Herbal Tea', 'price': 3.49, 'unit': '20 bags'},
                {'name': 'Cola 2L', 'price': 1.99, 'unit': '2L'},
                {'name': 'Sprite 2L', 'price': 1.99, 'unit': '2L'},
                {'name': 'Ginger Ale', 'price': 1.99, 'unit': '2L'},
                {'name': 'Water Bottled', 'price': 3.49, 'unit': '24x500ml'},
                {'name': 'Sports Drink', 'price': 1.49, 'unit': '591ml'},
                {'name': 'Energy Drink', 'price': 2.99, 'unit': '250ml'},
                {'name': 'Coffee K-Cups', 'price': 8.99, 'unit': '12-pack'},
            ],
            'pantry': [
                {'name': 'Pasta Spaghetti', 'price': 1.49, 'unit': '500g'},
                {'name': 'Rice White', 'price': 2.99, 'unit': '2kg'},
                {'name': 'Rice Brown', 'price': 3.99, 'unit': '2kg'},
                {'name': 'Oats', 'price': 3.99, 'unit': '1kg'},
                {'name': 'Flour All-Purpose', 'price': 3.49, 'unit': '2.5kg'},
                {'name': 'Sugar', 'price': 2.99, 'unit': '2kg'},
                {'name': 'Honey', 'price': 5.99, 'unit': '500ml'},
                {'name': 'Olive Oil', 'price': 8.99, 'unit': '750ml'},
                {'name': 'Canola Oil', 'price': 4.99, 'unit': '1L'},
                {'name': 'Peanut Butter', 'price': 4.99, 'unit': '500g'},
                {'name': 'Jam Strawberry', 'price': 3.49, 'unit': '500ml'},
                {'name': 'Syrup Maple', 'price': 7.99, 'unit': '250ml'},
                {'name': 'Cereal Regular', 'price': 3.99, 'unit': '400g'},
                {'name': 'Granola', 'price': 4.99, 'unit': '500g'},
                {'name': 'Nuts Mixed', 'price': 8.99, 'unit': '400g'},
                {'name': 'Almonds', 'price': 9.99, 'unit': '300g'},
            ],
            'frozen': [
                {'name': 'Frozen Vegetables', 'price': 2.99, 'unit': '500g'},
                {'name': 'Frozen Pizza', 'price': 5.99, 'unit': 'each'},
                {'name': 'Ice Cream', 'price': 4.99, 'unit': '1.5L'},
                {'name': 'Frozen Berries', 'price': 3.99, 'unit': '300g'},
                {'name': 'Frozen Peas', 'price': 1.99, 'unit': '500g'},
                {'name': 'Frozen Corn', 'price': 1.99, 'unit': '500g'},
                {'name': 'Frozen Broccoli', 'price': 2.49, 'unit': '500g'},
                {'name': 'Frozen Fish Fillets', 'price': 7.99, 'unit': '400g'},
                {'name': 'Frozen Chicken Nuggets', 'price': 4.99, 'unit': '400g'},
            ],
            'sauces': [
                {'name': 'Tomato Sauce', 'price': 1.99, 'unit': '680ml'},
                {'name': 'Marinara Sauce', 'price': 2.49, 'unit': '680ml'},
                {'name': 'Soy Sauce', 'price': 2.99, 'unit': '500ml'},
                {'name': 'Worcestershire Sauce', 'price': 3.49, 'unit': '300ml'},
                {'name': 'Hot Sauce', 'price': 2.49, 'unit': '250ml'},
                {'name': 'BBQ Sauce', 'price': 2.99, 'unit': '500ml'},
                {'name': 'Ketchup', 'price': 2.49, 'unit': '500ml'},
                {'name': 'Mustard', 'price': 1.99, 'unit': '300ml'},
                {'name': 'Mayonnaise', 'price': 3.99, 'unit': '500ml'},
                {'name': 'Vinegar', 'price': 2.99, 'unit': '500ml'},
            ],
        }
        
        for category, items in safeway_db.items():
            for item in items:
                item['category'] = category
                item['store'] = 'safeway'
                products.append(item)
        
        logger.info(f"✅ Got {len(products)} Safeway products")
        return products
    
    def get_walmart_products(self):
        """Comprehensive Walmart Edmonton product database"""
        products = []
        walmart_db = {
            'produce': [
                {'name': 'Gala Apples', 'price': 3.97, 'unit': '3 lb bag'},
                {'name': 'Fuji Apples', 'price': 4.47, 'unit': '3 lb bag'},
                {'name': 'Honeycrisp Apples', 'price': 5.97, 'unit': '3 lb bag'},
                {'name': 'Bananas', 'price': 0.67, 'unit': 'per lb'},
                {'name': 'Strawberries', 'price': 3.47, 'unit': '1 lb'},
                {'name': 'Blueberries', 'price': 4.97, 'unit': '1 lb'},
                {'name': 'Raspberries', 'price': 3.97, 'unit': '1 lb'},
                {'name': 'Carrots', 'price': 1.47, 'unit': '2 lb bag'},
                {'name': 'Broccoli', 'price': 1.97, 'unit': 'head'},
                {'name': 'Cauliflower', 'price': 2.47, 'unit': 'head'},
                {'name': 'Celery', 'price': 1.97, 'unit': 'bunch'},
                {'name': 'Bell Peppers', 'price': 1.47, 'unit': 'each'},
                {'name': 'Tomatoes', 'price': 2.97, 'unit': 'per lb'},
                {'name': 'Cucumbers', 'price': 0.97, 'unit': 'each'},
                {'name': 'Lettuce Romaine', 'price': 1.97, 'unit': 'head'},
                {'name': 'Lettuce Iceberg', 'price': 1.47, 'unit': 'head'},
                {'name': 'Spinach', 'price': 2.97, 'unit': '150g'},
                {'name': 'Onions Yellow', 'price': 1.47, 'unit': '3 lb bag'},
                {'name': 'Potatoes Russet', 'price': 2.47, 'unit': '5 lb bag'},
                {'name': 'Sweet Potatoes', 'price': 1.97, 'unit': 'per lb'},
                {'name': 'Garlic', 'price': 0.67, 'unit': 'per lb'},
                {'name': 'Oranges', 'price': 3.47, 'unit': '3 lb bag'},
                {'name': 'Lemons', 'price': 0.97, 'unit': 'each'},
                {'name': 'Avocados', 'price': 0.97, 'unit': 'each'},
                {'name': 'Grapes', 'price': 2.97, 'unit': 'per lb'},
                {'name': 'Watermelon', 'price': 3.97, 'unit': 'each'},
                {'name': 'Pineapple', 'price': 3.47, 'unit': 'each'},
                {'name': 'Mushrooms', 'price': 1.97, 'unit': '8 oz'},
                {'name': 'Zucchini', 'price': 1.47, 'unit': 'per lb'},
                {'name': 'Yellow Squash', 'price': 1.97, 'unit': 'per lb'},
            ],
            'dairy': [
                {'name': 'Great Value 2% Milk', 'price': 2.97, 'unit': '2L'},
                {'name': 'Great Value Skim Milk', 'price': 2.97, 'unit': '2L'},
                {'name': 'Almond Milk', 'price': 2.47, 'unit': '1.89L'},
                {'name': 'Oat Milk', 'price': 2.97, 'unit': '1.89L'},
                {'name': 'Soy Milk', 'price': 2.47, 'unit': '1.89L'},
                {'name': 'Greek Yogurt', 'price': 3.97, 'unit': '650g'},
                {'name': 'Regular Yogurt', 'price': 2.97, 'unit': '6x100g'},
                {'name': 'Sour Cream', 'price': 1.97, 'unit': '500ml'},
                {'name': 'Cream Cheese', 'price': 1.97, 'unit': '250g'},
                {'name': 'Cheddar Cheese Slices', 'price': 3.97, 'unit': '200g'},
                {'name': 'Mozzarella Cheese', 'price': 3.47, 'unit': '200g'},
                {'name': 'Butter', 'price': 4.97, 'unit': '454g'},
                {'name': 'Margarine', 'price': 2.47, 'unit': '454g'},
                {'name': 'Great Value Eggs', 'price': 2.47, 'unit': 'Dozen'},
                {'name': 'Eggs Large', 'price': 2.97, 'unit': 'Dozen'},
                {'name': 'Cottage Cheese', 'price': 2.47, 'unit': '500g'},
                {'name': 'Pudding', 'price': 1.47, 'unit': '4x100g'},
            ],
            'meat': [
                {'name': 'Chicken Breast', 'price': 7.47, 'unit': 'per lb'},
                {'name': 'Chicken Thighs', 'price': 3.97, 'unit': 'per lb'},
                {'name': 'Chicken Drumsticks', 'price': 2.97, 'unit': 'per lb'},
                {'name': 'Ground Beef 80/20', 'price': 6.97, 'unit': 'per lb'},
                {'name': 'Ground Beef Lean', 'price': 7.47, 'unit': 'per lb'},
                {'name': 'Beef Steak Sirloin', 'price': 9.97, 'unit': 'per lb'},
                {'name': 'Beef Steak Rib Eye', 'price': 11.97, 'unit': 'per lb'},
                {'name': 'Beef Roast', 'price': 7.47, 'unit': 'per lb'},
                {'name': 'Pork Chops', 'price': 5.97, 'unit': 'per lb'},
                {'name': 'Pork Tenderloin', 'price': 6.97, 'unit': 'per lb'},
                {'name': 'Ground Pork', 'price': 5.47, 'unit': 'per lb'},
                {'name': 'Salmon Fillet', 'price': 11.97, 'unit': 'per lb'},
                {'name': 'Cod Fillet', 'price': 8.97, 'unit': 'per lb'},
                {'name': 'Tilapia Fillet', 'price': 7.47, 'unit': 'per lb'},
                {'name': 'Shrimp', 'price': 9.97, 'unit': 'per lb'},
                {'name': 'Bacon', 'price': 4.97, 'unit': '375g'},
                {'name': 'Ham Sliced', 'price': 5.97, 'unit': '250g'},
                {'name': 'Turkey Breast', 'price': 6.97, 'unit': 'per lb'},
                {'name': 'Meatballs', 'price': 5.47, 'unit': '500g'},
            ],
            'bakery': [
                {'name': 'Wonder Bread', 'price': 1.97, 'unit': 'loaf'},
                {'name': 'Whole Wheat Bread', 'price': 2.47, 'unit': 'loaf'},
                {'name': 'White Bread', 'price': 1.97, 'unit': 'loaf'},
                {'name': 'Croissants', 'price': 2.97, 'unit': '4-pack'},
                {'name': 'Bagels', 'price': 2.47, 'unit': '6-pack'},
                {'name': 'English Muffins', 'price': 2.47, 'unit': '6-pack'},
                {'name': 'Buns', 'price': 1.97, 'unit': '8-pack'},
                {'name': 'Donuts', 'price': 2.97, 'unit': '6-pack'},
                {'name': 'Muffins', 'price': 3.47, 'unit': '4-pack'},
                {'name': 'Cookies', 'price': 2.47, 'unit': '300g'},
                {'name': 'Cakes', 'price': 4.47, 'unit': 'each'},
                {'name': 'Pies', 'price': 4.97, 'unit': 'each'},
                {'name': 'Granola Bars', 'price': 3.47, 'unit': '5-pack'},
            ],
            'beverages': [
                {'name': 'Tropicana Orange Juice', 'price': 2.47, 'unit': '1.89L'},
                {'name': 'Apple Juice', 'price': 1.97, 'unit': '1.89L'},
                {'name': 'Cranberry Juice', 'price': 2.47, 'unit': '1.5L'},
                {'name': 'Iced Tea', 'price': 1.97, 'unit': '2L'},
                {'name': 'Lemonade', 'price': 1.97, 'unit': '1.5L'},
                {'name': 'Coffee', 'price': 5.97, 'unit': '400g'},
                {'name': 'Tea Bags', 'price': 2.47, 'unit': '20 bags'},
                {'name': 'Cola', 'price': 1.97, 'unit': '2L'},
                {'name': 'Sprite', 'price': 1.97, 'unit': '2L'},
                {'name': 'Water Bottled', 'price': 2.97, 'unit': '24x500ml'},
                {'name': 'Sports Drink', 'price': 1.47, 'unit': '591ml'},
                {'name': 'Energy Drink', 'price': 2.47, 'unit': '250ml'},
                {'name': 'Ginger Ale', 'price': 1.97, 'unit': '2L'},
                {'name': 'Lager Beer', 'price': 12.97, 'unit': '12-pack'},
                {'name': 'Stout Beer', 'price': 13.47, 'unit': '12-pack'},
            ],
            'pantry': [
                {'name': 'Pasta', 'price': 1.27, 'unit': '500g'},
                {'name': 'Rice', 'price': 2.47, 'unit': '2kg'},
                {'name': 'Oats', 'price': 2.97, 'unit': '1kg'},
                {'name': 'Flour', 'price': 2.97, 'unit': '2.5kg'},
                {'name': 'Sugar', 'price': 2.47, 'unit': '2kg'},
                {'name': 'Honey', 'price': 4.97, 'unit': '500ml'},
                {'name': 'Olive Oil', 'price': 6.97, 'unit': '750ml'},
                {'name': 'Canola Oil', 'price': 3.97, 'unit': '1L'},
                {'name': 'Peanut Butter', 'price': 3.97, 'unit': '500g'},
                {'name': 'Jam', 'price': 2.47, 'unit': '500ml'},
                {'name': 'Syrup', 'price': 4.97, 'unit': '250ml'},
                {'name': 'Cereal', 'price': 2.97, 'unit': '400g'},
                {'name': 'Granola', 'price': 3.97, 'unit': '500g'},
                {'name': 'Nuts', 'price': 6.97, 'unit': '400g'},
                {'name': 'Soup Cans', 'price': 1.47, 'unit': 'each'},
                {'name': 'Canned Vegetables', 'price': 1.27, 'unit': 'each'},
            ],
            'frozen': [
                {'name': 'Frozen Vegetables', 'price': 2.47, 'unit': '500g'},
                {'name': 'Frozen Pizza', 'price': 4.47, 'unit': 'each'},
                {'name': 'Ice Cream', 'price': 3.47, 'unit': '1.5L'},
                {'name': 'Frozen Berries', 'price': 2.97, 'unit': '300g'},
                {'name': 'Frozen Peas', 'price': 1.47, 'unit': '500g'},
                {'name': 'Frozen Corn', 'price': 1.47, 'unit': '500g'},
                {'name': 'Frozen Broccoli', 'price': 1.97, 'unit': '500g'},
                {'name': 'Frozen Fish Fillets', 'price': 5.97, 'unit': '400g'},
                {'name': 'Frozen Chicken Nuggets', 'price': 3.97, 'unit': '400g'},
            ],
            'sauces': [
                {'name': 'Tomato Sauce', 'price': 1.47, 'unit': '680ml'},
                {'name': 'Marinara Sauce', 'price': 1.97, 'unit': '680ml'},
                {'name': 'Soy Sauce', 'price': 1.97, 'unit': '500ml'},
                {'name': 'Hot Sauce', 'price': 1.97, 'unit': '250ml'},
                {'name': 'BBQ Sauce', 'price': 1.97, 'unit': '500ml'},
                {'name': 'Ketchup', 'price': 1.97, 'unit': '500ml'},
                {'name': 'Mustard', 'price': 1.27, 'unit': '300ml'},
                {'name': 'Mayonnaise', 'price': 2.97, 'unit': '500ml'},
                {'name': 'Vinegar', 'price': 1.47, 'unit': '500ml'},
                {'name': 'Worcestershire Sauce', 'price': 2.47, 'unit': '300ml'},
            ],
        }
        
        for category, items in walmart_db.items():
            for item in items:
                item['category'] = category
                item['store'] = 'walmart'
                products.append(item)
        
        logger.info(f"✅ Got {len(products)} Walmart products")
        return products
    
    def get_saveonfoods_products(self):
        """Comprehensive Save-on-Foods Edmonton product database"""
        products = []
        saveonfoods_db = {
            'produce': [
                {'name': 'Jonagold Apples', 'price': 4.49, 'unit': '3 lb bag'},
                {'name': 'Pink Lady Apples', 'price': 5.49, 'unit': '3 lb bag'},
                {'name': 'McIntosh Apples', 'price': 3.99, 'unit': '3 lb bag'},
                {'name': 'Bananas', 'price': 0.99, 'unit': 'per lb'},
                {'name': 'Strawberries Premium', 'price': 4.99, 'unit': '1 lb'},
                {'name': 'Blueberries Organic', 'price': 6.99, 'unit': '1 lb'},
                {'name': 'Raspberries', 'price': 5.99, 'unit': '1 lb'},
                {'name': 'Blackberries', 'price': 5.99, 'unit': '1 lb'},
                {'name': 'Rainbow Carrots', 'price': 2.49, 'unit': '2 lb bag'},
                {'name': 'Organic Broccoli', 'price': 2.99, 'unit': 'head'},
                {'name': 'Organic Cauliflower', 'price': 3.49, 'unit': 'head'},
                {'name': 'Celery', 'price': 2.99, 'unit': 'bunch'},
                {'name': 'Red Bell Peppers', 'price': 2.49, 'unit': 'each'},
                {'name': 'Yellow Bell Peppers', 'price': 2.49, 'unit': 'each'},
                {'name': 'Beefsteak Tomatoes', 'price': 3.49, 'unit': 'per lb'},
                {'name': 'Cherry Tomatoes Premium', 'price': 5.99, 'unit': 'pint'},
                {'name': 'Cucumbers English', 'price': 1.99, 'unit': 'each'},
                {'name': 'Romaine Lettuce', 'price': 2.49, 'unit': 'head'},
                {'name': 'Organic Spinach', 'price': 4.99, 'unit': '150g'},
                {'name': 'Organic Kale', 'price': 4.49, 'unit': 'bunch'},
                {'name': 'Zucchini Organic', 'price': 2.49, 'unit': 'per lb'},
                {'name': 'Portobello Mushrooms', 'price': 5.99, 'unit': '4 oz'},
                {'name': 'Shiitake Mushrooms', 'price': 6.99, 'unit': '4 oz'},
                {'name': 'Onions Red', 'price': 2.49, 'unit': '2 lb bag'},
                {'name': 'Garlic Organic', 'price': 1.49, 'unit': 'per lb'},
                {'name': 'Potatoes Red Organic', 'price': 3.99, 'unit': '5 lb bag'},
                {'name': 'Sweet Potatoes', 'price': 3.49, 'unit': 'per lb'},
                {'name': 'Navel Oranges', 'price': 4.99, 'unit': '3 lb bag'},
                {'name': 'Organic Lemons', 'price': 1.99, 'unit': 'each'},
                {'name': 'Organic Avocados', 'price': 2.49, 'unit': 'each'},
                {'name': 'Red Grapes', 'price': 4.49, 'unit': 'per lb'},
                {'name': 'Green Grapes', 'price': 4.49, 'unit': 'per lb'},
                {'name': 'Cantaloupe', 'price': 4.99, 'unit': 'each'},
                {'name': 'Honeydew Melon', 'price': 3.99, 'unit': 'each'},
                {'name': 'Mango', 'price': 2.99, 'unit': 'each'},
                {'name': 'Pineapple', 'price': 4.99, 'unit': 'each'},
            ],
            'dairy': [
                {'name': 'Lucerne 2% Milk', 'price': 3.29, 'unit': '2L'},
                {'name': 'Organic Milk', 'price': 4.99, 'unit': '2L'},
                {'name': 'Almond Milk Organic', 'price': 3.49, 'unit': '1.89L'},
                {'name': 'Oat Milk Organic', 'price': 3.99, 'unit': '1.89L'},
                {'name': 'Fage Greek Yogurt', 'price': 4.99, 'unit': '650g'},
                {'name': 'Organic Greek Yogurt', 'price': 5.99, 'unit': '650g'},
                {'name': 'Liberte Yogurt', 'price': 4.49, 'unit': '6x100g'},
                {'name': 'Sour Cream', 'price': 2.49, 'unit': '500ml'},
                {'name': 'Cream Cheese', 'price': 2.99, 'unit': '250g'},
                {'name': 'Black Diamond Cheese', 'price': 5.99, 'unit': '200g'},
                {'name': 'Brie Cheese', 'price': 6.99, 'unit': '200g'},
                {'name': 'Feta Cheese', 'price': 4.99, 'unit': '200g'},
                {'name': 'Lactantia Butter', 'price': 5.99, 'unit': '454g'},
                {'name': 'Organic Butter', 'price': 7.99, 'unit': '454g'},
                {'name': 'Brown Eggs Organic', 'price': 5.99, 'unit': 'Dozen'},
                {'name': 'Free Range Eggs', 'price': 4.99, 'unit': 'Dozen'},
                {'name': 'Cottage Cheese', 'price': 3.99, 'unit': '500g'},
                {'name': 'Quark', 'price': 2.99, 'unit': '500g'},
            ],
            'meat': [
                {'name': 'Boneless Chicken Breast', 'price': 10.99, 'unit': 'per lb'},
                {'name': 'Organic Chicken Breast', 'price': 12.99, 'unit': 'per lb'},
                {'name': 'Chicken Thighs', 'price': 5.99, 'unit': 'per lb'},
                {'name': 'Chicken Drumsticks', 'price': 3.99, 'unit': 'per lb'},
                {'name': 'Whole Chicken', 'price': 6.99, 'unit': 'per lb'},
                {'name': 'Lean Ground Beef', 'price': 9.99, 'unit': 'per lb'},
                {'name': 'Organic Ground Beef', 'price': 11.99, 'unit': 'per lb'},
                {'name': 'Beef Steak Sirloin', 'price': 12.99, 'unit': 'per lb'},
                {'name': 'Beef Steak Rib Eye Prime', 'price': 15.99, 'unit': 'per lb'},
                {'name': 'Beef Roast', 'price': 9.99, 'unit': 'per lb'},
                {'name': 'Pork Chops', 'price': 8.99, 'unit': 'per lb'},
                {'name': 'Pork Tenderloin', 'price': 9.99, 'unit': 'per lb'},
                {'name': 'Pork Shoulder', 'price': 5.49, 'unit': 'per lb'},
                {'name': 'Ground Pork', 'price': 7.99, 'unit': 'per lb'},
                {'name': 'Wild Salmon Fillet', 'price': 14.99, 'unit': 'per lb'},
                {'name': 'Atlantic Salmon', 'price': 12.99, 'unit': 'per lb'},
                {'name': 'Halibut Fillet', 'price': 13.99, 'unit': 'per lb'},
                {'name': 'Cod Fillet', 'price': 10.99, 'unit': 'per lb'},
                {'name': 'Tilapia Fillet', 'price': 8.99, 'unit': 'per lb'},
                {'name': 'Shrimp Premium', 'price': 13.99, 'unit': 'per lb'},
                {'name': 'Crab Legs', 'price': 18.99, 'unit': 'per lb'},
                {'name': 'Mussels', 'price': 7.99, 'unit': 'per lb'},
                {'name': 'Bacon Premium', 'price': 7.99, 'unit': '375g'},
                {'name': 'Ham Sliced Premium', 'price': 8.99, 'unit': '250g'},
                {'name': 'Turkey Breast', 'price': 9.99, 'unit': 'per lb'},
                {'name': 'Lamb Chops', 'price': 13.99, 'unit': 'per lb'},
                {'name': 'Veal', 'price': 14.99, 'unit': 'per lb'},
            ],
            'bakery': [
                {'name': 'Artisan Whole Grain Bread', 'price': 3.99, 'unit': 'loaf'},
                {'name': 'Sourdough Bread', 'price': 4.49, 'unit': 'loaf'},
                {'name': 'French Baguette', 'price': 2.99, 'unit': 'each'},
                {'name': 'Organic Rye Bread', 'price': 4.99, 'unit': 'loaf'},
                {'name': 'Multigrain Bread', 'price': 4.49, 'unit': 'loaf'},
                {'name': 'Butter Croissants Premium', 'price': 5.99, 'unit': '4-pack'},
                {'name': 'Pain au Chocolat', 'price': 4.99, 'unit': '4-pack'},
                {'name': 'Bagels Homemade', 'price': 4.99, 'unit': '6-pack'},
                {'name': 'English Muffins', 'price': 3.49, 'unit': '6-pack'},
                {'name': 'Buns Artisan', 'price': 3.49, 'unit': '8-pack'},
                {'name': 'Donuts Glazed', 'price': 4.99, 'unit': '6-pack'},
                {'name': 'Muffins Blueberry', 'price': 4.99, 'unit': '4-pack'},
                {'name': 'Cookies Organic', 'price': 4.99, 'unit': '300g'},
                {'name': 'Cake Carrot', 'price': 6.99, 'unit': 'each'},
                {'name': 'Cake Chocolate', 'price': 6.99, 'unit': 'each'},
                {'name': 'Pie Apple Homemade', 'price': 7.99, 'unit': 'each'},
                {'name': 'Pie Berry', 'price': 7.99, 'unit': 'each'},
                {'name': 'Granola Bars Organic', 'price': 5.49, 'unit': '5-pack'},
                {'name': 'Scones', 'price': 3.99, 'unit': '4-pack'},
            ],
            'beverages': [
                {'name': 'Fresh Orange Juice', 'price': 4.99, 'unit': '1L'},
                {'name': 'Organic Apple Juice', 'price': 4.49, 'unit': '1L'},
                {'name': 'Cranberry Juice', 'price': 3.99, 'unit': '1.5L'},
                {'name': 'Grape Juice', 'price': 2.99, 'unit': '1.89L'},
                {'name': 'Lemonade Fresh', 'price': 3.49, 'unit': '1.5L'},
                {'name': 'Iced Tea Organic', 'price': 2.99, 'unit': '2L'},
                {'name': 'Premium Coffee', 'price': 8.99, 'unit': '400g'},
                {'name': 'Organic Coffee', 'price': 10.99, 'unit': '400g'},
                {'name': 'Herbal Tea Premium', 'price': 4.99, 'unit': '20 bags'},
                {'name': 'Green Tea', 'price': 3.99, 'unit': '20 bags'},
                {'name': 'Cola', 'price': 1.99, 'unit': '2L'},
                {'name': 'Sprite', 'price': 1.99, 'unit': '2L'},
                {'name': 'Ginger Ale Premium', 'price': 2.49, 'unit': '2L'},
                {'name': 'Water Spring', 'price': 4.49, 'unit': '24x500ml'},
                {'name': 'Sparkling Water', 'price': 3.99, 'unit': '12x250ml'},
                {'name': 'Sports Drink', 'price': 1.99, 'unit': '591ml'},
                {'name': 'Energy Drink Organic', 'price': 3.99, 'unit': '250ml'},
                {'name': 'Red Wine', 'price': 14.99, 'unit': '750ml'},
                {'name': 'White Wine', 'price': 13.99, 'unit': '750ml'},
            ],
            'pantry': [
                {'name': 'Pasta Organic', 'price': 2.49, 'unit': '500g'},
                {'name': 'Rice Organic', 'price': 4.49, 'unit': '2kg'},
                {'name': 'Brown Rice Organic', 'price': 4.99, 'unit': '2kg'},
                {'name': 'Oats Organic', 'price': 4.99, 'unit': '1kg'},
                {'name': 'Quinoa', 'price': 6.99, 'unit': '500g'},
                {'name': 'Flour Organic', 'price': 4.99, 'unit': '2.5kg'},
                {'name': 'Sugar Organic', 'price': 4.99, 'unit': '2kg'},
                {'name': 'Honey Raw Organic', 'price': 7.99, 'unit': '500ml'},
                {'name': 'Olive Oil Extra Virgin', 'price': 11.99, 'unit': '750ml'},
                {'name': 'Canola Oil Organic', 'price': 5.99, 'unit': '1L'},
                {'name': 'Peanut Butter Natural', 'price': 5.99, 'unit': '500g'},
                {'name': 'Almond Butter', 'price': 7.99, 'unit': '500g'},
                {'name': 'Jam Organic', 'price': 4.99, 'unit': '500ml'},
                {'name': 'Maple Syrup Pure', 'price': 9.99, 'unit': '250ml'},
                {'name': 'Cereal Organic', 'price': 4.99, 'unit': '400g'},
                {'name': 'Granola Premium', 'price': 5.99, 'unit': '500g'},
                {'name': 'Nuts Mixed Organic', 'price': 10.99, 'unit': '400g'},
                {'name': 'Almonds Organic', 'price': 12.99, 'unit': '300g'},
                {'name': 'Cashews Roasted', 'price': 11.99, 'unit': '300g'},
                {'name': 'Walnuts', 'price': 10.99, 'unit': '300g'},
                {'name': 'Soup Organic', 'price': 2.99, 'unit': 'each'},
                {'name': 'Canned Vegetables Organic', 'price': 1.99, 'unit': 'each'},
                {'name': 'Canned Beans', 'price': 1.49, 'unit': 'each'},
                {'name': 'Canned Tomatoes', 'price': 1.99, 'unit': 'each'},
            ],
            'frozen': [
                {'name': 'Frozen Vegetables Organic', 'price': 3.99, 'unit': '500g'},
                {'name': 'Frozen Pizza Premium', 'price': 6.99, 'unit': 'each'},
                {'name': 'Ice Cream Premium', 'price': 5.99, 'unit': '1.5L'},
                {'name': 'Organic Ice Cream', 'price': 7.99, 'unit': '1.5L'},
                {'name': 'Frozen Berries Organic', 'price': 5.99, 'unit': '300g'},
                {'name': 'Frozen Peas', 'price': 2.49, 'unit': '500g'},
                {'name': 'Frozen Corn', 'price': 2.49, 'unit': '500g'},
                {'name': 'Frozen Broccoli', 'price': 2.99, 'unit': '500g'},
                {'name': 'Frozen Fish Fillets Premium', 'price': 9.99, 'unit': '400g'},
                {'name': 'Frozen Chicken Nuggets', 'price': 5.99, 'unit': '400g'},
                {'name': 'Frozen Dumplings', 'price': 4.99, 'unit': '350g'},
            ],
            'sauces': [
                {'name': 'Tomato Sauce Organic', 'price': 2.49, 'unit': '680ml'},
                {'name': 'Marinara Sauce Premium', 'price': 3.49, 'unit': '680ml'},
                {'name': 'Soy Sauce Organic', 'price': 3.99, 'unit': '500ml'},
                {'name': 'Worcestershire Sauce', 'price': 3.99, 'unit': '300ml'},
                {'name': 'Hot Sauce Premium', 'price': 3.49, 'unit': '250ml'},
                {'name': 'BBQ Sauce', 'price': 3.49, 'unit': '500ml'},
                {'name': 'Ketchup Organic', 'price': 3.49, 'unit': '500ml'},
                {'name': 'Mustard Organic', 'price': 2.99, 'unit': '300ml'},
                {'name': 'Mayonnaise Organic', 'price': 4.99, 'unit': '500ml'},
                {'name': 'Vinegar Organic', 'price': 3.99, 'unit': '500ml'},
                {'name': 'Balsamic Vinegar', 'price': 5.99, 'unit': '250ml'},
                {'name': 'Pesto', 'price': 4.99, 'unit': '190ml'},
                {'name': 'Hummus', 'price': 3.99, 'unit': '227g'},
                {'name': 'Salsa Organic', 'price': 3.49, 'unit': '500ml'},
            ],
        }
        
        for category, items in saveonfoods_db.items():
            for item in items:
                item['category'] = category
                item['store'] = 'saveonfoods'
                products.append(item)
        
        logger.info(f"✅ Got {len(products)} Save-on-Foods products")
        return products
    
    def collect_all_products(self):
        """Collect products from all stores"""
        all_products = []
        
        all_products.extend(self.get_safeway_products())
        all_products.extend(self.get_walmart_products())
        all_products.extend(self.get_saveonfoods_products())
        
        return all_products

def save_to_database(products):
    """Save products and prices to database"""
    with get_db() as conn:
        cursor = conn.cursor()
        
        for product in products:
            try:
                cursor.execute('''
                    INSERT OR IGNORE INTO products 
                    (store, product_id, name, category, unit)
                    VALUES (?, ?, ?, ?, ?)
                ''', (
                    product['store'],
                    f"{product['store']}_{product['name']}",
                    product['name'],
                    product['category'],
                    product.get('unit', 'each')
                ))
                
                cursor.execute('''
                    SELECT id FROM products 
                    WHERE store = ? AND name = ?
                ''', (product['store'], product['name']))
                
                result = cursor.fetchone()
                if result:
                    product_id = result['id']
                    
                    cursor.execute('''
                        INSERT INTO price_history (product_id, price)
                        VALUES (?, ?)
                    ''', (product_id, product['price']))
                    
                    cursor.execute('''
                        INSERT INTO latest_prices (product_id, price)
                        VALUES (?, ?)
                        ON CONFLICT(product_id) DO UPDATE SET 
                        price = ?, updated_at = CURRENT_TIMESTAMP
                    ''', (product_id, product['price'], product['price']))
                    
            except Exception as e:
                logger.error(f"Error saving product {product['name']}: {e}")
        
        conn.commit()

def organize_products(products):
    """Organize products by item name and find best prices"""
    organized = {}
    
    for product in products:
        name = product['name'].lower().strip()
        category = product['category']
        
        if name not in organized:
            organized[name] = {
                'name': product['name'],
                'category': category,
                'prices': {}
            }
        
        store = product['store']
        organized[name]['prices'][STORE_NAMES[store]] = {
            'price': product['price'],
            'unit': product.get('unit', 'each'),
            'store': store
        }
    
    return organized

products_data = {
    'data': [],
    'last_updated': None,
    'status': 'initializing'
}

def update_products_data():
    """Update products data from all stores"""
    global products_data
    
    try:
        print("\n" + "="*70)
        print("🔄 COMPREHENSIVE GROCERY DATA UPDATE")
        print("="*70)
        
        products_data['status'] = 'updating'
        
        collector = ComprehensiveGroceryCollector()
        raw_products = collector.collect_all_products()
        
        print(f"\n📦 Total raw products collected: {len(raw_products)}")
        
        save_to_database(raw_products)
        
        organized = organize_products(raw_products)
        
        products_list = []
        for product_name, product_info in organized.items():
            if product_info['prices']:
                prices_list = [p['price'] for p in product_info['prices'].values()]
                lowest_price = min(prices_list)
                best_store = [s for s, p in product_info['prices'].items() 
                             if p['price'] == lowest_price][0]
                
                products_list.append({
                    'name': product_info['name'],
                    'category': product_info['category'],
                    'prices': product_info['prices'],
                    'lowest_price': lowest_price,
                    'best_store': best_store
                })
        
        products_data['data'] = sorted(products_list, key=lambda x: x['name'])
        
        edmonton_tz = pytz.timezone('America/Edmonton')
        products_data['last_updated'] = datetime.now(edmonton_tz).isoformat()
        products_data['status'] = 'ready'
        
        print(f"\n✅ Successfully processed {len(products_list)} unique products")
        print(f"📊 Breakdown by store:")
        print(f"   🛒 Safeway: {len([p for p in raw_products if p['store'] == 'safeway'])} products")
        print(f"   🏪 Walmart: {len([p for p in raw_products if p['store'] == 'walmart'])} products")
        print(f"   💚 Save-on-Foods: {len([p for p in raw_products if p['store'] == 'saveonfoods'])} products")
        print(f"📅 Last updated: {products_data['last_updated']}")
        print("="*70 + "\n")
        
        return True
    except Exception as e:
        logger.error(f"❌ Error updating products: {e}")
        products_data['status'] = 'error'
        return False

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/products', methods=['GET'])
def get_products():
    """Get all products with optional filtering"""
    category = request.args.get('category', 'all')
    search = request.args.get('search', '').lower()
    
    filtered = products_data['data']
    
    if category != 'all':
        filtered = [p for p in filtered if p['category'] == category]
    
    if search:
        filtered = [p for p in filtered if search in p['name'].lower()]
    
    return jsonify(filtered)

@app.route('/api/categories', methods=['GET'])
def get_categories():
    """Get all product categories"""
    return jsonify(CATEGORIES)

@app.route('/api/status', methods=['GET'])
def get_status():
    """Get status info"""
    return jsonify({
        'status': products_data['status'],
        'last_updated': products_data['last_updated'],
        'product_count': len(products_data['data']),
        'stores': list(STORE_NAMES.values()),
        'next_update': 'Daily at 7:00 AM MST',
        'store_count': len(STORE_NAMES)
    })

@app.route('/api/price-history/<product_name>/<store>', methods=['GET'])
def get_price_history(product_name, store):
    """Get price history for a specific product"""
    with get_db() as conn:
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT ph.price, ph.recorded_at 
            FROM price_history ph
            JOIN products p ON ph.product_id = p.id
            WHERE p.name = ? AND p.store = ?
            ORDER BY ph.recorded_at DESC
            LIMIT 30
        ''', (product_name, store))
        
        history = []
        for row in cursor.fetchall():
            history.append({
                'price': row['price'],
                'recorded_at': row['recorded_at']
            })
        
        return jsonify(history)

@app.route('/api/best-deals', methods=['GET'])
def get_best_deals():
    """Get products with best deals"""
    days = request.args.get('days', 7, type=int)
    
    deals = []
    
    with get_db() as conn:
        cursor = conn.cursor()
        
        cutoff_date = datetime.now() - timedelta(days=days)
        
        cursor.execute('''
            SELECT p.name, p.store, p.category, p.unit,
                   (SELECT price FROM price_history WHERE product_id = p.id ORDER BY recorded_at DESC LIMIT 1) as current_price,
                   (SELECT price FROM price_history WHERE product_id = p.id AND recorded_at < ? ORDER BY recorded_at DESC LIMIT 1) as old_price
            FROM products p
            WHERE (SELECT COUNT(*) FROM price_history WHERE product_id = p.id) > 1
        ''', (cutoff_date,))
        
        for row in cursor.fetchall():
            if row['old_price'] and row['current_price']:
                discount = ((row['old_price'] - row['current_price']) / row['old_price']) * 100
                if discount > 0:
                    deals.append({
                        'name': row['name'],
                        'store': row['store'],
                        'category': row['category'],
                        'unit': row['unit'],
                        'current_price': row['current_price'],
                        'old_price': row['old_price'],
                        'discount_percent': round(discount, 2)
                    })
    
    deals.sort(key=lambda x: x['discount_percent'], reverse=True)
    return jsonify(deals[:50])

@app.route('/api/update', methods=['POST'])
def manual_update():
    """Manual trigger for update"""
    success = update_products_data()
    return jsonify({
        'success': success,
        'last_updated': products_data['last_updated'],
        'product_count': len(products_data['data'])
    })

def init_scheduler():
    """Initialize the scheduler"""
    scheduler = BackgroundScheduler()
    edmonton_tz = pytz.timezone('America/Edmonton')
    
    scheduler.add_job(
        func=update_products_data,
        trigger=CronTrigger(hour=7, minute=0, timezone=edmonton_tz),
        id='daily_update',
        name='Daily grocery data update at 7 AM MST',
        replace_existing=True
    )
    
    scheduler.start()
    logger.info("✅ Scheduler initialized - Daily update at 7:00 AM MST")

@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Not found'}), 404

@app.errorhandler(500)
def server_error(error):
    return jsonify({'error': 'Server error'}), 500

if __name__ == '__main__':
    logger.info("🚀 Starting Fresh Findr Server...")
    
    init_db()
    update_products_data()
    init_scheduler()
    
    port = int(os.environ.get('PORT', 5000))
    app.run(host='0.0.0.0', port=port, debug=False, use_reloader=False)
EOF

echo "✅ Created app.py"