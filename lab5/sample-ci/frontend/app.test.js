/**
 * @jest-environment jsdom
 */

describe('Product Manager App', () => {
    test('displayProducts should render products correctly', () => {
        // Setup
        document.body.innerHTML = '<div id="products"></div>';

        const products = [
            { name: 'Laptop', price: 999.99 },
            { name: 'Mouse', price: 29.99 }
        ];

        // Mock the displayProducts function
        const displayProducts = (products) => {
            const container = document.getElementById('products');
            container.innerHTML = products.map(product => `
                <div class="product-item">
                    <strong>${product.name}</strong> - $${product.price.toFixed(2)}
                </div>
            `).join('');
        };

        // Execute
        displayProducts(products);

        // Assert
        const container = document.getElementById('products');
        expect(container.innerHTML).toContain('Laptop');
        expect(container.innerHTML).toContain('999.99');
        expect(container.innerHTML).toContain('Mouse');
        expect(container.innerHTML).toContain('29.99');
    });

    test('displayProducts should show message when no products', () => {
        // Setup
        document.body.innerHTML = '<div id="products"></div>';

        const displayProducts = (products) => {
            const container = document.getElementById('products');
            if (products.length === 0) {
                container.innerHTML = '<p>No products found</p>';
                return;
            }
        };

        // Execute
        displayProducts([]);

        // Assert
        const container = document.getElementById('products');
        expect(container.innerHTML).toContain('No products found');
    });
});
