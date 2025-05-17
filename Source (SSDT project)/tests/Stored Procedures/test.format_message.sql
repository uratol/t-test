CREATE procedure [tests].[test.format_message]
as
begin tran
	
	select test.assert_equals('NULL should returns NULL'
		, null
		, test.format_message(null, 1, 2, 3, 4)
		)

	select test.assert_equals('String should be substituted'
		, 'Hello world'
		, test.format_message('Hello %1', 'world', null, null, null)
		)

	declare @now datetime = getutcdate()
	select test.assert_equals('Datetime should be substituted'
		, concat('Hello at ', convert(nvarchar(10), @now, 101), ' ', convert(nvarchar(5), @now, 114))
		, test.format_message('Hello at %2', null, @now, null, null)
		)

	select test.assert_equals('Binary should be substituted'
		, 'Hello binary: 0x010203'
		, test.format_message('Hello binary: %1', 0x010203, null, null, null)
		)


rollback