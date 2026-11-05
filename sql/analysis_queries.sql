-- =============================================================
-- Supply Chain Delivery Risk: key SQL (DuckDB dialect)
-- Tables built in notebooks/01: orders (all lines), shipped (excludes cancelled)
-- =============================================================

-- 1. Promised vs actual days and late rate by shipping mode
SELECT shipping_mode,
       COUNT(*)                     AS lines,
       ROUND(AVG(days_promised), 2) AS avg_days_promised,
       ROUND(AVG(days_actual), 2)   AS avg_days_actual,
       ROUND(AVG(is_late), 3)       AS late_rate
FROM shipped
GROUP BY shipping_mode
ORDER BY avg_days_promised;

-- 2. Spread of late rate across dimensions (which one actually explains lateness?)
SELECT 'market' AS dimension, MIN(r) AS lowest, MAX(r) AS highest
FROM (SELECT AVG(is_late) AS r FROM shipped GROUP BY market)
UNION ALL
SELECT 'order_region', MIN(r), MAX(r) FROM (SELECT AVG(is_late) AS r FROM shipped GROUP BY order_region)
UNION ALL
SELECT 'shipping_mode', MIN(r), MAX(r) FROM (SELECT AVG(is_late) AS r FROM shipped GROUP BY shipping_mode);

-- 3. Risk ranking: top 10 region x mode by late lines, with running share (window functions + QUALIFY)
WITH combo AS (
    SELECT order_region, shipping_mode,
           COUNT(*)      AS lines,
           SUM(is_late)  AS late_lines,
           AVG(is_late)  AS late_rate
    FROM shipped
    GROUP BY order_region, shipping_mode
)
SELECT RANK() OVER (ORDER BY late_lines DESC) AS priority,
       order_region, shipping_mode, lines, late_lines, ROUND(late_rate, 3) AS late_rate,
       ROUND(100.0 * SUM(late_lines) OVER (ORDER BY late_lines DESC) / SUM(late_lines) OVER (), 1) AS cumulative_pct_of_late
FROM combo
QUALIFY priority <= 10
ORDER BY priority;

-- 4. Profit: late vs on-time orders (aggregate to order level first)
WITH o AS (
    SELECT order_id, MAX(is_late) AS late, SUM(profit) AS profit
    FROM shipped
    GROUP BY order_id
)
SELECT late, COUNT(*) AS orders, ROUND(AVG(profit), 2) AS avg_profit_per_order
FROM o
GROUP BY late;

-- 5. Fraud concentration by payment type
SELECT payment_type,
       COUNT(*) AS lines,
       SUM(CASE WHEN is_suspected_fraud THEN 1 ELSE 0 END) AS fraud_lines,
       ROUND(100 * AVG(CASE WHEN is_suspected_fraud THEN 1 ELSE 0 END), 1) AS fraud_rate_pct
FROM orders
GROUP BY payment_type
ORDER BY fraud_lines DESC;

-- 6. Scenario: late rate if promises matched what each mode actually achieves
WITH promise AS (
    SELECT * FROM (VALUES ('First Class', 2), ('Second Class', 4), ('Standard Class', 4), ('Same Day', 1))
             AS t(shipping_mode, realistic_days)
)
SELECT s.shipping_mode,
       ROUND(AVG(s.is_late), 3)                                                   AS late_rate_now,
       ROUND(AVG(CASE WHEN s.days_actual > p.realistic_days THEN 1 ELSE 0 END), 3) AS late_rate_realistic
FROM shipped s
JOIN promise p USING (shipping_mode)
GROUP BY s.shipping_mode;
