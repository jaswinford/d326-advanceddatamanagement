-- Verify creation of report_customer_details table
SELECT * FROM report_customer_details;

-- Verify creation of report_location_summary table
SELECT * FROM report_location_summary;

-- Test format_active_status function
SELECT format_active_status(1) AS formatted_status; -- Should return 'Active'
SELECT format_active_status(0) AS formatted_status; -- Should return 'Inactive'

-- Test trigger for report_customer_details

SELECT * FROM report_location_summary WHERE location_id = 1;

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
) VALUES (
	1001,
	'John Doe',
	'Saint-Denis',
	'Runion',
	1000.00,
	5,
	10,
	'2023-10-01',
	'Active'
);
