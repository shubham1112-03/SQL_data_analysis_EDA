-- ADVANCE DATA ANALYSIS 
--==========================================================================================================================
-- A) CHANGE OVER TIME ANALYSIS 

-- Q) Calculate total sales by year 
	SELECT 
		YEAR(order_date) [year of sales],
		SUM(sales_amount) AS Total_sales,
		COUNT(DISTINCT customer_key) AS total_customers,
		SUM(quantity) AS total_quantity
	FROM gold.fact_sales
	WHERE order_date IS NOT NULL
	GROUP BY YEAR(order_date)
	ORDER BY YEAR(order_date) ASC

-- Q) calculate total sales by year, month
	SELECT 
		YEAR(order_date)[order year],
		DATENAME(MONTH,order_date) [order month],
		SUM(sales_amount) [total sales],
		COUNT(DISTINCT customer_key) [total customers],
		SUM(quantity) [total quantity]
	FROM gold.fact_sales
	WHERE order_date IS NOT NULL
	GROUP BY DATENAME(MONTH,order_date) ,YEAR(order_date)
	ORDER BY DATENAME(MONTH,order_date) ,YEAR(order_date)

-- using DATETRUNC (output is a date)
    SELECT 
		DATETRUNC(MONTH,order_date)[order by DATETRUNC],
		SUM(sales_amount) [total sales],
		COUNT(DISTINCT customer_key) [total customers],
		SUM(quantity) [total quantity]
	FROM gold.fact_sales
	WHERE order_date IS NOT NULL
	GROUP BY DATETRUNC(MONTH,order_date)
	ORDER BY DATETRUNC(MONTH,order_date)


-- using FORMAT (string value is the output)
    SELECT 
		FORMAT(order_date, 'MMM-yyyy')[order by FORMAT],
		SUM(sales_amount) [total sales],
		COUNT(DISTINCT customer_key) [total customers],
		SUM(quantity) [total quantity]
	FROM gold.fact_sales
	WHERE order_date IS NOT NULL
	GROUP BY FORMAT(order_date, 'MMM-yyyy')
	ORDER BY FORMAT(order_date, 'MMM-yyyy')
--===================================================================================================================================

-- B) CUMULATIVE ANALYSIS

--Q) calculate the total sales per month 
  -- and the running total of sales over time 


SELECT 
[order date by month],
[total sales],
SUM([total sales]) OVER(ORDER BY [order date by month]) AS running_total
FROM
(
	SELECT 
		DATETRUNC(MONTH,order_date) [order date by month],
		SUM(sales_amount) [total sales] 
	FROM gold.fact_sales
	WHERE order_date IS NOT NULL 
	GROUP BY DATETRUNC(MONTH,order_date)
)T

--==================================================================

-- C) PERFORMANCE ANALYSIS 

-- Q) Analyze the yearly performance of products 
   -- by comparing each products sales to both
   -- its average sales performance and the previous years sales 
WITH Yearly_product_sales AS(
	SELECT
		YEAR(sls.order_date) AS order_year,
		pr.product_name,	
		SUM(sls.sales_amount) AS total_sales
	FROM gold.fact_sales AS sls
	LEFT JOIN gold.dim_products AS pr
	ON sls.product_key = pr.product_key
	WHERE sls.order_date IS NOT NULL
	GROUP BY YEAR(sls.order_date),pr.product_name
)
SELECT 
	 order_year,
	 product_name,
	 total_sales, 
	 AVG(total_sales) OVER(PARTITION BY product_name) AS avg_sales,
	 total_sales - AVG(total_sales) OVER(PARTITION BY product_name) AS avg_diff ,
	 CASE WHEN total_sales - AVG(total_sales) OVER(PARTITION BY product_name) > 0 THEN 'ABOVE AVG'
		  WHEN total_sales - AVG(total_sales) OVER(PARTITION BY product_name) > 0 THEN 'BELOW AVG'
		  ELSE 'AVG'
	 END AVG_CHANGE,
	 -- YEAR OVER YEAR ANALYSIS
	 LAG(total_sales) OVER(PARTITION BY product_name ORDER BY order_year) as previous_year,
	 total_sales - LAG(total_sales) OVER(PARTITION BY product_name ORDER BY order_year) AS difference_in_sales,
	 CASE WHEN total_sales - LAG(total_sales) OVER(PARTITION BY product_name ORDER BY order_year) > 0 THEN 'INCREASE'
		  WHEN total_sales -LAG(total_sales) OVER(PARTITION BY product_name ORDER BY order_year) < 0 THEN 'DECREASE'
		  ELSE 'NO change'
	 END FLAG_difference 
FROM Yearly_product_sales
ORDER BY product_name , order_year



--===================================================================================================================================

-- D) PART TO WHOLE ANALYSIS

-- Q)which category contributes the most of the overall sales ?

WITH category_contribution AS
(
	SELECT 
		pr.category AS product_category,
		SUM(sls.sales_amount) AS total_sales
	FROM gold.dim_products AS pr
	LEFT JOIN gold.fact_sales sls
	ON pr.product_key = sls.product_key
	WHERE sales_amount IS NOT NULL
	GROUP BY pr.category
)
SELECT 
product_category,
total_sales,
SUM(total_sales) OVER() AS grand_total ,
CONCAT(ROUND((CAST(total_sales AS FLOAT) / SUM(total_sales) OVER())  * 100 , 2) , '%')AS percentage_contribution
FROM category_contribution
ORDER BY total_sales DESC


