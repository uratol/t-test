CREATE proc [test].[throw]
  @message nvarchar(max)
, @proc_id int = null
as

	declare @err_num int = 70000

	if @proc_id is not null
	begin
		set @message += concat('
<Procedure:> ', isnull(
		quotename(
		object_schema_name(@proc_id)
		)
		+ '.'
		+ quotename(
		object_name(@proc_id)
		)
		, @proc_id)
		);
	end

	exec test.log @message = @message, @severity = 'error', @proc_id = @proc_id;

	set @message = replace(@message, '%', '%%');

	throw @err_num, @message, 1;