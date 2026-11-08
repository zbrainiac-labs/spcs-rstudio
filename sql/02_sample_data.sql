/*
 * 02_sample_data.sql -- Sample table read by R/examples/snowflake_test.R.
 *   snow sql -c <conn> --database R_SPCS_DB --schema PUBLIC -f sql/02_sample_data.sql
 */

CREATE OR REPLACE TABLE RST_SAMPLE_DATA (
    ID INT,
    CATEGORY VARCHAR(50),
    AMOUNT FLOAT,
    CREATED_AT TIMESTAMP_NTZ
)
COMMENT = 'Sample rows for the RStudio on SPCS connectivity test';

INSERT INTO RST_SAMPLE_DATA (ID, CATEGORY, AMOUNT, CREATED_AT)
VALUES
(1, 'A', 10.5, CURRENT_TIMESTAMP()),
(2, 'B', 20.3, CURRENT_TIMESTAMP()),
(3, 'A', 15.2, CURRENT_TIMESTAMP()),
(4, 'C', 8.7, CURRENT_TIMESTAMP()),
(5, 'B', 22.1, CURRENT_TIMESTAMP()),
(6, 'A', 12.9, CURRENT_TIMESTAMP()),
(7, 'C', 9.4, CURRENT_TIMESTAMP()),
(8, 'B', 18.6, CURRENT_TIMESTAMP());

SELECT
    CATEGORY,
    COUNT(*) AS ROW_COUNT
FROM RST_SAMPLE_DATA
GROUP BY CATEGORY
ORDER BY CATEGORY ASC;
