IF OBJECT_ID('Dev.GetWrapperSQLSemaphore', 'P') IS NULL
	EXEC ('CREATE PROCEDURE Dev.GetWrapperSQLSemaphore AS;');
GO

ALTER PROCEDURE Dev.GetWrapperSQLSemaphore
@NoOfSlots int,
@CodeBlockID nvarchar(50),
@SchemaName nvarchar(128) = 'dbo'
AS
/*
	Summary
	-------
	This procedure returns SQL code that serves as a wrapper for a block of SQL
	code (or, most conveniently, a single stored-procedure call) that needs to
	have the concurrency of sessions running it limited. This procedure will
	typically be used during development, not in production code.
		
	Details
	-------
	The block of code that needs wrapping will be referred to as "actual work"
	both in this description and in the comment in the generated wrapper that
	marks where it needs to be pasted.
	
	The wrapper produces the effect of letting sessions enter "actual work" freely as long as the number of such sessions has not reached the specified
	limit. When the limit has been reached,
	additional sessions trying to run "actual work" are blocked and they
	effectively join a queue of waiting sessions. Each previously entered session
	that leaves "actual work" causes a queued-up session to enter "actual work".

	Parameters
	----------
		@NoOfSlots: the maximum number of simultaneous sessions allowed to enter
			"actual work". The number is hard-coded in the wrapper at the top. It
			may be changed at will after the wrapper is created.
			
			@NoOfSlots should be in the range from 1 to 22. Values greater than
			that are disallowed because they are unlikely to be needed and
			performance can degrade at higher values.
		@CodeBlockID: a unique string identifying one concurrency constraint.
			Typically, a unique @CodeBlockID will be needed for each "actual work"
			block. However, it is permissible to use the same wrapper generated by
			this procedure for more than one block of code ("actual work") that
			will run on the database. In such a case, the concurrency limit applies
			to the total number of sessions entering any of the "actual work" code
			blocks.
		@SchemaName: The schema where the wrapper should create the sequence
			object needed for the Semaphore functionality.

	Notes
	-----

	This sort of concurrency-limiting measure is well suited for cases where it
	is known that increasing concurrency beyond a certain amount offers no
	additional performance benefit and in fact increases the probability of
	deadlocks. Any potentially long running "actual work" that runs as one
	transaction and acts on the same database resources repeatedly is a prime
	candidate for concurrency control.
	
	When the concurrency limit is chosen as 1, then the resulting wrapper treats
	"actual work" as a critical section that is run under an exclusive lock. For
	such a case, better performance can
	be achieved by directly using a single exclusive lock.

	The overhead of using the wrapper should be assumed to be between one-tenth
	of a microsecond and one microsecond. So if "actual work" typically completes
	in times of that order, then there
	might be a heavy performance penalty from using this SQL Semaphore.

	The logic of the SQL Semaphore is to use a SEQUENCE object to find lock
	handle that is likely to be free if there is a free slot at all. The
	@CodeBlockID effectively defines as many lock handles
	(called Resources by SQL Server) as there are allowed slots. At any time, at
	most one session is polling the different lock handles to obtain a slot at an
	interval that is between 100 and 1500 milliseconds.
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

	SET @CodeBlockID = REPLACE(REPLACE(@CodeBlockID, '[', ''), ']', '');
	SET @SchemaName = REPLACE(REPLACE(@SchemaName, '[', ''), ']', '');
	DECLARE @ObjName nvarchar(4000) = N'[' + @SchemaName + N'].[SeqSemaphore' + @CodeBlockID + N']';
	DECLARE @LockStem nvarchar(4000) = master.sys.fn_varbintohexstr(HASHBYTES('SHA1', @CodeBlockID));
	DECLARE @Template nvarchar(max) = 
	N'DECLARE @NoOfSlots int = {NoOfSlots};

	IF NOT (ISNULL(@NoOfSlots, 0) BETWEEN 1 AND 22)
	BEGIN
		RAISERROR (''@NoOfSlots should be in the range 1 to 22.'', 16, 1) WITH SETERROR;
		RETURN;
	END;

	IF OBJECT_ID(N''{ObjName}'', ''SO'') IS NULL
	BEGIN
		BEGIN TRY;
			CREATE SEQUENCE {ObjName} AS int
				START WITH 0
				INCREMENT BY 1
				MINVALUE 0
				MAXVALUE 232792559
				CYCLE;
		END TRY
		BEGIN CATCH
		END CATCH;
	END;

	DECLARE @RsrcName nvarchar(255);
	DECLARE @RetCode int;
	DECLARE @SeqValue int;
	DECLARE @TimeoutMilliseconds int = 0;
	DECLARE @Iter int = 0;

	EXEC sp_getapplock @Resource=N''{LockStem}'', @LockMode=''Exclusive'', @LockOwner=''Session'', @LockTimeout=-1;

	SELECT @SeqValue = NEXT VALUE FOR {ObjName};
	SET @SeqValue = @SeqValue % @NoOfSlots;
	SET @RsrcName = N''{LockStem}'' + CAST(@SeqValue AS nvarchar(255));
	EXEC @RetCode=sp_getapplock @Resource=@RsrcName, @LockMode=''Exclusive'', @LockOwner=''Session'', @LockTimeout=@TimeoutMilliseconds;
	WHILE @RetCode < 0
	BEGIN
		SELECT @SeqValue = NEXT VALUE FOR {ObjName};
		SET @SeqValue = @SeqValue % @NoOfSlots;
		SET @RsrcName = N''{LockStem}'' + CAST(@SeqValue AS nvarchar(255));

		SET @Iter = @Iter + 1;
		IF @Iter % @NoOfSlots = 0
		BEGIN
			IF @TimeoutMilliseconds < 1500
				SET @TimeoutMilliseconds = @TimeoutMilliseconds + 100;
			EXEC @RetCode=sp_getapplock @Resource=@RsrcName, @LockMode=''Exclusive'', @LockOwner=''Session'', @LockTimeout=@TimeoutMilliseconds;
		END;
		ELSE
			EXEC @RetCode=sp_getapplock @Resource=@RsrcName, @LockMode=''Exclusive'', @LockOwner=''Session'', @LockTimeout=0;
	END;

	EXEC sp_releaseapplock @Resource=N''{LockStem}'', @LockOwner=''Session'';

	DECLARE @ErrorOccurred bit = 0;
	BEGIN TRY
		------------------------------------
		--- "Actual work" goes here.
		------------------------------------
	END TRY
	BEGIN CATCH
		SET @ErrorOccurred = 1;
		{ThrowCode}
	END CATCH;

	IF @ErrorOccurred = 0
		EXEC sp_releaseapplock @Resource=@RsrcName, @LockOwner=''Session'';';	
	
	SET @Template = REPLACE(REPLACE(REPLACE(@Template, N'{ObjName}', @ObjName), N'{LockStem}', @LockStem), N'{NoOfSlots}', CAST(@NoOfSlots AS nvarchar(4000)));	
	IF Dev.GetServerMajorVersion() >= 15
		SET @Template = REPLACE(@Template, N'{ThrowCode}', N'THROW;');
	ELSE
		SET @Template = REPLACE(@Template, N'{ThrowCode}', N'DECLARE @err nvarchar(max);
		SET @err = N''RAISERROR(''''Error #'' + CAST(ERROR_NUMBER() AS nvarchar) + N'': '' + REPLACE(ERROR_MESSAGE(), N'''''''', N'''''''''''') + N'''''', '' + CAST(ERROR_SEVERITY() AS nvarchar) + N'', '' + CAST(ERROR_STATE() AS nvarchar) + '') WITH SETERROR;'';
		EXEC(@err);');
	
	SELECT @Template;
GO

