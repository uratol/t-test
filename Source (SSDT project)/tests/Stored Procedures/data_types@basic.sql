CREATE PROC [tests].[data_types@basic]
AS
PRINT N'Compare one row of numeric, text, date and spatial types.';
PRINT N'Expect: equal values; spatial WKT and SRID match.';
SET NOCOUNT ON;

DECLARE @expected nvarchar(max), @actual nvarchar(max), @result nvarchar(max),
	@geometry geometry, @geography geography;

-- Arrange
SET @geometry = geometry::Point(12.5, 45.25, 0);
SET @geography = geography::Point(45.25, 12.5, 4326);

SET @expected = (
	SELECT
		CAST(1 AS bit) AS bit_value,
		CAST(255 AS tinyint) AS tinyint_value,
		CAST(-12345 AS smallint) AS smallint_value,
		CAST(123456789 AS int) AS int_value,
		CAST(9007199254740993 AS bigint) AS bigint_value,
		CAST(12345678901234567890.12345678 AS decimal(28, 8)) AS decimal_value,
		CAST(-1234567890.1250 AS numeric(18, 4)) AS numeric_value,
		CAST(1234.1250 AS money) AS money_value,
		CAST(-123.1250 AS smallmoney) AS smallmoney_value,
		CAST(1.23456789012345E100 AS float) AS float_value,
		CAST(1.25E0 AS real) AS real_value,
		CAST('A' AS char(4)) AS char_value,
		CAST('quote " slash \' AS varchar(100)) AS varchar_value,
		REPLICATE(CAST('x' AS varchar(max)), 5000) AS varchar_max_value,
		CAST(NCHAR(381) AS nchar(4)) AS nchar_value,
		CAST(NCHAR(0x0416) + NCHAR(0x4E2D) + NCHAR(13) + NCHAR(10) AS nvarchar(100)) AS nvarchar_value,
		REPLICATE(CAST(NCHAR(381) AS nvarchar(max)), 5000) AS nvarchar_max_value,
		CAST(0x01020304 AS binary(4)) AS binary_value,
		CAST(0x00FF1020 AS varbinary(8)) AS varbinary_value,
		CAST(0x AS varbinary(max)) AS varbinary_max_value,
		CAST('2026-03-04' AS date) AS date_value,
		CAST('05:06:07.123456' AS time(6)) AS time_value,
		CAST('2026-03-04T05:06:07.123' AS datetime) AS datetime_value,
		CAST('2026-03-04T05:06:00' AS smalldatetime) AS smalldatetime_value,
		CAST('2026-03-04T05:06:07.123456' AS datetime2(6)) AS datetime2_value,
		CAST('2026-03-04T05:06:07.123456+02:00' AS datetimeoffset(6)) AS datetimeoffset_value,
		CAST('01234567-89AB-CDEF-0123-456789ABCDEF' AS uniqueidentifier) AS uniqueidentifier_value,
		CAST(NULL AS int) AS null_value,
		CAST(N'POINT (12.5 45.25)' AS nvarchar(100)) AS geometry_wkt,
		CAST(0 AS int) AS geometry_srid,
		CAST(N'POINT (12.5 45.25)' AS nvarchar(100)) AS geography_wkt,
		CAST(4326 AS int) AS geography_srid
	FOR JSON PATH, INCLUDE_NULL_VALUES
);

-- Act
SET @actual = (
	SELECT
		@geography.STSrid AS geography_srid,
		@geography.STAsText() AS geography_wkt,
		@geometry.STSrid AS geometry_srid,
		@geometry.STAsText() AS geometry_wkt,
		CAST(NULL AS int) AS null_value,
		CAST('01234567-89AB-CDEF-0123-456789ABCDEF' AS uniqueidentifier) AS uniqueidentifier_value,
		CAST('2026-03-04T05:06:07.123456+02:00' AS datetimeoffset(6)) AS datetimeoffset_value,
		CAST('2026-03-04T05:06:07.123456' AS datetime2(6)) AS datetime2_value,
		CAST('2026-03-04T05:06:00' AS smalldatetime) AS smalldatetime_value,
		CAST('2026-03-04T05:06:07.123' AS datetime) AS datetime_value,
		CAST('05:06:07.123456' AS time(6)) AS time_value,
		CAST('2026-03-04' AS date) AS date_value,
		CAST(0x AS varbinary(max)) AS varbinary_max_value,
		CAST(0x00FF1020 AS varbinary(8)) AS varbinary_value,
		CAST(0x01020304 AS binary(4)) AS binary_value,
		REPLICATE(CAST(NCHAR(381) AS nvarchar(max)), 5000) AS nvarchar_max_value,
		CAST(NCHAR(0x0416) + NCHAR(0x4E2D) + NCHAR(13) + NCHAR(10) AS nvarchar(100)) AS nvarchar_value,
		CAST(NCHAR(381) AS nchar(4)) AS nchar_value,
		REPLICATE(CAST('x' AS varchar(max)), 5000) AS varchar_max_value,
		CAST('quote " slash \' AS varchar(100)) AS varchar_value,
		CAST('A' AS char(4)) AS char_value,
		CAST(1.25E0 AS real) AS real_value,
		CAST(1.23456789012345E100 AS float) AS float_value,
		CAST(-123.1250 AS smallmoney) AS smallmoney_value,
		CAST(1234.1250 AS money) AS money_value,
		CAST(-1234567890.1250 AS numeric(18, 4)) AS numeric_value,
		CAST(12345678901234567890.12345678 AS decimal(28, 8)) AS decimal_value,
		CAST(9007199254740993 AS bigint) AS bigint_value,
		CAST(123456789 AS int) AS int_value,
		CAST(-12345 AS smallint) AS smallint_value,
		CAST(255 AS tinyint) AS tinyint_value,
		CAST(1 AS bit) AS bit_value
	FOR JSON PATH, INCLUDE_NULL_VALUES
);

-- Assert
SET @result = test.assert_equals(N'Inline rows must match across supported scalar types', @expected, @actual);
