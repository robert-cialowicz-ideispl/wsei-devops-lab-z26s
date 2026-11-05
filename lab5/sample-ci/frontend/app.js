// Simple Product Manager App

const API_URL = 'http://localhost:5000/api/products';

async function loadProducts() {
    try {
        const response = await fetch(API_URL);
        const products = await response.json();
        displayProducts(products);
    } catch (error) {
        console.error('Error loading products:', error);
        document.getElementById('products').innerHTML = '<p>Error loading products</p>';
    }
}

function displayProducts(products) {
    const container = document.getElementById('products');

    if (products.length === 0) {
        container.innerHTML = '<p>No products found</p>';
        return;
    }

    container.innerHTML = products.map(product => `
        <div class="product-item">
            <strong>${product.name}</strong> - $${product.price.toFixed(2)}
        </div>
    `).join('');
}

// Load products on page load
document.addEventListener('DOMContentLoaded', loadProducts);
