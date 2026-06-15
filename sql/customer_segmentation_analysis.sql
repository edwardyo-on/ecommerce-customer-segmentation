.headers on
.mode column

/*
E-Commerce Customer Segmentation SQL Analysis

SQL dialect: SQLite

Project:
E-Commerce Customer Segmentation and Retention Analysis

Purpose:
This SQL script recreates the core SQL workflow for the e-commerce customer segmentation project.
It cleans transaction data, builds customer-level RFM metrics, creates customer segments,
and summarizes revenue by segment, product, country, and customer concentration.

Expected input table:
online_retail

Expected columns:
- invoiceno
- stockcode
- description
- quantity
- invoicedate
- unitprice
- customerid
- country

Workflow:
1. Data quality summary
2. Clean transactions
3. Create customer-level RFM metrics
4. Calculate customer order metrics
5. Create business-rule customer segments
6. Summarize revenue by customer segment
7. Analyze top products by revenue
8. Analyze revenue by country
9. Identify top customers by revenue
10. Measure revenue concentration
11. Create a segment action plan
*/


/* ============================================================
   1. Data quality summary
   ============================================================ */

.print ''
.print '1. Data quality summary'

SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN customerid IS NULL THEN 1 ELSE 0 END) AS missing_customerid_rows,
    SUM(CASE WHEN quantity <= 0 THEN 1 ELSE 0 END) AS non_positive_quantity_rows,
    SUM(CASE WHEN unitprice <= 0 THEN 1 ELSE 0 END) AS non_positive_unitprice_rows,
    SUM(CASE WHEN invoiceno LIKE 'C%' THEN 1 ELSE 0 END) AS canceled_invoice_rows
FROM online_retail;


/* ============================================================
   2. Clean transactions
   ============================================================

   Removes:
   - Missing customer IDs
   - Negative or zero quantities
   - Negative or zero unit prices
   - Canceled invoices beginning with 'C'

   Adds:
   - revenue = quantity * unitprice
*/

DROP VIEW IF EXISTS cleaned_transactions;

CREATE VIEW cleaned_transactions AS
SELECT
    invoiceno,
    stockcode,
    description,
    quantity,
    invoicedate,
    unitprice,
    customerid,
    country,
    ROUND(quantity * unitprice, 2) AS revenue
FROM online_retail
WHERE customerid IS NOT NULL
  AND quantity > 0
  AND unitprice > 0
  AND invoiceno NOT LIKE 'C%';


.print ''
.print '2. Cleaned transaction summary'

SELECT
    COUNT(*) AS cleaned_rows,
    COUNT(DISTINCT customerid) AS unique_customers,
    COUNT(DISTINCT invoiceno) AS unique_orders,
    COUNT(DISTINCT stockcode) AS unique_products,
    ROUND(SUM(revenue), 2) AS total_revenue,
    MIN(invoicedate) AS first_transaction_date,
    MAX(invoicedate) AS last_transaction_date
FROM cleaned_transactions;


/* ============================================================
   3. Create customer-level RFM metrics
   ============================================================

   Recency:
   Days since the customer's most recent purchase.
   Uses a snapshot date equal to one day after the latest transaction date.

   Frequency:
   Number of unique invoices per customer.

   Monetary value:
   Total revenue per customer.
*/

DROP VIEW IF EXISTS customer_rfm;

CREATE VIEW customer_rfm AS
SELECT
    customerid,

    ROUND(
        JULIANDAY(
            (SELECT DATETIME(MAX(invoicedate), '+1 day') FROM cleaned_transactions)
        ) - JULIANDAY(MAX(invoicedate)),
        0
    ) AS recency,

    COUNT(DISTINCT invoiceno) AS frequency,
    ROUND(SUM(revenue), 2) AS monetary_value,
    COUNT(DISTINCT stockcode) AS unique_products,
    MIN(invoicedate) AS first_purchase,
    MAX(invoicedate) AS last_purchase
FROM cleaned_transactions
GROUP BY customerid;


/* ============================================================
   4. Calculate customer order metrics
   ============================================================

   First calculates revenue per invoice.
   Then calculates average and maximum order value by customer.
*/

DROP VIEW IF EXISTS customer_order_values;

CREATE VIEW customer_order_values AS
SELECT
    customerid,
    invoiceno,
    ROUND(SUM(revenue), 2) AS order_value
FROM cleaned_transactions
GROUP BY customerid, invoiceno;


DROP VIEW IF EXISTS customer_order_metrics;

CREATE VIEW customer_order_metrics AS
SELECT
    customerid,
    ROUND(AVG(order_value), 2) AS avg_order_value,
    ROUND(MAX(order_value), 2) AS max_order_value
FROM customer_order_values
GROUP BY customerid;


