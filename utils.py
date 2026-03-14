from app import db, Product, Price, Store
from datetime import datetime
import random

def fetch_and_update_prices():
    """
    Fetch prices from stores and update the database
    Replace this with actual API calls to real store APIs
    """
    try:
        # Get all products and stores
        products = Product.query.all()
        stores = Store.query.all()
        
        for product in products:
            for store in stores:
                # Simulate price fetching with slight variation
                # In production, replace with actual API calls
                base_price = get_base_price(product.name, store.name)
                price_variation = random.uniform(0.95, 1.05)  # 5% variation
                new_price = round(base_price * price_variation, 2)
                
                # Update or create price
                price_record = Price.query.filter_by(
                    product_id=product.id,
                    store_id=store.id
                ).first()
                
                if price_record:
                    price_record.price = new_price
                    price_record.date_updated = datetime.utcnow()
                else:
                    price_record = Price(
                        product_id=product.id,
                        store_id=store.id,
                        price=new_price
                    )
                    db.session.add(price_record)
            
            # Update product's last_updated timestamp
            product.last_updated = datetime.utcnow()
        
        db.session.commit()
        return True
    except Exception as e:
        print(f"Error updating prices: {str(e)}")
        db.session.rollback()
        return False

def get_base_price(product_name, store_name):
    """Get base price for a product at a store"""
    # Base prices for sample data
    base_prices = {
        'Organic Apples': {'Fresh Market': 3.99, 'SuperMart': 4.49, 'Quick Shop': 3.79},
        'Carrots Bundle': {'Fresh Market': 1.99, 'SuperMart': 2.29, 'Quick Shop': 1.79},
        'Greek Yogurt': {'Fresh Market': 4.99, 'SuperMart': 4.79, 'Quick Shop': 5.29},
        'Chicken Breast': {'Fresh Market': 8.99, 'SuperMart': 8.49, 'Quick Shop': 9.49},
        'Whole Wheat Bread': {'Fresh Market': 3.49, 'SuperMart': 3.29, 'Quick Shop': 3.99},
        'Bananas': {'Fresh Market': 0.99, 'SuperMart': 1.29, 'Quick Shop': 0.89},
        'Broccoli': {'Fresh Market': 2.99, 'SuperMart': 3.49, 'Quick Shop': 2.79},
        'Cheddar Cheese': {'Fresh Market': 6.99, 'SuperMart': 7.49, 'Quick Shop': 6.49},
    }
    
    return base_prices.get(product_name, {}).get(store_name, 5.00)