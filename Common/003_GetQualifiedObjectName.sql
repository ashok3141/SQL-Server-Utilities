IF OBJECT_ID('Dev.GetQualifiedObjectName', 'FN') IS NULL
	EXEC('CREATE FUNCTION Dev.GetQualifiedObjectName() RETURNS nvarchar(4000) AS BEGIN RETURN NULL; END;');
GO

ALTER FUNCTION Dev.GetQualifiedObjectName(@ObjectId int = NULL, @ObjectName nvarchar(4000) = NULL, @ObjectType char(2) = NULL)
RETURNS nvarchar(4000)
AS
BEGIN
	/*
		The function returns a qualified (i.e., schema-qualified) name of a database
		object referred to by the parameters, if one is found, or NULL otherwise.
		It also provides complete safety from SQL injection, because the names are
		always constructed purely from system views.
		
		Parameters
		----------
		@ObjectId: The object id of the object whose name is being looked up. If
			this is not NULL, then the other arguments are ignored.
		@ObjectName: The name of the object in any format that would be acceptable
			to the built-in OBJECT_NAME() function. The object name will only ever
			be used as an argument for the OBJECT_NAME() function, so there need be
			no concerns about SQL injection.
		@ObjectType: An optional parameter to restrict the type of object whose
			name will be returned. If NULL is passed (which is the DEFAULT) value,
			then any type of object may be matched, but if it is not NULL, then
			only the specified type of object will be matched.
		
		Notes
		-----
		The parts of the name are enclosed in brackets ([]) only if that is required
		for their use in SQL statements.

		The lookup is based on @ObjectId if it is not NULL; otherwise it is based on
		@ObjectName and @ObjectType. If @ObjectType is not specified, then any type of
		object may be found; if it is specified, then it is used as the second parameter
		in OBJECT_ID(name, type) to restrict the type of object that may be found.

		The values (if not NULL) returned by the function may be directly used in SQL
		statements.

		Example:
			Assume that there exists a table named 'Customers' in the schema 'dbo' and a
		table named 'Contact Info' in the schema 'Cust'.
				SELECT Dev.GetQualifiedObjectName (DEFAULT, 'Customers', DEFAULT); --returns 'dbo.Customers'
				SELECT Dev.GetQualifiedObjectName (DEFAULT, 'Customers', 'U'); -- returns 'dbo.Customers'
				SELECT Dev.GetQualifiedObjectName (DEFAULT, 'Customers', 'P'); -- returns NULL
				SELECT Dev.GetQualifiedObjectName (DEFAULT, 'Cust.Contact Info', 'P'); -- returns 'Cust.[Contact Info]'				
	*/

/*
	Copyright (c) 2017 Ashok Gurumurthy

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.
*/

	DECLARE @objId int = COALESCE(@ObjectId,
		CASE WHEN @ObjectType IS NULL THEN OBJECT_ID(@ObjectName) ELSE OBJECT_ID(@ObjectName, @ObjectType) END
	);

	DECLARE @schema sysname, @name sysname;
	SELECT @schema = S.name, @name = O.name
		FROM sys.objects O
			JOIN sys.schemas S ON
				O.[schema_id] = S.[schema_id]
		WHERE O.[object_id] = @objId;

	DECLARE @ret nvarchar(4000);
	
	IF (@schema IS NOT NULL AND @name IS NOT NULL)
	BEGIN
		IF (@name NOT LIKE '[^0-9$]%' OR @name LIKE '%[^a-z0-9$_]%')
			SET @name = '[' + @name + ']';

		IF (@schema NOT LIKE '[^0-9$]%' OR @schema LIKE '%[^a-z0-9$_]%')
			SET @schema = '[' + @schema + ']';

		SET @ret = @schema + '.' + @name;
	END;

	RETURN @ret;
END;
GO