/* ============================================================
   5. Combine RFM metrics with order metrics
   ============================================================ */

DROP VIEW IF EXISTS customer_rfm_enriched;

CREATE VIEW customer_rfm_enriched AS
SELECT
    r.customerid,
    r.recency,
    r.frequency,
    r.monetary_value,
    o.avg_order_value,
    o.max_order_value,
    r.unique_products,
    r.first_purchase,
    r.last_purchase
FROM customer_rfm r
LEFT JOIN customer_order_metrics o
    ON r.customerid = o.customerid;


/* ============================================================
   6. Create customer segments
   ============================================================

   Segments are based on simple business rules using:
   - recency
   - frequency
   - monetary value

   These thresholds are intentionally easy to understand for a business audience.
*/

DROP VIEW IF EXISTS customer_segments;

CREATE VIEW customer_segments AS
SELECT
    customerid,
    recency,
    frequency,
    monetary_value,
    avg_order_value,
    max_order_value,
    unique_products,
    first_purchase,
    last_purchase,

    CASE
        WHEN recency <= 30
             AND frequency >= 10
             AND monetary_value >= 5000
            THEN 'Champions'

        WHEN recency <= 90
             AND frequency >= 5
            THEN 'Loyal Customers'

        WHEN recency <= 30
             AND monetary_value >= 1000
            THEN 'Recent High-Value'

        WHEN recency <= 60
             AND frequency <= 2
            THEN 'New/Potential Customers'

        WHEN recency > 180
             AND monetary_value >= 2000
            THEN 'At-Risk High-Value'

        WHEN recency > 180
             AND frequency >= 3
            THEN 'At Risk'

        WHEN recency > 180
             AND frequency <= 2
            THEN 'Inactive/Low Engagement'

        ELSE 'Needs Attention'
    END AS customer_segment
FROM customer_rfm_enriched;


/* ============================================================
   7. Revenue summary by customer segment
   ============================================================ */

.print ''
.print '3. Revenue summary by customer segment'

SELECT
    customer_segment,
    COUNT(*) AS customers,
    ROUND(
        100.0 * COUNT(*) / (SELECT COUNT(*) FROM customer_segments),
        2
    ) AS customer_percentage,
    ROUND(AVG(recency), 2) AS avg_recency,
    ROUND(AVG(frequency), 2) AS avg_frequency,
    ROUND(AVG(monetary_value), 2) AS avg_monetary_value,
    ROUND(AVG(avg_order_value), 2) AS avg_order_value,
    ROUND(SUM(monetary_value), 2) AS total_revenue,
    ROUND(
        100.0 * SUM(monetary_value) / (SELECT SUM(monetary_value) FROM customer_segments),
        2
    ) AS revenue_percentage
FROM customer_segments
GROUP BY customer_segment
ORDER BY total_revenue DESC;


/* ============================================================
   8. Top 10 products by revenue
   ============================================================

   Excludes non-product transaction codes such as postage,
   manual charges, bank charges, and fees.
*/

.print ''
.print '4. Top 10 products by revenue'

SELECT
    stockcode,
    description,
    SUM(quantity) AS total_quantity,
    ROUND(SUM(revenue), 2) AS total_revenue,
    COUNT(DISTINCT customerid) AS unique_customers,
    COUNT(DISTINCT invoiceno) AS total_orders,
    ROUND(SUM(revenue) / COUNT(DISTINCT invoiceno), 2) AS avg_revenue_per_order
FROM cleaned_transactions
WHERE stockcode NOT IN (
    'POST',
    'M',
    'BANK CHARGES',
    'AMAZONFEE',
    'DOT',
    'CRUK'
)
GROUP BY stockcode, description
ORDER BY total_revenue DESC
LIMIT 10;


/* ============================================================
   9. Revenue by country
   ============================================================ */

.print ''
.print '5. Revenue by country'

SELECT
    country,
    ROUND(SUM(revenue), 2) AS total_revenue,
    ROUND(
        100.0 * SUM(revenue) / (SELECT SUM(revenue) FROM cleaned_transactions),
        2
    ) AS revenue_percentage,
    COUNT(DISTINCT customerid) AS unique_customers,
    COUNT(DISTINCT invoiceno) AS total_orders,
    ROUND(SUM(revenue) / COUNT(DISTINCT invoiceno), 2) AS avg_order_revenue
FROM cleaned_transactions
GROUP BY country
ORDER BY total_revenue DESC;


/* ============================================================
   10. Top 10 customers by revenue
   ============================================================ */

.print ''
.print '6. Top 10 customers by revenue'

SELECT
    customerid,
    recency,
    frequency,
    monetary_value,
    ROUND(
        100.0 * monetary_value / (SELECT SUM(monetary_value) FROM customer_segments),
        2
    ) AS revenue_percentage,
    avg_order_value,
    max_order_value,
    unique_products,
    customer_segment