--===================================================================================================================================

-- E) DATA SEGMENTATION 

-- Q) Segment products into cost ranges and 
  --  count how many products fall into this segment ?
WITH segment_product AS 
(	SELECT 
	product_key,
	product_name,
	cost,
	CASE WHEN cost < 100 THEN 'Below 100'
		 WHEN cost BETWEEN 100 AND 500 THEN '100-500'
		 WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
		 WHEN cost BETWEEN 1000 AND 1500 THEN '1000-1500'
		 WHEN cost BETWEEN 1500 AND 2000 THEN '1500-2000'
		 ELSE 'MORE THAN - 2000'
	END cost_range
	FROM gold.dim_products
)
SELECT 
cost_range,
COUNT(product_key)
FROM segment_product
GROUP BY cost_range;


-- Q)Group customers into three segments based on their spending behavior:
--   - VIP: at least 12 months of history and spending more than €5,000.
--   - Regular: at least 12 months of history but spending €5,000 or less.
--   - New: lifespan less than 12 months.
--   And find the total number of customers by each group.
WITH segments AS 
(
	SELECT 
		cu.customer_key,
		SUM(sls.sales_amount) AS Total_spending,
		DATEDIFF(MONTH ,MIN(order_date) ,MAX(order_date)) AS lifespan_in_months
	FROM gold.fact_sales as sls
	LEFT JOIN gold.dim_customers AS cu
	ON cu.customer_key = sls.customer_key
	GROUP BY cu.customer_key
)

SELECT
	tags,
	COUNT(customer_key) AS total_customers
FROM(
	SELECT 
		customer_key,
		CASE WHEN lifespan_in_months >= 12 AND Total_spending > 5000 THEN 'VIP'
			 WHEN lifespan_in_months >= 12 AND Total_spending <= 5000 THEN 'REGULAR'
			 ELSE 'NEW'
		END tags 
	FROM segments
)T
GROUP BY tags
ORDER BY COUNT(customer_key) DESC


--===================================================================================================================================

-- F) Build customer report


/*  Customer Report  Purpose: - This report consolidates key customer metrics and behaviors Highlights: 
		1. Gathers essential fields such as names, ages, and transaction details. 
		2. Segments customers into categories (VIP, Regular, New) and age groups. 
		3. Aggregates customer-level metrics: 
			- total orders 
			- total sales 
			- total quantity purchased 
			- total products 
			- lifespan (in months) 
		4. Calculates valuable KPIs: - recency (months since last order) 
									 - average order value 
									 - average monthly spend
*/ 

IF OBJECT_ID('gold.report_customers', 'V') IS NOT NULL
    DROP VIEW gold.report_customers;
GO

CREATE VIEW gold.report_customers AS

WITH base_query AS(
/*---------------------------------------------------------------------------
1) Base Query: Retrieves core columns from tables
---------------------------------------------------------------------------*/
SELECT
f.order_number,
f.product_key,
f.order_date,
f.sales_amount,
f.quantity,
c.customer_key,
c.customer_number,
CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
DATEDIFF(year, c.birthdate, GETDATE()) age
FROM gold.fact_sales f
LEFT JOIN gold.dim_customers c
ON c.customer_key = f.customer_key
WHERE order_date IS NOT NULL)

, customer_aggregation AS (
/*---------------------------------------------------------------------------
2) Customer Aggregations: Summarizes key metrics at the customer level
---------------------------------------------------------------------------*/
SELECT 
	customer_key,
	customer_number,
	customer_name,
	age,
	COUNT(DISTINCT order_number) AS total_orders,
	SUM(sales_amount) AS total_sales,
	SUM(quantity) AS total_quantity,
	COUNT(DISTINCT product_key) AS total_products,
	MAX(order_date) AS last_order_date,
	DATEDIFF(month, MIN(order_date), MAX(order_date)) AS lifespan
FROM base_query
GROUP BY 
	customer_key,
	customer_number,
	customer_name,
	age
)
SELECT
customer_key,
customer_number,
customer_name,
age,
CASE 
	 WHEN age < 20 THEN 'Under 20'
	 WHEN age between 20 and 29 THEN '20-29'
	 WHEN age between 30 and 39 THEN '30-39'
	 WHEN age between 40 and 49 THEN '40-49'
	 ELSE '50 and above'
END AS age_group,
CASE 
    WHEN lifespan >= 12 AND total_sales > 5000 THEN 'VIP'
    WHEN lifespan >= 12 AND total_sales <= 5000 THEN 'Regular'
    ELSE 'New'
END AS customer_segment,
last_order_date,
DATEDIFF(month, last_order_date, GETDATE()) AS recency,
total_orders,
total_sales,
total_quantity,
total_products
lifespan,
-- Compuate average order value (AVO)
CASE WHEN total_sales = 0 THEN 0
	 ELSE total_sales / total_orders
END AS avg_order_value,
-- Compuate average monthly spend
CASE WHEN lifespan = 0 THEN total_sales
     ELSE total_sales / lifespan
END AS avg_monthly_spend
FROM customer_aggregation;


SELECT *
FROM gold.report_customers
