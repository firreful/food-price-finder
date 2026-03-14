let currentFilter = 'all';
let allProducts = [];
let allCategories = {};

document.addEventListener('DOMContentLoaded', function() {
    loadCategories();
    loadStatus();
    loadProducts();
});

function loadCategories() {
    fetch('/api/categories')
        .then(res => res.json())
        .then(categories => {
            allCategories = categories;
            renderCategoryFilters(categories);
        })
        .catch(err => console.error('Error loading categories:', err));
}

function renderCategoryFilters(categories) {
    const container = document.getElementById('categoriesContainer');
    
    let html = `<button class="filter-btn active" onclick="filterByCategory('all')">
                    <i class="fas fa-th"></i> All Products
                </button>`;
    
    for (const [key, label] of Object.entries(categories)) {
        html += `<button class="filter-btn" onclick="filterByCategory('${key}')">
                    ${label}
                </button>`;
    }
    
    container.innerHTML = html;
}

function loadStatus() {
    fetch('/api/status')
        .then(res => res.json())
        .then(data => {
            const banner = document.getElementById('statusBanner');
            if (data.last_updated) {
                const lastUpdate = new Date(data.last_updated);
                const formattedDate = lastUpdate.toLocaleString('en-CA', {
                    month: 'short',
                    day: 'numeric',
                    year: 'numeric',
                    hour: '2-digit',
                    minute: '2-digit',
                    timeZone: 'America/Edmonton'
                });
                
                banner.innerHTML = `
                    <i class="fas fa-check-circle"></i>
                    <div class="status-text">
                        <span><strong>${data.product_count}</strong> products from <strong>3 Edmonton stores</strong> | Last updated: <strong>${formattedDate} MST</strong></span>
                    </div>
                `;
            }
            
            document.getElementById('productCount').textContent = data.product_count;
        })
        .catch(err => console.error('Error loading status:', err));
}

function loadProducts() {
    const params = new URLSearchParams();
    if (currentFilter !== 'all') {
        params.append('category', currentFilter);
    }
    
    fetch(`/api/products?${params.toString()}`)
        .then(res => res.json())
        .then(products => {
            allProducts = products;
            renderProducts(products);
        })
        .catch(err => {
            console.error('Error loading products:', err);
            document.getElementById('productsGrid').innerHTML = '<div style="text-align:center;padding:2rem;">Error loading products</div>';
        });
}

function renderProducts(products) {
    const grid = document.getElementById('productsGrid');
    
    if (products.length === 0) {
        grid.innerHTML = `
            <div style="text-align:center;padding:2rem;color:#64748b;">
                <i class="fas fa-search" style="font-size:2rem;margin-bottom:1rem;display:block;"></i>
                <p>No products found</p>
            </div>
        `;
        return;
    }
    
    grid.innerHTML = products.map((p, idx) => {
        const categoryLabel = allCategories[p.category] || p.category;
        
        return `
            <div class="product-card" style="animation: fadeInUp ${0.5 + idx * 0.05}s ease;">
                <div style="background: linear-gradient(135deg, #34AE61, #2d9655); height: 200px; display: flex; align-items: center; justify-content: center; font-size: 4rem;">
                    ${p.name.includes('Milk') ? '🥛' : p.name.includes('Bread') ? '🍞' : p.name.includes('Chicken') || p.name.includes('Beef') || p.name.includes('Pork') || p.name.includes('Salmon') ? '🍗' : p.name.includes('Juice') || p.name.includes('Coffee') ? '🥤' : '🍎'}
                </div>
                <div style="padding: 1.8rem;">
                    <div style="font-size:1.1rem;font-weight:800;margin-bottom:0.5rem;">${p.name}</div>
                    <span style="display:inline-block;background:rgba(52, 174, 97, 0.1);color:#34AE61;padding:0.4rem 0.9rem;border-radius:0.5rem;font-size:0.75rem;font-weight:700;text-transform:uppercase;margin-bottom:1rem;">${categoryLabel}</span>
                    <div style="background:linear-gradient(135deg, #34AE61, #2d9655);color:white;padding:1.2rem;border-radius:0.9rem;text-align:center;font-weight:700;margin-bottom:1rem;">
                        <div style="font-size:1.8rem;margin-bottom:0.3rem;">$${p.lowest_price.toFixed(2)}</div>
                        <div style="font-size:0.85rem;opacity:0.9;">⭐ ${p.best_store}</div>
                    </div>
                    <div style="display:flex;flex-direction:column;gap:0.8rem;">
                        ${Object.entries(p.prices).map(([store, priceData]) => `
                            <div style="display:flex;justify-content:space-between;align-items:center;padding:0.8rem 0;border-bottom:1px solid rgba(52, 174, 97, 0.08);">
                                <span style="font-weight:600;">${store}</span>
                                <div style="display:flex;align-items:center;gap:0.7rem;">
                                    <span style="color:#34AE61;font-weight:800;font-size:1rem;">$${priceData.price.toFixed(2)}</span>
                                    ${priceData.price === p.lowest_price ? '<span style="background:linear-gradient(135deg, #34AE61, #2d9655);color:white;padding:0.2rem 0.6rem;border-radius:0.4rem;font-size:0.65rem;font-weight:800;text-transform:uppercase;">BEST</span>' : ''}
                                </div>
                            </div>
                        `).join('')}
                    </div>
                </div>
            </div>
        `;
    }).join('');
}

function filterByCategory(category) {
    currentFilter = category;
    document.querySelectorAll('.filter-btn').forEach(btn => btn.classList.remove('active'));
    event.target.closest('.filter-btn').classList.add('active');
    applyFilters();
}

function filterSearch() {
    applyFilters();
}

function applyFilters() {
    const search = document.getElementById('searchInput').value.toLowerCase();
    const sortValue = document.querySelector('.sort-select').value;
    
    let filtered = allProducts;
    
    if (search) {
        filtered = filtered.filter(p => p.name.toLowerCase().includes(search));
    }
    
    if (sortValue === 'price-low') {
        filtered.sort((a, b) => a.lowest_price - b.lowest_price);
    } else if (sortValue === 'price-high') {
        filtered.sort((a, b) => b.lowest_price - a.lowest_price);
    } else if (sortValue === 'name') {
        filtered.sort((a, b) => a.name.localeCompare(b.name));
    }
    
    renderProducts(filtered);
}

function toggleTheme() {
    document.body.classList.toggle('dark-mode');
    localStorage.setItem('theme', document.body.classList.contains('dark-mode') ? 'dark' : 'light');
}

if (localStorage.getItem('theme') === 'dark') {
    document.body.classList.add('dark-mode');
}