FROM customer_segments
ORDER BY monetary_value DESC
LIMIT 10;


/* ============================================================
   11. Revenue concentration by customer decile
   ============================================================

   Shows how much revenue comes from the top customers.
   Useful for identifying whether the business depends heavily
   on a small group of customers.
*/

.print ''
.print '7. Revenue concentration by customer decile'

WITH customer_revenue_ranked AS (
    SELECT
        customerid,
        monetary_value,
        NTILE(10) OVER (ORDER BY monetary_value DESC) AS revenue_decile
    FROM customer_segments
)

SELECT
    revenue_decile,
    COUNT(*) AS customers,
    ROUND(SUM(monetary_value), 2) AS total_revenue,
    ROUND(
        100.0 * SUM(monetary_value) / (
            SELECT SUM(monetary_value) FROM customer_segments
        ),
        2
    ) AS revenue_percentage
FROM customer_revenue_ranked
GROUP BY revenue_decile
ORDER BY revenue_decile;


/* ============================================================
   12. Top 10 percent and top 20 percent revenue concentration
   ============================================================ */

.print ''
.print '8. Top customer revenue concentration'

WITH ranked_customers AS (
    SELECT
        customerid,
        monetary_value,
        ROW_NUMBER() OVER (ORDER BY monetary_value DESC) AS revenue_rank,
        COUNT(*) OVER () AS total_customers
    FROM customer_segments
),

concentration_summary AS (
    SELECT
        customerid,
        monetary_value,
        revenue_rank,
        total_customers,
        CASE
            WHEN revenue_rank <= total_customers * 0.10 THEN 'Top 10%'
            WHEN revenue_rank <= total_customers * 0.20 THEN 'Top 20%'
            ELSE 'Remaining Customers'
        END AS customer_group
    FROM ranked_customers
)

SELECT
    customer_group,
    COUNT(*) AS customers,
    ROUND(SUM(monetary_value), 2) AS total_revenue,
    ROUND(
        100.0 * SUM(monetary_value) / (
            SELECT SUM(monetary_value) FROM customer_segments
        ),
        2
    ) AS revenue_percentage
FROM concentration_summary
GROUP BY customer_group
ORDER BY
    CASE
        WHEN customer_group = 'Top 10%' THEN 1
        WHEN customer_group = 'Top 20%' THEN 2
        ELSE 3
    END;


/* ============================================================
   13. Segment action plan
   ============================================================

   Adds business recommendations for each customer segment.
*/

.print ''
.print '9. Segment action plan'

SELECT
    customer_segment,

    CASE
        WHEN customer_segment = 'Champions'
            THEN 'Very High'

        WHEN customer_segment = 'Loyal Customers'
            THEN 'High'

        WHEN customer_segment = 'Recent High-Value'
            THEN 'High'

        WHEN customer_segment = 'At-Risk High-Value'
            THEN 'Very High'

        WHEN customer_segment = 'New/Potential Customers'
            THEN 'Medium'

        WHEN customer_segment = 'At Risk'
            THEN 'Medium'

        WHEN customer_segment = 'Needs Attention'
            THEN 'Medium'

        WHEN customer_segment = 'Inactive/Low Engagement'
            THEN 'Low'

        ELSE 'Medium'
    END AS business_priority,

    CASE
        WHEN customer_segment = 'Champions'
            THEN 'Reward with VIP offers, loyalty perks, and early product access.'

        WHEN customer_segment = 'Loyal Customers'
            THEN 'Use personalized recommendations and loyalty campaigns to increase repeat purchases.'

        WHEN customer_segment = 'Recent High-Value'
            THEN 'Encourage a second purchase with targeted bundles or limited-time offers.'

        WHEN customer_segment = 'At-Risk High-Value'
            THEN 'Prioritize win-back campaigns with personalized discounts or direct outreach.'

        WHEN customer_segment = 'New/Potential Customers'
            THEN 'Send onboarding emails and product discovery recommendations.'

        WHEN customer_segment = 'At Risk'
            THEN 'Use reactivation campaigns and reminder offers.'

        WHEN customer_segment = 'Inactive/Low Engagement'
            THEN 'Limit marketing spend unless the customer has strong historical value.'

        ELSE 'Monitor behavior and test targeted engagement campaigns.'
    END AS recommended_action,

    COUNT(*) AS customers,
    ROUND(SUM(monetary_value), 2) AS total_revenue,
    ROUND(
        100.0 * SUM(monetary_value) / (SELECT SUM(monetary_value) FROM customer_segments),
        2
    ) AS revenue_percentage
FROM customer_segments
GROUP BY customer_segment
ORDER BY total_revenue DESC;