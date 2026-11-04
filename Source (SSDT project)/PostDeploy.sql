INSERT [test].[test_vectors] (procedure_name, parameters)
SELECT N'[tests].[power@vectors]', v.parameters
FROM (VALUES (N'2,3,8'), (N'3,2,9'), (N'5,0,1'), (N'-2,3,-8')) v(parameters)
WHERE NOT EXISTS (
	SELECT 1
	FROM [test].[test_vectors] AS existing
	WHERE existing.procedure_name COLLATE Latin1_General_100_BIN2_UTF8 = N'[tests].[power@vectors]'
		AND existing.parameters COLLATE Latin1_General_100_BIN2_UTF8 = v.parameters
);
