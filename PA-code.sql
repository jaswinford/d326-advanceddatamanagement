-- Transformation Function

CREATE OR REPLACE FUNCTION format_active_status(active INT)
RETURNS TEXT AS $$
BEGIN
  RETURN CASE WHEN active = 1 THEN 'Active' ELSE 'Inactive' END;
END;
$$ LANGUAGE plpgsql;


-- Creation of Report Tables
-- Drop existing tables (if needed)

DROP TABLE IF EXISTS report_customer_details;
DROP TABLE IF EXISTS report_location_summary;

-- Create detailed table
CREATE TABLE report_customer_details AS
SELECT
  c.customer_id,
  c.first_name || ' ' || c.last_name AS full_name,
  ci.city,
  co.country,
  SUM(p.amount) AS total_spent,
  COUNT(DISTINCT p.payment_id) AS total_payments,
  COUNT(DISTINCT r.rental_id) AS total_rentals,
  MAX(r.rental_date) AS last_rental_date,
  format_active_status(c.active) AS active_status
FROM customer c
LEFT JOIN address a ON c.address_id = a.address_id
LEFT JOIN city ci ON a.city_id = ci.city_id
LEFT JOIN country co ON ci.country_id = co.country_id
LEFT JOIN payment p ON c.customer_id = p.customer_id
LEFT JOIN rental r ON c.customer_id = r.customer_id
GROUP BY c.customer_id, full_name, ci.city, co.country, active_status;

-- Create summary table
CREATE TABLE report_location_summary AS
SELECT
  city,
  country,
  COUNT(customer_id) AS total_customers,
  SUM(total_spent) AS total_revenue,
  AVG(total_spent) AS avg_spend_per_customer,
  COUNT(CASE WHEN active_status = 'Active' THEN 1 END) AS active_customers,
  (SUM(total_spent) * 100.0) / (SELECT SUM(total_spent) FROM report_customer_details) AS revenue_percentage_contribution
FROM report_customer_details
GROUP BY city, country
ORDER BY total_revenue DESC;

-- Create Trigger Function
CREATE OR REPLACE FUNCTION update_location_summary()
RETURNS TRIGGER AS $$
DECLARE
  global_total_revenue NUMERIC;
BEGIN
  -- Delete old summary row for the city/country
  DELETE FROM report_location_summary
  WHERE city = NEW.city AND country = NEW.country;

  -- Recalculate summary for city/country
  INSERT INTO report_location_summary (
    city,
    country,
    total_customers,
    total_revenue,
    avg_spend_per_customer,
    active_customers,
    revenue_percentage_contribution
  )
  SELECT
    city,
    country,
    COUNT(customer_id) AS total_customers,
    SUM(total_spent) AS total_revenue,
    AVG(total_spent) AS avg_spend_per_customer, -- ROUND removed
    COUNT(CASE WHEN active_status = 'Active' THEN 1 END) AS active_customers,
    -- Remove ROUND and directly compute percentage
    (
      (SUM(total_spent) * 100.0) / 
      (SELECT NULLIF(SUM(total_spent), 0) FROM report_customer_details)
    ) AS revenue_percentage_contribution
  FROM report_customer_details
  WHERE city = NEW.city AND country = NEW.country
  GROUP BY city, country;

  -- Calculate global total
  SELECT SUM(total_spent) INTO global_total_revenue
  FROM report_customer_details;

  -- Update all percentages without ROUND
  UPDATE report_location_summary
  SET revenue_percentage_contribution = (
    (total_revenue / NULLIF(global_total_revenue, 0)) * 100
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create Trigger for updating summary table after insertions in detailed table
CREATE TRIGGER trigger_update_summary
AFTER INSERT ON report_customer_details
FOR EACH ROW
EXECUTE FUNCTION update_location_summary();

-- Create a stored procedure to refresh report tables
CREATE OR REPLACE PROCEDURE refresh_report_tables()
LANGUAGE plpgsql
AS $$
BEGIN
  -- Step 1: Clear existing data from report tables
  TRUNCATE TABLE report_customer_details, report_location_summary RESTART IDENTITY;

  -- Step 2: Rebuild detailed table with fresh data extraction
  INSERT INTO report_customer_details (
    customer_id,
    full_name,
    city,
    country,
    total_spent,
    total_payments,
    total_rentals,
    last_rental_date,
    active_status
  )
  SELECT
    c.customer_id,
    c.first_name || ' ' || c.last_name AS full_name,
    ci.city,
    co.country,
    SUM(p.amount) AS total_spent,
    COUNT(DISTINCT p.payment_id) AS total_payments,
    COUNT(DISTINCT r.rental_id) AS total_rentals,
    MAX(r.rental_date) AS last_rental_date,
    CASE 
      WHEN c.active = 1 THEN 'Active' 
      ELSE 'Inactive' 
    END AS active_status
  FROM customer c
  LEFT JOIN address a ON c.address_id = a.address_id
  LEFT JOIN city ci ON a.city_id = ci.city_id
  LEFT JOIN country co ON ci.country_id = co.country_id
  LEFT JOIN payment p ON c.customer_id = p.customer_id
  LEFT JOIN rental r ON c.customer_id = r.customer_id
  GROUP BY c.customer_id, full_name, ci.city, co.country, active_status;

  -- Step 3: Rebuild summary table
  INSERT INTO report_location_summary (
    city,
    country,
    total_customers,
    total_revenue,
    avg_spend_per_customer,
    active_customers,
    revenue_percentage_contribution
  )
  SELECT
    city,
    country,
    COUNT(customer_id),
    SUM(total_spent),
    AVG(total_spent),
    COUNT(CASE WHEN active_status = 'Active' THEN 1 END),
    (SUM(total_spent) * 100.0) / NULLIF((SELECT SUM(total_spent) FROM report_customer_details), 0), 
  FROM report_customer_details
  GROUP BY city, country;

  COMMIT;
END;
$$;

