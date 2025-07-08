---
title: "Advanced Data Management D191 | D326 Performance Assessment"
description: "This document outlines the requirements for the Advanced Data Management D191 | D326 Performance Assessment, including tasks related to the DVD Dataset."
author: "James A. Swinford"
---

## A.  One real-world business problem that can be solved using the DVD Dataset

A report for "Top Customers and Revenue by Location" would be beneficial for a DVD rental business. This report would provide insights into customer spending patterns and revenue generation across different locations, helping the business to identify high-value customers and profitable markets.

### 1.  Identify the specific fields that will be included in the detailed table and the summary table of the report.

- Detailed Table Fields:
    - Customer ID (customer.customer_id)
    - Customer Name (customer.first_name + customer.last_name)
    - City (city.city)
    - Country (country.country)
    - Total Spent (payment.amount summation)
    - Total Payments Made (payment.payment_id count)
    - Total Rentals (rental.rental_id count)
    - Last Rental Date (rental.rental_date max)
    - Active Status (customer.active, transformed to "Active"/"Inactive")

- Summary Table Fields:
    - City (city.city)
    - Country (country.country)
    - Average Spend per Customer
    - Total Revenue Generated
    - Percentage Contribution to Total Revenue
    - Number of Active Customers

### 2.  Describe the types of data fields used for the report.

- Text Fields: Customer Name, City, Country
- Numeric Fields: Total Spent, Total Payments/rentals, average spend.
- Date Fields: Last Rental Date
- Boolean Fields: Active Status (transformed to text)

### 3.  Identify at least two specific tables from the given dataset that will provide the data necessary for the detailed table section and the summary table section of the report.

- Detailed Table: 
    - customer
    - payment
    - address
    - city
    - country
- Summary Table:
    - customer
    - payment

### 4.  Identify at least one field in the detailed table section that will require a custom transformation with a user-defined function and explain why it should be transformed (e.g., you might translate a field with a value of N to No and Y to Yes).
    
- Field: Active Status (customer.active)
- Transformation: Convert boolean values (1 for active, 0 for inactive) to text values ("Active" and "Inactive").
- Reason: This transformation makes the report more user-friendly and easier to understand for stakeholders who may not be familiar with boolean values.

### 5.  Explain the different business uses of the detailed table section and the summary table section of the report.

- Detailed Table Section:
    - Provides granular insights into individual customer transactions, allowing for targeted marketing strategies and personalized customer service.
    - Helps identify high-value customers and their purchasing patterns.
    - Useful for operational decisions, such as inventory management based on customer preferences.
- Summary Table Section:
    - Offers a high-level overview of customer behavior and revenue generation by location.
    - Assists in strategic decision-making, such as identifying profitable markets and regions for expansion.
    - Useful for financial reporting and performance analysis at the organizational level. 

### 6.  Explain how frequently your report should be refreshed to remain relevant to stakeholders.

The report should be refreshed monthly to ensure that stakeholders have access to the most current data on customer behavior and revenue generation. This frequency allows for timely adjustments in marketing strategies and operational decisions based on recent trends and performance metrics.

## B.  Provide original code for function(s) in text format that perform the transformation(s) you identified in part A4.

```sql
CREATE OR REPLACE FUNCTION format_active_status(active INT)
RETURNS TEXT AS $$
BEGIN
  RETURN CASE WHEN active = 1 THEN 'Active' ELSE 'Inactive' END;
END;
$$ LANGUAGE plpgsql;
```

## C.  Provide original SQL code in a text format that creates the detailed and summary tables to hold your report table sections.

### Detailed Table Creation

```sql
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
```

### Summary Table Creation

```sql
CREATE TABLE report_location_summary AS
SELECT
  city,
  country,
  COUNT(customer_id) AS total_customers,
  SUM(total_spent) AS total_revenue,
  AVG(total_spent) AS avg_spend_per_customer,
  COUNT(CASE WHEN active_status = 'Active' THEN 1 END) AS active_customers,
  (SUM(total_spent) * 100.0) / (SELECT SUM(total_spent) FROM report_customer_details)) AS revenue_percentage_contribution
FROM report_customer_details
GROUP BY city, country
ORDER BY total_revenue DESC;
```

## D.  Provide an original SQL query in a text format that will extract the raw data needed for the detailed section of your report from the source database.

The data is extracted as part of the detailed table creation in part C.

## E.  Provide original SQL code in a text format that creates a trigger on the detailed table of the report that will continually update the summary table as data is added to the detailed table.

### Trigger Function

```sql
CREATE OR REPLACE FUNCTION update_location_summary()
RETURNS TRIGGER AS $$
DECLARE
  total_revenue NUMERIC;
BEGIN
  -- Delete existing summary row for the new customer's city/country
  DELETE FROM report_location_summary
  WHERE city = NEW.city AND country = NEW.country;

  -- Recalculate summary for the city/country using all relevant detailed rows
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
    ROUND(AVG(total_spent), 2),
    COUNT(CASE WHEN active_status = 'Active' THEN 1 END),
    -- Calculate percentage contribution using global total revenue
    ROUND(
      (SUM(total_spent) * 100.0) / (SELECT SUM(total_spent) FROM report_customer_details),
      2
    )
  FROM report_customer_details
  WHERE city = NEW.city AND country = NEW.country
  GROUP BY city, country;

  -- Update percentage contributions for ALL rows (due to new global total)
  SELECT SUM(total_spent) INTO total_revenue FROM report_customer_details;
  UPDATE report_location_summary
  SET revenue_percentage_contribution = ROUND((total_revenue / total_revenue) * 100, 2)
  WHERE revenue_percentage_contribution IS NOT NULL;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

### Trigger Creation

```sql
CREATE TRIGGER trigger_update_summary
AFTER INSERT ON report_customer_details
FOR EACH ROW
EXECUTE FUNCTION update_location_summary();
```

## F.  Provide an original stored procedure in a text format that can be used to refresh the data in both the detailed table and summary table. The procedure should clear the contents of the detailed table and summary table and perform the raw data extraction from part D.

```sql
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
    ROUND(AVG(total_spent), 2),
    COUNT(CASE WHEN active_status = 'Active' THEN 1 END),
    ROUND(
      (SUM(total_spent) * 100.0) / NULLIF((SELECT SUM(total_spent) FROM report_customer_details), 0), 
      2
    )
  FROM report_customer_details
  GROUP BY city, country;

  COMMIT;
END;
$$;
```

### 1.  Identify a relevant job scheduling tool that can be used to automate the stored procedure.

A relevant job scheduling tool that can be used to automate the stored procedure is **pgAgent**. This is a job scheduling agent for PostgreSQL that allows users to schedule and run SQL scripts, including stored procedures, at specified intervals or times.
As an alternative, you can also use **cron jobs** on Linux systems or **Task Scheduler** on Windows to execute the stored procedure at regular intervals.

## H. Acknowledge outside sources.
No outside sources were used in the creation of this document. All content is original and based on the provided dataset and requirements.
