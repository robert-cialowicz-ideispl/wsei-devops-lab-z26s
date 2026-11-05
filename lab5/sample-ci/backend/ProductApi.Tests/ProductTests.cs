using Xunit;

namespace ProductApi.Tests;

public class ProductTests
{
    [Fact]
    public void Product_Should_Have_Valid_Id()
    {
        // Arrange
        var product = new Product { Id = 1, Name = "Test Product", Price = 99.99m };

        // Act & Assert
        Assert.True(product.Id > 0);
    }

    [Fact]
    public void Product_Should_Have_Valid_Name()
    {
        // Arrange
        var product = new Product { Id = 1, Name = "Test Product", Price = 99.99m };

        // Act & Assert
        Assert.False(string.IsNullOrEmpty(product.Name));
        Assert.Equal("Test Product", product.Name);
    }

    [Fact]
    public void Product_Should_Have_Valid_Price()
    {
        // Arrange
        var product = new Product { Id = 1, Name = "Test Product", Price = 99.99m };

        // Act & Assert
        Assert.True(product.Price > 0);
        Assert.Equal(99.99m, product.Price);
    }

    [Theory]
    [InlineData(1, "Laptop", 999.99)]
    [InlineData(2, "Mouse", 29.99)]
    [InlineData(3, "Keyboard", 49.99)]
    public void Product_Should_Be_Created_With_Valid_Data(int id, string name, decimal price)
    {
        // Arrange & Act
        var product = new Product { Id = id, Name = name, Price = price };

        // Assert
        Assert.Equal(id, product.Id);
        Assert.Equal(name, product.Name);
        Assert.Equal(price, product.Price);
    }
}
