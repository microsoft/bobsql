-- Let's pack 2 numbers, 6 and 4, into a single 8 byte
-- 6 is 0110 and 4 is 0100
-- To do this I want to store 0110 in the upper bits and 0100 in the lower bits
-- So 0110 0100 is 100 in decimal
-- But instead of treating this as 1 number I want to manipulate each on as they are separate
-- Shift left 4 bits the value of 6
-- The result is 96 which is 0110 0000
-- Now just add 4 and you get 100
-- Step 1: Pack 6 into the upper bits and 4 into the lower bits
-- The value of 100 is a byte that combines 6 in the upper bits and 4 in the lower bits
USE master;
GO
DECLARE @x tinyint;
SELECT @x = LEFT_SHIFT(6, 4) + 4;
SELECT @x = (6 << 4 ) + 4;
SELECT @x;
GO
-- Step 2: Only give me upper bits from the 100 packed value. The result should be a 6
USE master;
GO
DECLARE @x tinyint;
DECLARE @y tinyint;
SELECT @x = LEFT_SHIFT(6, 4) + 4;
SELECT @x = (6 << 4 ) + 4;
SELECT @y = RIGHT_SHIFT(@x, 4);
SELECT @y = @x >> 4;
SELECT @y;
GO
-- Step 3: Let's use SET_BIT to clear the upper bits to get the lower so the result should be a 4
USE master;
GO
DECLARE @x tinyint;
SELECT @x = LEFT_SHIFT(6, 4) + 4;
SELECT @x = (6 << 4 ) + 4;
SELECT @x = SET_BIT(@x, 4, 0);
SELECT @x = SET_BIT(@x, 5, 0);
SELECT @x = SET_BIT(@x, 6, 0);
SELECT @x = SET_BIT(@x, 7, 0);
SELECT @x;
GO

